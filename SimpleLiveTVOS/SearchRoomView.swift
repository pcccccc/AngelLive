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
    
    @State var searchText: String = ""
    @State var showToast: Bool = false
    @State var toastTitle: String = ""
    @State var toastTypeIsSuccess: Bool = false
    @FocusState var mainContentfocusState: Int?
    @State var loadingText: String = "正在获取内容"
    @State var needFullScreenLoading: Bool = false
    @State private var page = 1
    @State private var roomContentArray: Array<LiveModel> = []
    @State private var searchTypeArray = ["全平台关键词", "B站链接/分享口令/房间号", "斗鱼链接/房间号", "虎牙链接/分享口令/房间号", "抖音链接/抖音码/房间号"]
    @State private var searchTypeIndex = 0
    private let toastOptions = SimpleToastOptions(
        hideAfter: 2
    )
    
    var body: some View {
        VStack {
            Text("请输入要搜索的主播名或平台链接/分享口令/房间号")
            HStack {
                Menu(searchTypeArray[searchTypeIndex]) {
                    ForEach(searchTypeArray.indices, id: \.self) { index in
                        Button(searchTypeArray[index]) {
                            searchTypeIndex = index
                        }
                    }
                }
                TextField("搜索", text: $searchText)
                    .onSubmit {
                        page = 1
                        beginSearch(research: true)
                    }
            }
            if roomContentArray.count == 0 {
                if needFullScreenLoading == true && roomContentArray.isEmpty {
                    GeometryReader { proxy in
                        LoadingView(loadingText: $loadingText)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .zIndex(1)
                }else {
                    Spacer()
                }
            }else {
                Spacer()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                        ForEach(roomContentArray.indices, id: \.self) { index in
//                            LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, isFavoritePage: true) { success, delete, hint in
//                                toastTypeIsSuccess = success
//                                toastTitle = hint
//                                showToast.toggle()
//                                if delete {
//                                    roomContentArray.remove(at: index)
//                                }
//                            }
                        }
                    }
                }
            }
        }
        .simpleToast(isPresented: $showToast, options: toastOptions) {
            Label(toastTitle, systemImage: toastTypeIsSuccess == true ? "checkmark.circle":"info.circle.fill")
                .padding()
                .background(toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
        .onChange(of: mainContentfocusState, perform: { newValue in
            if newValue ?? 0 > 6 && newValue ?? 0 > self.roomContentArray.count - 6 {
                page += 1
                beginSearch(research: false)
            }
        })
    }
    
    func beginSearch(research: Bool) {
        loadingText = "正在搜索"
        Task {
            do {
                if searchText.count == 0 {
                    return
                }
                if research == true {
                    roomContentArray.removeAll()
                }
                needFullScreenLoading = true
                try await searchBilibiliStreamer()
                try await searchDouyuStreamer()
                try await searchHuyaStreamer()
                try await searchDouyinStreamer()
                if roomContentArray.count == 0 {
                    loadingText = "暂无内容"
                }
            }catch {
                print(error)
                showToast.toggle()
                toastTitle = error.localizedDescription
                toastTypeIsSuccess = false
            }
        }
    }
    
    func searchBilibiliStreamer() async throws {
        let dataReq = try await Bilibili.searchRooms(keyword: searchText, page: page)
        for item in dataReq {
            if roomContentArray.contains(where: { $0.roomId == item.roomId }) == false {
                roomContentArray.append(item)
            }
        }
    }
    
    func searchDouyinStreamer() async throws {
//        let dataReq = try await Douyin.getSearchURL(keyword: searchText, page:page)
//        for item in dataReq {
//            var newItem = item
//            try await newItem.getLiveState()
//            roomContentArray.append(newItem)
//        }
    }
    
    func searchDouyuStreamer() async throws {
        let dataReq = try await Douyu.searchRooms(keyword: searchText, page: page)
        roomContentArray.append(contentsOf: dataReq)
    }
    
    func searchHuyaStreamer() async throws {
        let dataReq = try await Huya.searchRooms(keyword: searchText, page: page)
        roomContentArray.append(contentsOf: dataReq)
    }
}

#Preview {
    SearchRoomView()
}
