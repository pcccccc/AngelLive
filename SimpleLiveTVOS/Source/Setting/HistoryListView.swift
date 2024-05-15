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
    var liveViewModel: LiveViewModel = LiveViewModel(roomListType: .history, liveType: .bilibili)
    @Environment(DanmuSettingModel.self) var danmuSettingModel
    @Environment(FavoriteModel.self) var favoriteModel
    @FocusState var focusState: FocusableField?
    
    var body: some View {
        VStack {
            Text("历史记录")
                .font(.title2)
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380))], spacing: 60) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                        LiveCardView(index: index)
                            .environment(liveViewModel)
                            .environment(favoriteModel)
                            .environment(danmuSettingModel)
                            .frame(width: 370, height: 240)
                    }
                }
                .safeAreaPadding(.top, 30)
            }
        }
        .task {
        }
        .onPlayPauseCommand(perform: {
        })
    }
}

#Preview {
    HistoryListView()
}
