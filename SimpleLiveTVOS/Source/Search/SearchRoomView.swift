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
    
    @FocusState var focusState: Int?
    @Environment(LiveViewModel.self) var liveViewModel
    
    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        VStack {
            Text("请输入要搜索的主播名或平台链接/分享口令/房间号")
            HStack {
                Picker(selection: $liveModel.searchTypeIndex) {
                    ForEach(liveViewModel.searchTypeArray.indices, id: \.self) { index in
                        // 需要有一个变量text。不然会自动帮忙加很多0
                        let text = liveViewModel.searchTypeArray[index]
                        Text(text)
                    }
                } label: {
                    Text("字体大小")
                }
            }
            TextField("搜索", text: $liveModel.searchText)
            .onSubmit {
                if liveViewModel.searchTypeIndex == 0 {
                    liveViewModel.roomPage = 1
                    Task {
                        await liveViewModel.searchRoomWithText(text: liveViewModel.searchText)
                    }
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
                            .environment(liveViewModel)
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
        .simpleToast(isPresented: $liveModel.showToast, options: liveModel.toastOptions) {
            Label(liveViewModel.toastTitle, systemImage: liveViewModel.toastTypeIsSuccess == true ? "checkmark.circle":"info.circle.fill")
                .padding()
                .background(liveViewModel.toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
}

