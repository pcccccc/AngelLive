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
    @FocusState var focusState: Int?
    @EnvironmentObject var favoriteStore: FavoriteStore
    
    init() {
        self._liveViewModel = StateObject(wrappedValue: LiveStore(roomListType: .favorite, liveType: .bilibili))
    }
    
    var body: some View {
        VStack {
            if favoriteStore.cloudKitReady {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60)], spacing: 60) {
                        ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                            LiveCardView(index: index)
                                .environmentObject(liveViewModel)
                                .environmentObject(favoriteStore)
                                .frame(width: 370, height: 240)
                        }
                    }
                    .safeAreaPadding(.top, 15)
                }
            }else {
                Text(favoriteStore.cloudKitStateString)
                    .font(.title3)
            }
        }
        .onPlayPauseCommand(perform: {
            favoriteStore.fetchFavoriteRoomList()
            liveViewModel.roomPage = 1
        })
        .onChange(of: focusState, perform: { index in
            if index ?? 0 >= liveViewModel.roomList.count - 4 { //如果小于4 就尝试刷新。
                liveViewModel.roomPage += 1
            }
        })
        .task {
            favoriteStore.fetchFavoriteRoomList()
            liveViewModel.roomPage = 1
        }
        .simpleToast(isPresented: $liveViewModel.showToast, options: liveViewModel.toastOptions) {
            Label(liveViewModel.toastTitle, systemImage: liveViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                .padding()
                .background(liveViewModel.toastTypeIsSuccess ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
}
