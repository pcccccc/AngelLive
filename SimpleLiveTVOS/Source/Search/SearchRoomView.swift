//
//  SearchRoomView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/30.
//

import SwiftUI
import SimpleToast
import LiveParse

struct SearchRoomView: View {
    
    @StateObject var liveViewModel = LiveStore(roomListType: .search, liveType: .bilibili)
    @FocusState var focusState: Int?
    @EnvironmentObject var favoriteStore: FavoriteStore
    
    var body: some View {
        VStack {
            Text("请输入要搜索的主播名或平台链接/分享口令/房间号")
            HStack {
                Menu(liveViewModel.searchTypeArray[liveViewModel.searchTypeIndex]) {
                    ForEach(liveViewModel.searchTypeArray.indices, id: \.self) { index in
                        Button(liveViewModel.searchTypeArray[index]) {
                            liveViewModel.searchTypeIndex = index
                        }
                    }
                }
                TextField("搜索", text: $liveViewModel.searchText)
                .onSubmit {
                    if liveViewModel.searchTypeIndex == 0 {
                        liveViewModel.roomPage = 1
                        liveViewModel.searchRoomWithText(text: liveViewModel.searchText)
                    }else {
                        liveViewModel.searchRoomWithShareCode(text: liveViewModel.searchText)
                    }
                    
                }
            }
            Spacer()
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(370), spacing: 70), GridItem(.fixed(370), spacing: 70), GridItem(.fixed(370), spacing: 70), GridItem(.fixed(370), spacing: 70)], spacing: 70) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                        LiveCardView(index: index)
                            .environmentObject(liveViewModel)
                            .environmentObject(favoriteStore)
                            .frame(width: 370, height: 240)
                    }
                }
                .safeAreaPadding(.top, 50)
                
            }
        }
        .simpleToast(isPresented: Binding(get: {
            liveViewModel.showToast
        }, set: { newValue in
            liveViewModel.showToast = newValue
        }), options: liveViewModel.toastOptions) {
            Label(liveViewModel.toastTitle, systemImage: liveViewModel.toastTypeIsSuccess == true ? "checkmark.circle":"info.circle.fill")
                .padding()
                .background(liveViewModel.toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
        .onChange(of: focusState, perform: { newValue in
            if newValue ?? 0 > 6 && newValue ?? 0 > liveViewModel.roomList.count - 6 {
                liveViewModel.roomPage += 1
//                beginSearch(research: false)
            }
        })
    }
}

