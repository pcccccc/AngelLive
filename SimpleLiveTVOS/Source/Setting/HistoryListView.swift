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
    @StateObject var liveViewModel: LiveStore
    @FocusState var focusState: FocusableField?
    
    init() {
        self._liveViewModel = StateObject(wrappedValue: LiveStore(roomListType: .history, liveType: .bilibili))
    }
    
    var body: some View {
        VStack {
            Text("历史记录")
                .font(.title2)
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380))], spacing: 60) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                        LiveCardView(index: index)
                            .environmentObject(liveViewModel)
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
