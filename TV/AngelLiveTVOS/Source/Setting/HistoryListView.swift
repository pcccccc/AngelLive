//
//  HistoryListView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/10.
//

import SwiftUI
import AngelLiveDependencies

struct HistoryListView: View {

    var appViewModel: AppState
    @FocusState var focusState: FocusableField?
    var liveViewModel: LiveViewModel?

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        self.liveViewModel = LiveViewModel(roomListType: .history, liveType: .bilibili, appViewModel: appViewModel)
    }

    var body: some View {
        VStack {
            Text("历史记录")
                .font(.title2)

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
    }
}
