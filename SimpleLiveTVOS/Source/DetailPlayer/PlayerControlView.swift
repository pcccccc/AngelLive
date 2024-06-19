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
    case section
    case list
}


struct PlayerControlView: View {
    
    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(SimpleLiveViewModel.self) var appViewModel

    @FocusState var state: PlayControlFocusableField?
    @State var lastOptionState: PlayControlFocusableField?
    @State var showTop = false
    @State var onceTips = false
    @State var showControl = false {
        didSet {
            if showControl == true {
                controlViewOptionSecond = 5  // 重置计时器
            }
        }
    }
    @State var showTips = false {
        didSet {
            if showTips == true {
                startTipsTimer()
                onceTips = true
            }
        }
    }
    @State private var controlViewOptionSecond = 5 {
        didSet {
            if controlViewOptionSecond == 5 {
                startTimer()
            }
        }
    }
    @State private var tipOptionSecond = 3
    @State private var contolTimer: Timer? = nil
    @State private var tipsTimer: Timer? = nil
    
    let topGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.1)]),
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
            if showTop {
                VStack(spacing: 20) {
                    HStack {
                        Button("收藏") {
                            
                        }
                        Button("历史") {
                            
                        }
                        Button("分区") {
                            
                        }
                    }
                    .buttonStyle(.plain)
                    .focusSection()
                    
                    ScrollView(.horizontal) {
                        LazyHGrid(rows: [GridItem(.fixed(192))], content: {
                            ForEach(0..<10) { i in
                                Button {
                                    
                                } label: {
                                    Image("1")
                                        .resizable()
                                }
                                .frame(width: 320, height: 192)
                                .buttonStyle(.borderless)
                                .focused($state, equals: .listContent(i))
                            }
                        })
                    }
                    
                    .frame(height: 192)
                    .padding([.leading, .trailing], 55)
                    .scrollClipDisabled()
                    .focusSection()
                    
                    Spacer()
                }
                .frame(width: 1920)
                .buttonStyle(.plain)
                .transition(.move(edge: .top))
                .onExitCommand(perform: {
                    withAnimation {
                        showTop = false
                    }
                    state = lastOptionState
                })
            }else {
                VStack {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                                .frame(height: 15)
                            Text("下滑切换直播间")
                                .foregroundStyle(.gray)
                            Image(systemName: "chevron.compact.down")
                                .foregroundStyle(.gray)
                        }
                        .shimmering(active: true)
                        Spacer()
                    }
                    Spacer()
                }
                .opacity(showTips ? 1 : 0)
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
                                Image(systemName: appViewModel.favoriteModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) ? "heart.fill" : "heart")
                                    .foregroundColor(.white)
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
                .opacity(showControl ? 1 : 0)
//                .onExitCommand {
//                    if showControl == true {
//                        showControl.toggle()
//                    }
//                }
            }
        }
        .onAppear {
            state = .playPause
            showControl = true
        }
        .onChange(of: state, { oldValue, newValue in
            
            if showControl == false {
                showControl.toggle()
            }else {
                controlViewOptionSecond = 5
            }
            
            if oldValue != .list && isListContentField(oldValue) == false && oldValue != nil {
                lastOptionState = oldValue
            }
            print(lastOptionState)
            print(state)
            
            if newValue == .left {
                state = .danmu
            }else if newValue == .right {
                state = .playPause
            }else if newValue == .list {
                withAnimation {
                    showTop = true
                    state = .listContent(0)
                }
            }
            
        })
        
    }
    
    func favoriteAction() {
        if appViewModel.favoriteModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) == false {
            Task {
                try await appViewModel.favoriteModel.addFavorite(room: roomInfoViewModel.currentRoom)
                appViewModel.showToast(true, title: "收藏成功")
            }
        }else {
            Task {
                try await  appViewModel.favoriteModel.removeFavoriteRoom(room: roomInfoViewModel.currentRoom)
                appViewModel.showToast(true, title: "取消收藏成功")
            }
        }
    }
    
    func startTimer() {
        
        contolTimer?.invalidate() // 停止之前的计时器
        contolTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            print(controlViewOptionSecond)
            if controlViewOptionSecond > 0 {
                controlViewOptionSecond -= 1
            } else {
                withAnimation {
                    showControl = false
                    if onceTips == false {
                        showTips = true
                    }
                }
                contolTimer?.invalidate() // 计时器停止
            }
        }
    }
    
    func startTipsTimer() {
        
        if onceTips {
            return
        }
        
        tipsTimer?.invalidate() // 停止之前的计时器
        tipOptionSecond = 3 // 重置计时器

        tipsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if tipOptionSecond > 0 {
                tipOptionSecond -= 1
            } else {
                withAnimation {
                    showTips = false
                }
                tipsTimer?.invalidate() // 计时器停止
            }
        }
    }
    
    func playPauseAction() {
        if (roomInfoViewModel.showControlView == false) {
            roomInfoViewModel.showControlView = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                if roomInfoViewModel.showControlView == true {
                    roomInfoViewModel.showControlView = false
                }
            })
        }else {
            if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false {
                roomInfoViewModel.playerCoordinator.playerLayer?.pause()
            }else {
                roomInfoViewModel.playerCoordinator.playerLayer?.play()
            }
        }
    }
    
    func refreshAction() {
        if (roomInfoViewModel.showControlView == false) {
            roomInfoViewModel.showControlView = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                if roomInfoViewModel.showControlView == true {
                    roomInfoViewModel.showControlView = false
                }
            })
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
        if (roomInfoViewModel.showControlView == false) {
            roomInfoViewModel.showControlView = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                if roomInfoViewModel.showControlView == true {
                    roomInfoViewModel.showControlView = false
                }
            })
        }else {
            withAnimation(.easeInOut(duration: 0.3)) {
                favoriteAction()
            }
        }
    }
    
    func danmuAction() {
        if (roomInfoViewModel.showControlView == false) {
            roomInfoViewModel.showControlView = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                if roomInfoViewModel.showControlView == true {
                    roomInfoViewModel.showControlView = false
                }
            })
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
}
