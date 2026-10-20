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
    @Environment(ToastManager.self) private var toastManager
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(\.openWindow) private var openWindow
    @State private var progressStore = ShortDramaProgressStore.shared
    @State private var showClearAlert = false
    @State private var selectedType = 0

    private var liveRooms: [LiveModel] {
        historyModel.watchList.filter { !progressStore.isShortDramaHistory($0) }
    }
    private var isEmpty: Bool { selectedType == 0 ? liveRooms.isEmpty : progressStore.historyEntries.isEmpty }
    private var selectedTitle: String { selectedType == 0 ? "直播" : "短剧" }

    var body: some View {
        VStack(spacing: 0) {
            historyTypeNavigator
            GeometryReader { _ in
                if isEmpty {
                    ErrorView.empty(
                        title: "暂无历史记录",
                        message: selectedType == 0 ? "开始播放直播间后，会自动记录在这里。" : "开始观看短剧后，最近播放的剧集和进度会显示在这里。",
                        symbolName: "clock.arrow.circlepath",
                        tint: .secondary
                    )
                } else {
                    ScrollView { historyGridView }
                }
            }
        }
        .navigationTitle("历史记录")
        .toolbar {
            if !isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("清空") { showClearAlert = true }
                }
            }
        }
        .alert("清空\(selectedTitle)历史", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive, action: clearCurrentHistory)
        } message: {
            Text(selectedType == 0 ? "确定要清空直播观看记录吗？" : "确定要清空短剧观看记录吗？续播进度仍会保留。")
        }
        .task {
            progressStore.loadHistory(legacyRooms: historyModel.watchList)
            if let warning = progressStore.historyWarning {
                toastManager.show(icon: "exclamationmark.triangle", message: warning)
            }
        }
    }

    private var historyTypeNavigator: some View {
        HStack(spacing: 16) {
            ForEach(0..<2) { index in
                let isSelected = selectedType == index
                Button { selectedType = index } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(index == 0 ? "直播" : "短剧")
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .fixedSize()

                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 20, height: 2)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(index == 0 ? "直播历史记录" : "短剧历史记录")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func clearCurrentHistory() {
        if selectedType == 0 {
            historyModel.removeHistories(ids: Set(liveRooms.map(\.id)))
        } else {
            do { try progressStore.clearHistory() }
            catch { toastManager.show(icon: "xmark.circle", message: "清空短剧历史失败，请重试") }
        }
    }

    private func removeShortDrama(_ entry: ShortDramaHistoryEntry) {
        do { try progressStore.removeHistory(for: entry.key) }
        catch { toastManager.show(icon: "xmark.circle", message: "删除记录失败，请重试") }
    }

    private func openShortDrama(_ entry: ShortDramaHistoryEntry) {
        guard let room = entry.room else {
            toastManager.show(icon: "puzzlepiece.extension", message: "此短剧的插件尚未安装或不可用。安装对应插件后可继续观看，观看进度仍会保留。")
            return
        }
        fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
    }

    private var historyGridView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 15)],
            spacing: 24
        ) {
            if selectedType == 0 {
                ForEach(liveRooms, id: \.id) { room in
                    HistoryRoomCardButton(room: room) {
                        LiveRoomCard(room: room, showsCoverBadge: true, onRemoveFromHistory: {
                            historyModel.removeHistories(ids: [room.id])
                        })
                    }
                }
            } else {
                ForEach(progressStore.historyEntries) { entry in
                    Button { openShortDrama(entry) } label: {
                        LiveRoomCard(room: entry.historyDisplayRoom,
                                     onRemoveFromHistory: { removeShortDrama(entry) },
                                     subtitle: entry.historySubtitle,
                                     allowsFavoriteActions: entry.room != nil)
                    }
                    .buttonStyle(MacRoomCardButtonStyle())
                    .macRoomCardHoverEffect()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private extension ShortDramaHistoryEntry {
    var historyDisplayRoom: LiveModel {
        room ?? LiveModel(userName: "", roomTitle: title, roomCover: coverURL ?? "", userHeadImg: "",
                          liveType: .placeholder, liveState: nil, userId: "", roomId: key.roomID,
                          liveWatchedCount: nil)
    }

    var historySubtitle: String {
        let episode = episodeNumber.map { "第 \($0) 集" } ?? episodeTitle ?? "最近观看"
        if completed { return "\(episode) · 已看完" }
        let minutes = String(format: "%.0f", floor(position / 60))
        let seconds = String(format: "%02.0f", floor(position.truncatingRemainder(dividingBy: 60)))
        return "\(episode) · \(minutes):\(seconds)"
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
    @State private var liveCheckTask: Task<Void, Never>?
    @State private var liveCheckToken = UUID()

    init(room: LiveModel, @ViewBuilder content: () -> Content) {
        self.room = room
        self.content = content()
    }

    var body: some View {
        Button {
            guard !isChecking else { return }
            isChecking = true
            let token = UUID()
            liveCheckToken = token
            liveCheckTask = Task {
                defer { if liveCheckToken == token { isChecking = false } }
                do {
                    let state = try await ApiManager.getCurrentRoomLiveState(
                        roomId: room.roomId,
                        userId: room.userId,
                        liveType: room.liveType
                    )
                    guard !Task.isCancelled, liveCheckToken == token else { return }
                    if state == .live {
                        fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
                    } else {
                        toastManager.show(icon: "tv.slash", message: "主播已下播")
                    }
                } catch {
                    guard !Task.isCancelled, liveCheckToken == token else { return }
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
        .buttonStyle(MacRoomCardButtonStyle())
        .macRoomCardHoverEffect()
        .onDisappear {
            liveCheckToken = UUID()
            liveCheckTask?.cancel()
            liveCheckTask = nil
            isChecking = false
        }
    }
}
