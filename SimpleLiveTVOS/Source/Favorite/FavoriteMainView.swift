//
//  FavoriteMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse

struct FavoriteMainView: View {
    
    @StateObject var liveViewModel: LiveStore
    @FocusState var focusState: FocusableField?
    
    init() {
        self._liveViewModel = StateObject(wrappedValue: LiveStore(roomListType: .favorite, liveType: .bilibili))
    }
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380))], spacing: 60) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                        LiveCardView(index: index)
                            .environmentObject(liveViewModel)
                            .frame(width: 370, height: 240)
                    }
                }
                .safeAreaPadding(.top, 15)
            }
        }
        .onPlayPauseCommand(perform: {
        })
    }
}
