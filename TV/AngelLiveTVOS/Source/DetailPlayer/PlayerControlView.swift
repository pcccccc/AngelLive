//
//  PlayerControlView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/27.
//

import SwiftUI
import TipKit
import AngelLiveCore
import AngelLiveDependencies

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
    case danmuSetting
}

enum PlayControlTopField: Hashable {
    case section(Int)
    case list(Int)
}


struct PlayerControlView: View {

    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(AppState.self) var appViewModel

    @State var sectionList: [LiveModel] = []
    @State var selectIndex = 0

    @FocusState var state: PlayControlFocusableField?
    @FocusState var topState: PlayControlTopField?
    @FocusState var showDanmuSetting: Bool

    @ObservedObject var playerCoordinator: KSVideoPlayer.Coordinator

    private let multiCameraTip = MultiCameraTip()

    /// 是否有多机位（cdn数量大于1）
    private var hasMultiCamera: Bool {
        (roomInfoViewModel.currentRoomPlayArgs?.count ?? 0) > 1
    }

    var body: some View {
        
        @Bindable var roomInfoModel = roomInfoViewModel
        
        ZStack {
            if roomInfoViewModel.showTop {
                VStack(spacing: 50) {
                    VStack {
                        HStack {
                            Spacer()
                            if appViewModel.favoriteViewModel.cloudKitReady {
                                Button("收藏") {}
                                .clipShape(.circle)
                                .focused($topState, equals: .section(0))
                            }
                            Button("历史") {}
                            .clipShape(.circle)
                            .focused($topState, equals: .section(1))
                            if roomInfoModel.roomType == .live {
                                Button("分区") {}
                                .clipShape(.circle)
                                .focused($topState, equals: .section(2))
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
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
                if roomInfoModel.showDanmuSettingView == true {
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            DanmuSettingMainView(showDanmuView: _showDanmuSetting)
                                .environment(appViewModel)
                                .frame(width: geometry.size.width / 2 - 100, height: geometry.size.height)
                                .padding([.leading, .trailing], 50)
                                .background(.thinMaterial)
                                .focused($state, equals: .danmuSetting)
                                .onExitCommand {
                                    if roomInfoModel.showDanmuSettingView == true {
                                        roomInfoModel.showDanmuSettingView.toggle()
                                        showDanmuSetting.toggle()
                                        state = roomInfoViewModel.lastOptionState
                                        roomInfoViewModel.showControl = true
                                    }
                                }
                        }
                    }
                }
                
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
                            LinearGradient(colors: [
                                .black,
                                .black.opacity(0.5),
                                .black.opacity(0.1),
                                .clear,
                                .clear,
                                .clear,
                                .clear,
                                .clear,
                            ], startPoint: .top, endPoint: .bottom)
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
                            HStack(spacing: 0) {
                                Button(action: {
                                    guard ensureControlVisible() else { return }
                                    roomInfoViewModel.togglePlayPause()
                                }, label: {
                                    Image(systemName: roomInfoViewModel.userPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                })
                                .clipShape(.circle)
                                .contextMenu(menuItems: {
                                    Button("debug mode") {
                //                        roomInfoViewModel.toggleTimer()
                                    }
                                })
                                .focused($state, equals: .playPause)

                                Button(action: {
                                    refreshAction()
                                }, label: {
                                    Image(systemName: "arrow.trianglehead.2.counterclockwise")
                                        .foregroundColor(.white)
                                        .font(.system(size: 30, weight: .bold))
                                        .frame(width: 40, height: 40)
                                })
                                .clipShape(.circle)
                                .focused($state, equals: .refresh)

                                Button(action: {
                                    favoriteBtnAction()
                                }, label: {
                                    if roomInfoModel.currentRoomLikeLoading {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 40, height: 40)
                                    }else {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(roomInfoModel.currentRoomIsLiked ? .red : .white)
                                            .font(.system(size: 30, weight: .bold))
                                            .frame(width: 40, height: 40)
                                            .padding(.top, 3)
                                    }
                                })
                                .clipShape(.circle)
                                .focused($state, equals: .favorite)
                                .changeEffect(
                                    .spray(origin: UnitPoint(x: 0.25, y: 0.5)) {
                                        Image(systemName:roomInfoModel.currentRoomIsLiked ? "heart.fill" : "heart.slash.fill" )
                                        .foregroundStyle(.red)
                                    }, value: roomInfoModel.currentRoomIsLiked)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 10)
                            .adaptiveGlassEffectCapsule()

                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                       
                        Spacer()
                        VStack {
                            HStack(spacing: 0) {
                                if roomInfoViewModel.showControl {
                                    Menu {
                                        if let playArgs = roomInfoViewModel.currentRoomPlayArgs, !playArgs.isEmpty {
                                            ForEach(playArgs.indices, id: \.self) { index in
                                                let cdn = playArgs[index]
                                                let cdnName = cdn.cdn.isEmpty ? "线路 \(index + 1)" : cdn.cdn
                                                Menu(cdnName) {
                                                    ForEach(cdn.qualitys.indices, id: \.self) { subIndex in
                                                        Button {
                                                            roomInfoViewModel.changePlayUrl(cdnIndex: index, urlIndex: subIndex)
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                                                                if playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                                                                    playerCoordinator.playerLayer?.play()
                                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                                                                        roomInfoViewModel.showControlView = false
                                                                    })
                                                                }
                                                            })
                                                        } label: {
                                                            Text(cdn.qualitys[subIndex].title)
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            Button("暂无线路") {}
                                                .disabled(true)
                                        }
                                    } label: {
                                        qualityLabel()
                                    }
                                    .focused($state, equals: .playQuality)
                                    .frame(height: 60)
                                    .clipShape(.capsule)
                                } else {
                                    Button(action: {
                                        roomInfoViewModel.showControl = true
                                    }, label: {
                                        qualityLabel()
                                    })
                                    .focused($state, equals: .playQuality)
                                    .frame(height: 60)
                                    .clipShape(.capsule)
                                }
//                                .popoverTip(multiCameraTip, arrowEdge: .top) { _ in
//                                    // 点击 Tip 后关闭
//                                }

                                Text("")
                                    .frame(width: 15)

                                Button(action: {
                                    guard ensureControlVisible() else { return }
                                    roomInfoModel.showDanmuSettingView = true
                                    roomInfoModel.showControl = false
                                    showDanmuSetting = true
                                    state = .danmuSetting
                                }, label: {
                                    Image("icon-danmu-setting-focus")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                })
                                .clipShape(.circle)
                                .focused($state, equals: .danmuSetting)
                                
                                
                                Button(action: {
                                    danmuAction()
                                }, label: {
                                    Image(appViewModel.danmuSettingsViewModel.showDanmu ? "icon-danmu-open-focus" : "icon-danmu-close-focus")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                })
                                .clipShape(.circle)
                                .focused($state, equals: .danmu)
                            }
                            .padding(.leading, 15)
                            .padding(.vertical, 10)
                            .adaptiveGlassEffectCapsule()
                            .onAppear {
                                if !hasMultiCamera {
                                    multiCameraTip.invalidate(reason: .actionPerformed)
                                }
                            }

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
                        LinearGradient(colors: [
                            .clear,
                            .clear,
                            .clear,
                            .clear,
                            .clear,
                            .black.opacity(0.1),
                            .black.opacity(0.5),
                            .black
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                    }
                    .frame(height: 150)
                }
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
                .opacity(roomInfoViewModel.showControl ? 1 : 0)
                .onExitCommand {
                    if roomInfoViewModel.showControl == true {
                        roomInfoViewModel.showControl = false
                        return
                    }
                    if roomInfoViewModel.showDanmuSettingView == true {
                        state = roomInfoViewModel.lastOptionState
                        return
                    }
                    if roomInfoViewModel.showControl == false {
                        roomInfoViewModel.liveFlagTimer?.invalidate()
                        roomInfoViewModel.liveFlagTimer = nil
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
            roomInfoViewModel.controlViewOptionSecond = 5
            
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
    }
    
    func favoriteAction() {
        roomInfoViewModel.currentRoomLikeLoading = true
        if appViewModel.favoriteViewModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) == false {
            Task {
                roomInfoViewModel.currentRoom.liveState = try await ApiManager.getCurrentRoomLiveState(roomId: roomInfoViewModel.currentRoom.roomId, userId: roomInfoViewModel.currentRoom.userId, liveType: roomInfoViewModel.currentRoom.liveType).rawValue
                try await appViewModel.favoriteViewModel.addFavorite(room: roomInfoViewModel.currentRoom)
                roomInfoViewModel.currentRoomIsLiked = true
                roomInfoViewModel.showToast(true, title: "收藏成功")
                roomInfoViewModel.currentRoomLikeLoading = false
                TopShelfManager.notifyContentChanged()
            }
        }else {
            Task {
                try await  appViewModel.favoriteViewModel.removeFavoriteRoom(room: roomInfoViewModel.currentRoom)
                appViewModel.favoriteViewModel.roomList.removeAll(where: { $0.roomId == roomInfoViewModel.currentRoom.roomId })
                roomInfoViewModel.currentRoomIsLiked = false
                roomInfoViewModel.showToast(true, title: "取消收藏成功")
                roomInfoViewModel.currentRoomLikeLoading = false
                TopShelfManager.notifyContentChanged()
            }
        }
    }

    func refreshAction() {
        guard ensureControlVisible() else { return }
        roomInfoViewModel.refreshPlayback()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            if playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                playerCoordinator.playerLayer?.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                    roomInfoViewModel.showControlView = false
                })
            }
        })
    }
    
