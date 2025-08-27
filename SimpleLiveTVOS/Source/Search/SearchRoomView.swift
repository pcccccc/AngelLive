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
    @Environment(AppState.self) var appViewModel
    
    var body: some View {
        
        @Bindable var appModel = appViewModel
        @Bindable var liveModel = liveViewModel
        
        VStack {
            Text("请输入要搜索的主播名或平台链接/分享口令/房间号")
            HStack {
                Picker(selection: $appModel.searchViewModel.searchTypeIndex) {
                    ForEach(liveViewModel.searchTypeArray.indices, id: \.self) { index in
                        // 需要有一个变量text。不然会自动帮忙加很多0
                        let text = liveViewModel.searchTypeArray[index]
                        Text(text)
                    }
                } label: {
                    Text("字体大小")
                }
            }
            TextField("搜索", text: $appModel.searchViewModel.searchText)
            .onSubmit {
                if appModel.searchViewModel.searchTypeIndex == 0 {
                    liveViewModel.roomPage = 1
                    Task {
                        await liveViewModel.searchRoomWithText(text: appModel.searchViewModel.searchText)
                    }
                }else {
                    liveViewModel.roomPage = 1
                    liveViewModel.searchRoomWithShareCode(text: appModel.searchViewModel.searchText)
                }
                
            }
            Spacer()
            if appModel.searchViewModel.searchTypeIndex == 2 && liveViewModel.roomList.count == 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("可选格式:")
                            .font(.title3)
                        Text("https://www.youtube.com/watch?v=36YnV9STBqc")
                            .font(.headline)
                        Text("https://www.youtube.com/live/36YnV9STBqc")
                            .font(.headline)
                        Text("36YnV9STBqc")
                            .font(.headline)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                }
            }else {
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
        }
        .simpleToast(isPresented: $liveModel.showToast, options: liveModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: liveModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(liveModel.toastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(Color.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            liveViewModel.getRoomList(index: 1)
        })
    }
}

