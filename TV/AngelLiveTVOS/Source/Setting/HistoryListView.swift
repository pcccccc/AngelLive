//
//  HistoryListView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/10.
//

import SwiftUI
import AngelLiveDependencies

enum HistoryFocusField: Hashable {
    case clearButton
    case card(Int)
}

struct HistoryListView: View {

    var appViewModel: AppState
    @FocusState var focusState: HistoryFocusField?
    var liveViewModel: LiveViewModel?
    @State private var showClearAlert = false

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        self.liveViewModel = LiveViewModel(roomListType: .history, liveType: .bilibili, appViewModel: appViewModel)
    }

    var body: some View {
        VStack {
            HStack {
                Text("历史记录")
                    .font(.title2)

                Spacer()

                if !appViewModel.historyViewModel.watchList.isEmpty {
                    Button(action: { showClearAlert = true }) {
                        Label("清空全部", systemImage: "trash")
                            .font(.caption)
                    }
                    .focused($focusState, equals: .clearButton)
                }
            }
            .padding(.horizontal, 50)
            .focusSection()

            if appViewModel.historyViewModel.watchList.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("暂无历史记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("观看直播后将自动记录在这里")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(380), spacing: 50),
                            GridItem(.fixed(380), spacing: 50),
                            GridItem(.fixed(380), spacing: 50),
                            GridItem(.fixed(380), spacing: 50)
                        ],
                        alignment: .center,
                        spacing: 50
                    ) {
                        ForEach(appViewModel.historyViewModel.watchList.indices, id: \.self) { index in
                            LiveCardView(index: index)
                                .environment(liveViewModel)
                                .environment(appViewModel)
                                .frame(width: 370, height: 280)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .safeAreaPadding(.top, 30)
                    .focusSection()
                }
            }
        }
        .task {
            for index in 0 ..< (liveViewModel?.roomList ?? []).count {
                liveViewModel?.getLastestHistoryRoomInfo(index)
            }
        }
        .onPlayPauseCommand(perform: {
        })
        .alert("清空历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                appViewModel.historyViewModel.clearAll()
            }
        } message: {
            Text("确定要清空所有观看记录吗？此操作不可恢复。")
        }
    }
}
