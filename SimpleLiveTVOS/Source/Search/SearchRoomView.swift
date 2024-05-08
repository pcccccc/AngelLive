//
//  SearchRoomView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/30.
//

import SwiftUI
import SimpleToast
import LiveParse
import Shimmer

struct SearchRoomView: View {
    
    @StateObject var liveViewModel = LiveStore(roomListType: .search, liveType: .bilibili)
    @FocusState var focusState: Int?
    @EnvironmentObject var favoriteModel: FavoriteModel
    
    var body: some View {
        VStack {
            Text("请输入要搜索的主播名或平台链接/分享口令/房间号")
            HStack {
                Picker(selection: $liveViewModel.searchTypeIndex) {
                    ForEach(liveViewModel.searchTypeArray.indices, id: \.self) { index in
                        // 需要有一个变量text。不然会自动帮忙加很多0
                        let text = liveViewModel.searchTypeArray[index]
                        Text(text)
                    }
                } label: {
                    Text("字体大小")
                }
            }
            TextField("搜索", text: $liveViewModel.searchText)
            .onSubmit {
                if liveViewModel.searchTypeIndex == 0 {
                    liveViewModel.roomPage = 1
                    liveViewModel.searchRoomWithText(text: liveViewModel.searchText)
                }else {
                    liveViewModel.roomPage = 1
                    liveViewModel.searchRoomWithShareCode(text: liveViewModel.searchText)
                }
                
            }
            Spacer()
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(370), spacing: 50), GridItem(.fixed(370), spacing: 50), GridItem(.fixed(370), spacing: 50), GridItem(.fixed(370), spacing: 50)], spacing: 50) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                        LiveCardView(index: index)
                            .environmentObject(liveViewModel)
                            .environmentObject(favoriteModel)
                            .frame(width: 370, height: 280)
                    }
                    if liveViewModel.isLoading {
                        LoadingView()
                            .frame(width: 370, height: 280)
                            .cornerRadius(5)
                            .shimmering(active: true)
                            .redacted(reason: .placeholder)
                    }
                }
                .safeAreaPadding(.top, 50)
            }
        }
        .simpleToast(isPresented: $liveViewModel.showToast, options: liveViewModel.toastOptions) {
            Label(liveViewModel.toastTitle, systemImage: liveViewModel.toastTypeIsSuccess == true ? "checkmark.circle":"info.circle.fill")
                .padding()
                .background(liveViewModel.toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
}

