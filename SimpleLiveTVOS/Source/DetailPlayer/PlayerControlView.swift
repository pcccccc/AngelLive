//
//  PlayerControlView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/27.
//

import SwiftUI
import SimpleToast
import KSPlayer
import LiveParse
import Shimmer
import Kingfisher

enum PlayControlFocusableField: Hashable {
    case playPause
    case refresh
    case favorite
    case playQuality
    case danmu
    case listContent(Int)
    case list
    case left
    case right
}

enum PlayControlTopField: Hashable {
    case section(Int)
    case list(Int)
}


struct PlayerControlView: View {
    
    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(SimpleLiveViewModel.self) var appViewModel
    
    @State var sectionList: [LiveModel] = []
    @State var selectIndex = 0

    @FocusState var state: PlayControlFocusableField?
    @FocusState var topState: PlayControlTopField?
   
    
    let topGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.1)]),
        startPoint: .top,
        endPoint: .bottom
    )
    let topTipGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.3), Color.black.opacity(0.05)]),
        startPoint: .top,
        endPoint: .bottom
    )
    let bottomGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.5)]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        
        @Bindable var roomInfoModel = roomInfoViewModel
        
        ZStack {
            if roomInfoViewModel.showTop {
                VStack(spacing: 50) {
                    VStack {
                        HStack {
                            Spacer()
                            if appViewModel.favoriteStateModel.cloudKitReady {
                                Button("收藏") {}
                                .focused($topState, equals: .section(0))
                            }
                            Button("历史") {}
                            .focused($topState, equals: .section(1))
                            if roomInfoModel.roomType == .live {
                                Button("分区") {}
                                .focused($topState, equals: .section(2))
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .buttonStyle(.plain)
                        .focusSection()
                        .onChange(of: topState) { oldValue, newValue in
                            switch newValue {
                                case .section(let index):
                                    changeList(index)
                                default:
                                    break
                            }
                        }
                        
                        ScrollView(.horizontal) {
                            LazyHGrid(rows: [GridItem(.fixed(192))], content: {
                                ForEach(sectionList.indices, id: \.self) { index in
                                    PlayerControlCardView() { liveModel in
                                        changeRoom(liveModel)
                                    }
                                        .environment(PlayerControlCardViewModel(liveModel: sectionList[index], cardIndex: index, selectIndex: selectIndex))
                                }
                            })
                            .padding()
                        }
                        .frame(height: 192)
                        .padding([.leading, .trailing], 55)
                        .padding(.top, 80)
                        .scrollClipDisabled()
                        .focusSection()
                        Spacer()
                    }
                    .background(.black.opacity(0.6))
                    .frame(height: 390)
                    Spacer()
                }
                .frame(width: 1920)
                .padding(.top, 30)
                .buttonStyle(.plain)
                .transition(.move(edge: .top))
                .onExitCommand(perform: {
                    withAnimation {
                        roomInfoViewModel.showTop = false
                    }
                    state = roomInfoViewModel.lastOptionState
                })
            }else {
                VStack {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                                .frame(height: 15)
                            Text("下滑切换直播间")
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.compact.down")
                                .foregroundStyle(.white)
                        }
                        .shimmering(active: true)
                        Spacer()
                    }
                    Spacer()
                }
                .opacity(roomInfoViewModel.showTips ? 1 : 0)
//可以放个播放按钮
                VStack() {
                    ZStack {
                        HStack {
                            Text("\(roomInfoViewModel.currentRoom.userName) - \(roomInfoViewModel.currentRoom.roomTitle)")
                                .font(.title3)
                                .padding(.leading, 15)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .background {
                            Rectangle()
                                .fill(topGradient)
                                .shadow(radius: 10)
                                .frame(height: 150)
                        }
                        .frame(height: 150)
                    }
                    Spacer()
                    HStack(alignment: .center, spacing: 15) {
                        
                            Button(action: {}, label: {
                                
                            })
                            .padding(.leading, -80)
                            .clipShape(.circle)
                            .frame(width: 40, height: 40)
                            .focused($state, equals: .left)
                            
                        VStack {
                            Button(action: {
                                playPauseAction()
                            }, label: {
                                Image(systemName: roomInfoViewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            })
                            .contextMenu(menuItems: {
                                Button("debug mode") {
            //                        roomInfoViewModel.toggleTimer()
                                }
                            })
                            .focused($state, equals: .playPause)
                            .clipShape(.circle)
                            .padding(.leading, -20)
                            
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                        VStack {
                            Button(action: {
                                refreshAction()
                            }, label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundColor(.white)
                                    .font(.system(size: 30, weight: .bold))
                                    .frame(width: 40, height: 40)
                            })
                            .clipShape(.circle)
                            .padding(.leading, -20)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                      
                        VStack {
                            Button(action: {
                                favoriteBtnAction()
                            }, label: {
                                Image(systemName: (appViewModel.favoriteModel?.roomList ?? []).contains(where: { $0.roomId == roomInfoViewModel.currentRoom.roomId }) ? "heart.fill" : "heart")
                                    .foregroundColor((appViewModel.favoriteModel?.roomList ?? []).contains(where: { $0.roomId == roomInfoViewModel.currentRoom.roomId }) ? .red : .white)
                                    .font(.system(size: 30, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .padding(.top, 3)
                                    .contentTransition(.symbolEffect(.replace))
                            })
                            .clipShape(.circle)
                            .padding(.leading, -20)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                       
                        Color.green
                            .cornerRadius(10)
                            .frame(width: 20, height: 20)
                        Text("Live")
                            .foregroundStyle(.white)
                        Spacer()
                        VStack {
                            Menu {
                                ForEach(roomInfoViewModel.currentRoomPlayArgs?.indices ?? 0..<1, id: \.self) { index in
                                    Button(action: {
                                        if (roomInfoViewModel.showControlView == false) {
                                            roomInfoViewModel.showControlView = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                                                if roomInfoViewModel.showControlView == true {
                                                    roomInfoViewModel.showControlView = false
                                                }
                                            })
                                        }else {}
                                    }, label: {
                                        if roomInfoViewModel.currentRoomPlayArgs == nil {
                                            Text("测试")
                                        }else {
                                            Menu {
                                                ForEach(roomInfoViewModel.currentRoomPlayArgs?[index].qualitys.indices ?? 0 ..< 1, id: \.self) { subIndex in
                                                    Button {
                                                        roomInfoViewModel.changePlayUrl(cdnIndex: index, urlIndex: subIndex)
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                                                            if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                                                                roomInfoViewModel.playerCoordinator.playerLayer?.play()
                                                                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                                                                    roomInfoViewModel.showControlView = false
                                                                })
                                                            }
                                                        })
                                                    } label: {

                                                        Text(roomInfoViewModel.currentRoomPlayArgs?[index].qualitys[subIndex].title ?? "")
                                                    }
                                                }
                                            } label: {
                                                Text(roomInfoViewModel.currentRoomPlayArgs?[index].cdn ?? "")
                                            }
                                        }
                                    })
                                }
                            } label: {
                                Text(roomInfoViewModel.currentPlayQualityString)
                                    .font(.system(size: 30, weight: .bold))
                                    .frame(height: 50, alignment: .center)
                                    .padding(.top, 10)
                                    .foregroundStyle(.white)
                            }
                            .frame(height: 60)
                            .clipShape(.capsule)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                        
                        VStack {
                            Button(action: {
                                danmuAction()
                            }, label: {
                                Image(appViewModel.danmuSettingModel.showDanmu ? "icon-danmu-open-focus" : "icon-danmu-close-focus")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                            })
                            .focused($state, equals: .danmu)
                            .clipShape(.circle)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                        
                        Button(action: {}, label: {
                            
                        })
                        .padding(.trailing, -80)
                        .clipShape(.circle)
                        .frame(width: 40, height: 40)
                        .focused($state, equals: .right)
                    }
                    .background {
                        Rectangle()
                            .fill(bottomGradient)
                            .shadow(radius: 10)
                            .frame(height: 150)
                    }
                    .frame(height: 150)
                }
                .transition(.opacity)
                .opacity(roomInfoViewModel.showControl ? 1 : 0)
                .onExitCommand {
                    if roomInfoViewModel.showControl == true {
                        roomInfoViewModel.showControl = false
                        return
                    }
                    if roomInfoViewModel.showControl == false {
                        NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil)
                    }
                }
            }
        }
        .onAppear {
            state = .playPause
            roomInfoViewModel.showControl = true
        }
        .onChange(of: state, { oldValue, newValue in
            if roomInfoViewModel.showControl == false {
                roomInfoViewModel.showControl.toggle()
            }else {
                roomInfoViewModel.controlViewOptionSecond = 5
            }
            
            if oldValue != .list && isListContentField(oldValue) == false && oldValue != nil {
                roomInfoViewModel.lastOptionState = oldValue
            }
            if newValue == .left {
                state = .danmu
            }else if newValue == .right {
                state = .playPause
            }else if newValue == .list {
                withAnimation {
                    roomInfoViewModel.showTop = true
                    state = .listContent(0)
                }
            }
        })
        .onPlayPauseCommand(perform: {
            playPauseAction()
        })
    }
    
    func favoriteAction() {
        if appViewModel.favoriteStateModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) == false {
            Task {
                try await appViewModel.favoriteStateModel.addFavorite(room: roomInfoViewModel.currentRoom)
                appViewModel.favoriteModel?.roomList.append(roomInfoViewModel.currentRoom)
                roomInfoViewModel.showToast(true, title: "收藏成功")
            }
        }else {
            Task {
                try await  appViewModel.favoriteStateModel.removeFavoriteRoom(room: roomInfoViewModel.currentRoom)
                appViewModel.favoriteModel?.roomList.removeAll(where: { $0.roomId == roomInfoViewModel.currentRoom.roomId })
                roomInfoViewModel.showToast(true, title: "取消收藏成功")
            }
        }
    }
    
    
    
    func playPauseAction() {
        if (roomInfoViewModel.showControl == false) {
            roomInfoViewModel.showControl = true
        }else {
            DispatchQueue.main.async {
                if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false {
                    roomInfoViewModel.playerCoordinator.playerLayer?.pause()
                }else {
                    roomInfoViewModel.playerCoordinator.playerLayer?.play()
                }
            }
        }
    }
    
    func refreshAction() {
        if (roomInfoViewModel.showControl == false) {
            roomInfoViewModel.showControl = true
        }else {
            roomInfoViewModel.getPlayArgs()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                    roomInfoViewModel.playerCoordinator.playerLayer?.play()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                        roomInfoViewModel.showControlView = false
                    })
                }
            })
        }
    }
    
    func favoriteBtnAction() {
        if (roomInfoViewModel.showControl == false) {
            roomInfoViewModel.showControl = true
        }else {
            withAnimation(.easeInOut(duration: 0.3)) {
                favoriteAction()
            }
        }
    }
    
    func danmuAction() {
        if (roomInfoViewModel.showControl == false) {
            roomInfoViewModel.showControl = true
        }else {
            appViewModel.danmuSettingModel.showDanmu.toggle()
            if appViewModel.danmuSettingModel.showDanmu == false {
                roomInfoViewModel.disConnectSocket()
            }else {
                roomInfoViewModel.getDanmuInfo()
            }
        }
    }
    
    func isListContentField(_ field: PlayControlFocusableField?) -> Bool {
        if case .listContent(_) = field {
            return true
        }
        return false
    }
    
    @MainActor func changeRoom(_ liveModel: LiveModel) {
        if liveModel.liveState == "" || liveModel.liveState == LiveState.unknow.rawValue {
            roomInfoViewModel.showToast(false, title: "请等待房间状态同步")
        }else if liveModel.liveState == LiveState.close.rawValue {
            roomInfoViewModel.showToast(false, title: "主播已经下播")
        }else {
            roomInfoViewModel.reloadRoom(liveModel: liveModel)
        }
    }
    
    func changeList(_ index: Int) {
        selectIndex = index
        sectionList.removeAll()
        switch index {
            case 0:
                for item in appViewModel.favoriteModel?.roomList ?? [] {
                    if item.liveState ?? "0" == LiveState.live.rawValue {
                        sectionList.append(item)
                    }
                }
            case 1:
                Task {
                    for item in appViewModel.historyModel.watchList {
                        sectionList.append(item)
                    }
                }
            case 2:
                sectionList.append(contentsOf: roomInfoViewModel.roomList)
            default:
                break
        }
    }
    
    
}
