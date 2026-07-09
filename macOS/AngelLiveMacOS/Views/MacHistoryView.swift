//
//  MacHistoryView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore

struct MacHistoryView: View {
    @Environment(HistoryModel.self) private var historyModel
    @State private var showClearAlert = false

    var body: some View {
        GeometryReader { geometry in
            if historyModel.watchList.isEmpty {
                ErrorView.empty(
                    title: "暂无历史记录",
                    message: "开始播放直播间后，会自动记录在这里。",
                    symbolName: "clock.arrow.circlepath",
                    tint: .secondary
                )
            } else {
                ScrollView {
                    historyGridView(geometry: geometry)
                }
            }
        }
        .navigationTitle("历史记录")
        .toolbar {
            if !historyModel.watchList.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("清空") {
                        showClearAlert = true
                    }
                }
            }
        }
        .alert("清空历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                historyModel.clearAll()
            }
        } message: {
            Text("确定要清空所有历史记录吗？")
        }
    }

    @ViewBuilder
    private func historyGridView(geometry: GeometryProxy) -> some View {
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20

        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 180, maximum: 260), spacing: horizontalSpacing)
            ],
            spacing: verticalSpacing
        ) {
            ForEach(historyModel.watchList, id: \.id) { room in
                HistoryRoomCardButton(room: room) {
                    LiveRoomCard(room: room, showsCoverBadge: true)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        historyModel.removeHistory(room: room)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 16)
    }
}

/// 历史记录专用卡片按钮 - 先异步查询直播状态，再决定是否打开播放器
private struct HistoryRoomCardButton<Content: View>: View {
    let room: LiveModel
    let content: Content
    @Environment(\.openWindow) private var openWindow
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(ToastManager.self) private var toastManager
    @State private var isChecking = false

    init(room: LiveModel, @ViewBuilder content: () -> Content) {
        self.room = room
        self.content = content()
    }

    var body: some View {
        Button {
            guard !isChecking else { return }
            Task {
                isChecking = true
                defer { isChecking = false }
                do {
                    let state = try await ApiManager.getCurrentRoomLiveState(
                        roomId: room.roomId,
                        userId: room.userId,
                        liveType: room.liveType
                    )
                    if state == .live {
                        fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
                    } else {
                        toastManager.show(icon: "tv.slash", message: "主播已下播")
                    }
                } catch {
                    // 查询失败时仍然放行，让播放页自行处理错误
                    fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
                }
            }
        } label: {
            content
                .overlay {
                    if isChecking {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.3))
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
