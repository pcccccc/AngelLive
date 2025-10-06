//
//  HistoryListView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/10.
//

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse

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
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380))], spacing: 60) {
                    ForEach(appViewModel.historyViewModel.watchList.indices, id: \.self) { index in
                        LiveCardView(index: index)
                            .environment(liveViewModel)
                            .environment(appViewModel)
                            .frame(width: 370, height: 240)
                    }
                }
                .safeAreaPadding(.top, 30)
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

