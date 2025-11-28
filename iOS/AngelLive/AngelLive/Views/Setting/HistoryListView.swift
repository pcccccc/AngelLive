//
//  HistoryListView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct HistoryListView: View {
    @State private var historyModel = HistoryModel()
    @State private var showClearAlert = false
    @State private var selectedRoom: LiveModel?
    @State private var showDeleteAlert = false

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: AppConstants.Spacing.md)
    ]

    var body: some View {
        ZStack {
            if historyModel.watchList.isEmpty {
                // 空状态视图
                VStack(spacing: AppConstants.Spacing.lg) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundStyle(AppConstants.Colors.secondaryText.opacity(0.5))

                    Text("暂无观看记录")
                        .font(.title3)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("开始观看直播后会显示在这里")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppConstants.Spacing.lg) {
                        ForEach(historyModel.watchList, id: \.roomId) { room in
                            LiveRoomCard(room: room)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        selectedRoom = room
                                        showDeleteAlert = true
                                    } label: {
                                        Label("删除此记录", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !historyModel.watchList.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearAlert = true
                    } label: {
                        Text("清空")
                            .foregroundStyle(AppConstants.Colors.error)
                    }
                }
            }
        }
        .alert("清空历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                historyModel.clearAll()
            }
        } message: {
            Text("确定要清空所有观看记录吗？此操作不可恢复。")
        }
        .alert("删除记录", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                selectedRoom = nil
            }
            Button("删除", role: .destructive) {
                if let room = selectedRoom {
                    historyModel.removeHistory(room: room)
                    selectedRoom = nil
                }
            }
        } message: {
            if let room = selectedRoom {
                Text("确定要删除 \(room.userName) 的观看记录吗？")
            }
        }
    }
}