    func favoriteBtnAction() {
        guard ensureControlVisible() else { return }
        favoriteAction()
    }
    
    func danmuAction() {
        guard ensureControlVisible() else { return }
        appViewModel.danmuSettingsViewModel.showDanmu.toggle()
        if appViewModel.danmuSettingsViewModel.showDanmu == false {
            roomInfoViewModel.disConnectSocket()
        }else {
            roomInfoViewModel.getDanmuInfo()
        }
    }

    @discardableResult
    private func ensureControlVisible() -> Bool {
        if roomInfoViewModel.showControl == false {
            roomInfoViewModel.showControl = true
            return false
        }
        return true
    }

    @ViewBuilder
    private func qualityLabel() -> some View {
        if #available(tvOS 26.0, *) {
            Text(roomInfoViewModel.currentPlayQualityString)
                .font(.system(size: 30, weight: .bold))
                .frame(height: 50, alignment: .center)
                .foregroundStyle(.white)
        }else {
            Text(roomInfoViewModel.currentPlayQualityString)
                .font(.system(size: 30, weight: .bold))
                .frame(height: 50, alignment: .center)
                .padding(.top, 10)
                .foregroundStyle(.white)
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
                for item in appViewModel.favoriteViewModel.roomList ?? [] {
                    if item.liveState ?? "0" == LiveState.live.rawValue {
                        sectionList.append(item)
                    }
                }
            case 1:
                Task {
                    for item in appViewModel.historyViewModel.watchList {
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
