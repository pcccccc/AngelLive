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
    
    @FocusState var mainContentfocusState: Int?
    @State private var roomContentArray: Array<LiveModel> = []
    @State private var page = 1
    @State var showToast: Bool = false
    @State var toastTitle: String = ""
    @State var toastTypeIsSuccess: Bool = false
    @State var loadingText: String = "正在获取内容"
    @State var iCloudStatus: String = "正在获取iCloud状态"
    @State var iCloudStatusLoading: Bool = false
    @State var needFullScreenLoading: Bool = false
    @FocusState var refreshButtonFocues: Bool
    private let toastOptions = SimpleToastOptions(
        hideAfter: 1
    )
    
    var body: some View {
        VStack {
            HStack {
                if iCloudStatusLoading == true {
                    ProgressView()
                }else {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        roomContentArray.removeAll()
                        reloadFavorite()
                    }
                    .font(.system(size: 25))
                    .focused($refreshButtonFocues, equals: true)
                }
                Spacer()
                Text("iCloud状态：\(iCloudStatus)")
                    .font(.headline)
            }
            
            ZStack {
                if needFullScreenLoading == true && roomContentArray.isEmpty {
                    GeometryReader { proxy in
                        LoadingView(loadingText: $loadingText)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .zIndex(1)
                }else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                            ForEach(roomContentArray.indices, id: \.self) { index in
//                                LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, isFavoritePage: true) { success, delete, hint in
//                                    toastTypeIsSuccess = success
//                                    toastTitle = hint
//                                    showToast.toggle()
//                                    if delete {
//                                        roomContentArray.remove(at: index)
//                                    }
//                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                    .simpleToast(isPresented: $showToast, options: toastOptions) {
                        Label(toastTitle, systemImage:toastTypeIsSuccess == true ? "checkmark.circle":"info.circle.fill")
                            .padding()
                            .background(toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                            .foregroundColor(Color.white)
                            .cornerRadius(10)
                            .padding(.top)

                    }
                }
            }
        }
        .task {
            reloadFavorite()
        }
        .onPlayPauseCommand(perform: {
            
            refreshButtonFocues = true
        })
    }
    
    func getRoomList() async {
        do {
//            
//            needFullScreenLoading = true
//            var newItem = try await CloudSQLManager.searchRecord()
//            for item in newItem {
//                var new = item
//                try await new.getLiveState()
//                if roomContentArray.contains(where: { $0.roomId == item.roomId }) == false {
//                    if new.liveState ?? "" == "正在直播" {
//                        roomContentArray.insert(new, at: 0)
//                    }else{
//                        roomContentArray.append(new)
//                    }
//                }
//            }
//            if roomContentArray.isEmpty == false {
//                needFullScreenLoading = false
//            }
        }catch {
            loadingText = error.localizedDescription
        }
    }
    
    func reloadFavorite() {
        Task {
            iCloudStatusLoading = true
            iCloudStatus = await CloudSQLManager.getCloudState()
            iCloudStatusLoading = false
            await getRoomList()
        }
    }
}

#Preview {
    FavoriteMainView()
}
