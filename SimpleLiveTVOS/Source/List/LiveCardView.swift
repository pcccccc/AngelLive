//
//  LiveCardView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/9.
//

import SwiftUI
import Kingfisher
import KSPlayer
import LiveParse

struct LiveCardView: View {
    @EnvironmentObject var liveViewModel: LiveStore
    @EnvironmentObject var favoriteStore: FavoriteStore
    @State var index: Int
    @State private var isLive: Bool = false
    @FocusState var focusState: FocusableField?
    
    let gradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.3)]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        if index < liveViewModel.roomList.count {
            VStack(alignment: .leading, spacing: 10, content: {
                ZStack(alignment: Alignment(horizontal: .leading, vertical: .top), content: {
                    Button {
                        liveViewModel.currentRoom = liveViewModel.roomList[index]
                        liveViewModel.selectedRoomListIndex = index
                        Task {
                            do {
                                if LiveState(rawValue: self.liveViewModel.currentRoom?.liveState ?? "unknow") == .live || self.liveViewModel.roomListType == .live {
                                    if self.liveViewModel.watchList.contains(where: { self.liveViewModel.currentRoom!.roomId == $0.roomId }) == false {
                                        self.liveViewModel.watchList.insert(self.liveViewModel.currentRoom!, at: 0)
                                    }
                                    liveViewModel.createCurrentRoomViewModel()
                                    DispatchQueue.main.async {
                                        isLive = true
                                    }
                                }else {
                                    DispatchQueue.main.async {
                                        isLive = false
                                        liveViewModel.showToast(false, title: "主播已经下播")
                                    }
                                }
                            }catch {
                                DispatchQueue.main.async {
                                    isLive = false
                                    liveViewModel.showToast(false, title: "主播已经下播")
                                }
                            }
                        }
                    } label: {
                        ZStack(alignment: .bottom) {
                            KFImage(URL(string: liveViewModel.roomList[index].roomCover))
                                .placeholder {
                                    Image("placeholder")
                                        .resizable()
                                        .frame(height: 210)
                                }
                                .resizable()
                                .frame(height: 210)
                                
                            Rectangle()
                            .fill(gradient)
                            .shadow(radius: 10)
                            .frame(height: 30)
                            if liveViewModel.roomList[index].liveWatchedCount != nil {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 5) {
                                        Image(systemName: "eye")
                                            .font(.system(size: 14))
                                        Text(liveViewModel.roomList[index].liveWatchedCount!.formatWatchedCount())
                                            .font(.system(size: 18))
                                    }
                                    
                                    .foregroundColor(.white)
                                    .padding([.trailing], 10)
                                }
                                .frame(height: 30, alignment: .trailing)
                            }
                            if liveViewModel.roomListType != .live { // 如果不为直播页面，则展示对应平台和直播状态
                                HStack {
                                    Image(uiImage: .init(named: getImage())!)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(5)
                                        .padding(.top, 5)
                                        .padding(.leading, 5)
                                    Spacer()
                                    HStack(spacing: 5) {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(LiveState(rawValue: liveViewModel.roomList[index].liveState ?? "3") == .live ? Color.green : Color.gray)
                                                .frame(width: 10, height: 10)
                                                .padding(.leading, 5)
                                            Text(liveViewModel.roomList[index].liveStateFormat())
                                                .font(.system(size: 18))
                                                .foregroundColor(Color.white)
                                                .padding(.trailing, 5)
                                                .padding(.top, 5)
                                                .padding(.bottom, 5)
                                        }
                                        .background(Color("favorite_right_hint"))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .padding(.trailing, 5)
                                }
                                .padding(.bottom, 165)
                            }
                        }
                    }
                    .buttonStyle(.card)
                    .focused($focusState, equals: .mainContent(index))
                    .onChange(of: focusState, perform: { value in
                        liveViewModel.currentRoom = liveViewModel.roomList[index]
                        liveViewModel.selectedRoomListIndex = index
                        if liveViewModel.roomListType != .history {
                            switch value {
                                case .mainContent(let index):
                                    liveViewModel.selectedRoomListIndex = index
                                    if liveViewModel.roomListType == .live || liveViewModel.roomListType == .search  {
                                        if index >= liveViewModel.roomList.count - 4 { //如果小于4 就尝试刷新。
                                            liveViewModel.roomPage += 1
                                        }
                                    }
                                case .leftMenu(let index): break
                                default: break
                            }
                        }
                    })
                    .alert("提示", isPresented: $liveViewModel.showAlert) {
                        Button("取消收藏", role: .destructive, action: {
                            Task {
                                do {
                                    try await favoriteStore.removeFavoriteRoom(room: liveViewModel.currentRoom!)
                                    if liveViewModel.roomListType == .favorite {
                                        DispatchQueue.main.async {
                                            liveViewModel.roomList.remove(at: index)
                                        }
                                    }
                                    liveViewModel.showToast(true, title:"取消收藏成功")
                                }catch {
                                    liveViewModel.showToast(false, title:favoriteStore.formatErrorCode(error: error))
                                }
                            }
                        })
                        Button("再想想",role: .cancel) {
                            liveViewModel.showAlert = false
                        }
                    } message: {
                        Text("确认取消收藏吗")
                    }
                    .contextMenu(menuItems: {
                        if liveViewModel.currentRoomIsFavorited {
                            Button(action: {
                                Task {
                                    do {
                                        try await favoriteStore.removeFavoriteRoom(room: liveViewModel.currentRoom!)
                                        if liveViewModel.roomListType == .favorite {
                                            DispatchQueue.main.async {
                                                liveViewModel.roomList.remove(at: index)
                                            }
                                        }
                                        liveViewModel.showToast(true, title:"取消收藏成功")
                                    }catch {
                                        liveViewModel.showToast(false, title:favoriteStore.formatErrorCode(error: error))
                                    }
                                }
                            }, label: {
                                HStack {
                                    Image(systemName: "heart.fill")
                                    Text("取消收藏")
                                }
                            })
                            
                        }else {
                            Button(action: {
                                Task {
                                    do {
                                        try await favoriteStore.addFavorite(room: liveViewModel.currentRoom!)
                                        liveViewModel.showToast(true, title:"收藏成功")
                                    }catch {
                                        liveViewModel.showToast(false, title:favoriteStore.formatErrorCode(error: error))
                                    }
                                }
                            }, label: {
                                HStack {
                                    Image(systemName: "heart.fill")
                                    Text("收藏")
                                }
                            })
                        }
                        if liveViewModel.roomListType == .history {
                            Button(action: {
                                liveViewModel.deleteHistory(index: index)
                            }, label: {
                                HStack {
                                    Image(systemName: "trash.circle")
                                    Text("删除")
                                }
                            })
                        }
                    })
                    .fullScreenCover(isPresented: $isLive, content: {
                        DetailPlayerView(didExitView: { isLive, hint in
                            self.isLive = isLive
                        })
                        .environmentObject(liveViewModel.roomInfoViewModel ?? RoomInfoStore(currentRoom: LiveModel(userName: "", roomTitle: "", roomCover: "", userHeadImg: "", liveType: .bilibili, liveState: "", userId: "", roomId: "", liveWatchedCount: "")))
                        .environmentObject(favoriteStore)
                        .edgesIgnoringSafeArea(.all)
                        .frame(width: 1920, height: 1080)
                    })
                })
                HStack(spacing: 15) {
                    KFImage(URL(string: liveViewModel.roomList[index].userHeadImg))
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(20)
                    VStack (alignment: .leading, spacing: 5) {
                        Text(liveViewModel.roomList[index].userName)
                            .font(.system(size: 22))
                        Text(liveViewModel.roomList[index].roomTitle)
                            .font(.system(size: 16))
                    }
                    Spacer()
                }
                .padding(.top, focusState == .mainContent(index) ? 25 : 10)
                .scaleEffect(focusState == .mainContent(index) ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: focusState == .mainContent(index))
                .frame(height: 50)
            })
            .onAppear {
                if favoriteStore != nil {
                    liveViewModel.favoriteStore = favoriteStore
                }
            }
        }
        
    }

    func getImage() -> String {
        switch liveViewModel.roomList[index].liveType {
            case .bilibili:
                return "live_card_bili"
            case .douyu:
                return "live_card_douyu"
            case .huya:
                return "live_card_huya"
            default:
                return "live_card_douyin"
        }
    }
}
