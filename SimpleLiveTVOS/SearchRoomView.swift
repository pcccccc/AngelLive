//
//  SearchRoomView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/30.
//

import SwiftUI
import SimpleToast

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
    private let toastOptions = SimpleToastOptions(
        hideAfter: 2
    )
    
    var body: some View {
        VStack {
            Text("请输入要搜索的主播名/房间号（目前仅支持抖音，其他平台正在制作中）")
            TextField("搜索主播名/房间号", text: $searchText)
                .onSubmit {
                    beginSearch(research: true)
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
                            LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, isFavoritePage: true) { success, delete, hint in
                                toastTypeIsSuccess = success
                                toastTitle = hint
                                showToast.toggle()
                                if delete {
                                    roomContentArray.remove(at: index)
                                }
                            }
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
        Task {
            do {
                if searchText.count == 0 {
                    return
                }
                loadingText = "正在搜索"
                if research == true {
                    roomContentArray.removeAll()
                }
                needFullScreenLoading = true
                let dataReq = try await Douyin.getSearchURL(keyword: searchText, page:page)
                
                for item in dataReq {
                    var newItem = item
                    try await newItem.getLiveState()
                    roomContentArray.append(newItem)
                }
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
}

#Preview {
    SearchRoomView()
}
