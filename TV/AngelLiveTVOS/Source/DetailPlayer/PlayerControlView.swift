//
//  PlayerControlView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/27.
//

import SwiftUI
import TipKit
import AVFoundation
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
    @State private var showStatisticsPanel = false
    @State private var showQualityPanel = false
    @State private var suppressHiddenFocusActivation = false
    @State private var pendingVisibleFocusAfterReveal: PlayControlFocusableField?
    @State private var showVolumeHUD = false
    @State private var volumeHUDHideTask: Task<Void, Never>?
    @StateObject private var systemVolumeObserver = TVSystemVolumeObserver()

    @FocusState var state: PlayControlFocusableField?
    @FocusState var topState: PlayControlTopField?
    @FocusState var showDanmuSetting: Bool

    @ObservedObject var playerCoordinator: KSVideoPlayer.Coordinator

    private let multiCameraTip = MultiCameraTip()

    /// 是否有多机位（cdn数量大于1）
    private var hasMultiCamera: Bool {
        (roomInfoViewModel.currentRoomPlayArgs?.count ?? 0) > 1
    }
    
    private func topTabLabel(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .contentShape(Capsule())
    }


    var body: some View {
        
        @Bindable var roomInfoModel = roomInfoViewModel
        
        ZStack {
            if roomInfoViewModel.showTop {
                VStack {
                    VStack(spacing: 105) {
                        // 顶部 Tab 栏（固定 55pt）
                        HStack {
                            Spacer()
                            HStack(spacing: 12) {
                                if showsFavoriteTopTab {
                                    Button(action: {}) {
                                        topTabLabel("收藏")
                                    }
                                    .focused($topState, equals: .section(0))
                                }
                                Button(action: {}) {
                                    topTabLabel("历史")
                                }
                                .focused($topState, equals: .section(1))
                                if roomInfoModel.roomType == .live {
                                    Button(action: {}) {
                                        topTabLabel("分区")
                                    }
                                    .focused($topState, equals: .section(2))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .adaptiveGlassEffectCapsule()
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .frame(height: 55)
                        .focusSection()
                        .onChange(of: topState) { oldValue, newValue in
                            switch newValue {
                                case .section(let index):
                                    changeList(index)
                                default:
                                    break
                            }
                        }
                        
                        // 卡片区域（占满剩余高度）
                        ScrollView(.horizontal) {
                            LazyHGrid(rows: [GridItem(.flexible())], content: {
                                ForEach(sectionList.indices, id: \.self) { index in
                                    PlayerControlCardView() { liveModel in
                                        changeRoom(liveModel)
                                    }
                                    .environment(PlayerControlCardViewModel(liveModel: sectionList[index], cardIndex: index, selectIndex: selectIndex))
                                }
                            })
                            .padding()
                        }
                        .padding([.leading, .trailing], 55)
                        .padding(.top, 65)
                        .scrollClipDisabled()
                        .focusSection()
                        
                        Spacer()
                    }
                    .background(.black.opacity(0.6))
                    .frame(width: 1920, height: 390)
                    .padding(.top, 30)
                    .transition(.move(edge: .top))
                    .onExitCommand(perform: {
                        withAnimation {
                            roomInfoViewModel.showTop = false
                        }
                        DispatchQueue.main.async {
                            if roomInfoViewModel.showControl {
                                restoreControlFocus()
                            } else {
                                restoreHiddenControlFocus()
                            }
                        }
                    })
                    
                    Spacer()
                }
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

                if showStatisticsPanel {
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            TVPlayerStatisticsPanel(
                                playerCoordinator: playerCoordinator,
                                qualityTitle: roomInfoViewModel.currentPlayQualityString,
                                streamURL: roomInfoViewModel.currentPlayURL
                            ) {
                                hideStatisticsPanel()
                            }
                            .frame(width: min(geometry.size.width * 0.4, 640), height: geometry.size.height - 80)
                            .padding(.vertical, 40)
                            .padding(.trailing, 48)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .zIndex(5)
                }

                if showQualityPanel {
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            TVQualitySelectionPanel(
                                onSelect: { cdnIndex, urlIndex in
                                    roomInfoViewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                                    hideQualityPanel()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        if playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                                            playerCoordinator.playerLayer?.play()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                                roomInfoViewModel.showControlView = false
                                            }
                                        }
                                    }
                                },
                                onClose: {
                                    hideQualityPanel()
                                }
                            )
                            .frame(width: min(geometry.size.width * 0.4, 640), height: geometry.size.height - 80)
                            .padding(.vertical, 40)
                            .padding(.trailing, 48)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .zIndex(5)
                }

                if shouldShowHiddenControlAnchors {
                    hiddenControlAnchorOverlay
                        .zIndex(1)
                }

                if showVolumeHUD {
                    VStack {
                        Spacer().frame(height: 90)
                        volumeHUDView
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(6)
                }

                if let hint = roomInfoViewModel.danmuStatusHint {
                    VStack {
                        Spacer()
                        HStack {
                            danmuHintBubble(text: hint)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            Spacer()
                        }
                    }
                    // 左下角,抬到底部控制带(高 150)之上;左边距与播放控制胶囊左缘对齐
                    // (HStack 起点 0 + 隐藏聚焦按钮 40 + spacing 15 ≈ 55)
                    .padding(.leading, 55)
                    .padding(.bottom, 170)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(7)
                }

                if roomInfoViewModel.showControl {
                    VStack {
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
                                    Button {
                                        showStatisticsAction()
                                    } label: {
                                        Label("视频信息统计", systemImage: "chart.bar.xaxis")
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
                                    .frame(width: 150, height: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0.01)
                        }
                        .padding(.top, 60)
                       
                        Spacer()
                        VStack {
                            HStack(spacing: 0) {
                                if roomInfoViewModel.showControl {
                                    Button {
                                        showQualityAction()
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

                                if roomInfoViewModel.supportsDanmu {
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
                                    .frame(width: 150, height: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0.01)
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
                    .focusSection()
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            Logger.debug("[VolumeHUD] PlayerControlView appeared, initial volume=\(systemVolumeObserver.volume)", category: .ui)
            roomInfoViewModel.showControl = true
            restoreControlFocus()
        }
        .onDisappear {
            volumeHUDHideTask?.cancel()
            volumeHUDHideTask = nil
        }
        // 订阅 TVSystemVolumeObserver:tick 每次音量回调 +1,触发 HUD
        // 触发条件:音频路由经 Apple TV 控制(HomePod / AirPods / AirPlay 2)。
        // HDMI-CEC 让电视自管音量时,系统不会回传给 App,这是平台限制。
        .onChange(of: systemVolumeObserver.changeTick) { _, _ in
            presentVolumeHUD()
        }
        .onChange(of: roomInfoViewModel.showControl) { oldValue, isVisible in
            if isVisible {
                restoreControlFocus()
            } else {
                pendingVisibleFocusAfterReveal = nil
                restoreHiddenControlFocus()
            }
        }
        .onChange(of: state, { oldValue, newValue in
            roomInfoViewModel.controlViewOptionSecond = 5

            if oldValue != .list && isListContentField(oldValue) == false && oldValue != nil {
                roomInfoViewModel.lastOptionState = oldValue
            }

            guard roomInfoViewModel.showTop == false,
                  roomInfoViewModel.showDanmuSettingView == false,
                  showStatisticsPanel == false,
                  showQualityPanel == false else {
                return
            }

            if roomInfoViewModel.showControl == false {
                if suppressHiddenFocusActivation {
                    suppressHiddenFocusActivation = false
                }
                return
            }

            if newValue == .left {
                state = .danmu
            }else if newValue == .right {
                state = .playPause
            }else if newValue == .list {
                showRelatedRoomsPanel()
            }
        })
        .onExitCommand {
            guard roomInfoViewModel.showTop == false,
                  roomInfoViewModel.showDanmuSettingView == false,
                  showStatisticsPanel == false,
                  showQualityPanel == false else {
                return
            }

            if roomInfoViewModel.showControl {
                withAnimation(.easeInOut(duration: 0.2)) {
                    roomInfoViewModel.showControl = false
                }
            } else {
                roomInfoViewModel.liveFlagTimer?.invalidate()
                roomInfoViewModel.liveFlagTimer = nil
                NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil)
            }
        }
    }

    private func showStatisticsAction() {
        guard ensureControlVisible() else { return }
        roomInfoViewModel.lastOptionState = state ?? .playPause
        state = nil
        withAnimation(.easeInOut(duration: 0.28)) {
            showStatisticsPanel = true
            roomInfoViewModel.showControl = false
        }
    }

    private func hideStatisticsPanel() {
        withAnimation(.easeInOut(duration: 0.28)) {
            showStatisticsPanel = false
            roomInfoViewModel.showControl = true
        }
    }

    private func showQualityAction() {
        guard ensureControlVisible() else { return }
        roomInfoViewModel.lastOptionState = state ?? .playQuality
        state = nil
        withAnimation(.easeInOut(duration: 0.28)) {
            showQualityPanel = true
            roomInfoViewModel.showControl = false
        }
    }

    private func hideQualityPanel() {
        withAnimation(.easeInOut(duration: 0.28)) {
            showQualityPanel = false
            roomInfoViewModel.showControl = true
        }
    }

    private var shouldShowHiddenControlAnchors: Bool {
        roomInfoViewModel.showControl == false &&
        roomInfoViewModel.showTop == false &&
        roomInfoViewModel.showDanmuSettingView == false &&
        showStatisticsPanel == false &&
        showQualityPanel == false
    }

    @ViewBuilder
    private var hiddenControlAnchorOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 15) {
                hiddenControlAnchor(width: 40, height: 40, focus: .left)
                    .padding(.leading, -80)

                VStack(spacing: 20) {
                    HStack(spacing: 0) {
                        hiddenControlAnchor(width: 50, height: 60, focus: .playPause)
                        hiddenControlAnchor(width: 50, height: 60, focus: .refresh)
                        hiddenControlAnchor(width: 50, height: 60, focus: .favorite)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 10)

                    hiddenControlAnchor(width: 150, height: 40, focus: .list)
                }

                Spacer()

                VStack(spacing: 20) {
                    HStack(spacing: 0) {
                        hiddenControlAnchor(width: 150, height: 60, focus: .playQuality)
                        Color.clear.frame(width: 15)
                        hiddenControlAnchor(width: 50, height: 60, focus: .danmuSetting)
                        hiddenControlAnchor(width: 50, height: 60, focus: .danmu)
                    }
                    .padding(.leading, 15)
                    .padding(.vertical, 10)

                    hiddenControlAnchor(width: 150, height: 40, focus: .list)
                }

                hiddenControlAnchor(width: 40, height: 40, focus: .right)
                    .padding(.trailing, -80)
            }
            .frame(height: 150)
            .offset(y: 220)
        }
        .ignoresSafeArea()
    }

    private func hiddenControlAnchor(width: CGFloat, height: CGFloat, focus: PlayControlFocusableField) -> some View {
        Button(action: {}) {
            Color.clear
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($state, equals: focus)
        .onMoveCommand { direction in
            handleHiddenAnchorMove(from: focus, direction: direction)
        }
    }

    private func restoreControlFocus() {
        guard roomInfoViewModel.showTop == false,
              roomInfoViewModel.showDanmuSettingView == false,
              showStatisticsPanel == false,
              showQualityPanel == false else {
            return
        }

        let preferredFocus = pendingVisibleFocusAfterReveal ?? (state == .list ? roomInfoViewModel.lastOptionState : (state ?? roomInfoViewModel.lastOptionState))
        let target = resolvedVisibleControlFocus(from: preferredFocus)
        DispatchQueue.main.async {
            state = nil
            DispatchQueue.main.async {
                state = target
                pendingVisibleFocusAfterReveal = nil
            }
        }
    }

    private func handleHiddenAnchorMove(from focus: PlayControlFocusableField, direction: MoveCommandDirection) {
        guard shouldShowHiddenControlAnchors else {
            return
        }


        switch direction {
        case .down:
            showRelatedRoomsPanel()
        case .left, .right:
            guard let target = nextVisibleFocus(from: focus, direction: direction) else {
                return
            }

            pendingVisibleFocusAfterReveal = target
            withAnimation(.easeInOut(duration: 0.2)) {
                roomInfoViewModel.showControl = true
            }
        default:
            break
        }
    }

    private func restoreHiddenControlFocus() {
        guard shouldShowHiddenControlAnchors else {
            return
        }

        let preferredFocus = state == .list ? roomInfoViewModel.lastOptionState : (state ?? roomInfoViewModel.lastOptionState)
        let target = resolvedHiddenAnchorFocus(from: preferredFocus)

        suppressHiddenFocusActivation = true
        DispatchQueue.main.async {
            state = nil
            DispatchQueue.main.async {
                state = target
            }
        }
    }

    private func showRelatedRoomsPanel() {
        let initialSection = preferredTopSectionIndex()
        changeList(initialSection)

        withAnimation(.easeInOut(duration: 0.2)) {
            roomInfoViewModel.showTop = true
        }

        DispatchQueue.main.async {
            topState = .section(initialSection)
        }
    }

    /// 顶部面板是否显示「收藏」Tab。本地优先(Core 模型):有本地收藏就显示,不依赖 iCloud 是否就绪。
    private var showsFavoriteTopTab: Bool {
        !appViewModel.favoriteViewModel.roomList.isEmpty
    }

    private func preferredTopSectionIndex() -> Int {
        if roomInfoViewModel.roomType == .live {
            return 2
        }
        // 收藏 Tab 渲染了才默认聚焦它,否则退到「历史」(section 1),避免聚焦未渲染的 Tab。
        return showsFavoriteTopTab ? 0 : 1
    }

    private func resolvedVisibleControlFocus(from candidate: PlayControlFocusableField?) -> PlayControlFocusableField {
        switch candidate {
        case .refresh, .favorite, .playQuality, .danmu, .danmuSetting, .left, .right:
            return candidate ?? .playPause
        case .playPause:
            return .playPause
        default:
            return .playPause
        }
    }

    private func resolvedHiddenAnchorFocus(from candidate: PlayControlFocusableField?) -> PlayControlFocusableField {
        switch candidate {
        case .playPause, .refresh, .favorite, .playQuality, .danmu, .list, .left, .right, .danmuSetting:
            return candidate ?? .playPause
        default:
            return .playPause
        }
    }

    private func nextVisibleFocus(from focus: PlayControlFocusableField, direction: MoveCommandDirection) -> PlayControlFocusableField? {
        switch (focus, direction) {
        case (.left, .right):
            return .playPause
        case (.playPause, .left):
            return .left
        case (.playPause, .right):
            return .refresh
        case (.refresh, .left):
            return .playPause
        case (.refresh, .right):
            return .favorite
        case (.favorite, .left):
            return .refresh
        case (.favorite, .right):
            return .playQuality
        case (.playQuality, .left):
            return .favorite
        case (.playQuality, .right):
            return .danmuSetting
        case (.danmuSetting, .left):
            return .playQuality
        case (.danmuSetting, .right):
            return .danmu
        case (.danmu, .left):
            return .danmuSetting
        case (.danmu, .right):
            return .right
        case (.right, .left):
            return .danmu
        default:
            return nil
        }
    }
    
    func favoriteAction() {
        roomInfoViewModel.currentRoomLikeLoading = true
        let isAdding = appViewModel.favoriteViewModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) == false
        Task { @MainActor in
            defer { roomInfoViewModel.currentRoomLikeLoading = false }
            do {
                if isAdding {
                    roomInfoViewModel.currentRoom.liveState = try await ApiManager.getCurrentRoomLiveState(
                        roomId: roomInfoViewModel.currentRoom.roomId,
                        userId: roomInfoViewModel.currentRoom.userId,
                        liveType: roomInfoViewModel.currentRoom.liveType
                    ).rawValue
                    try await appViewModel.favoriteViewModel.addFavorite(room: roomInfoViewModel.currentRoom)
                    roomInfoViewModel.currentRoomIsLiked = true
                    roomInfoViewModel.showToast(true, title: "收藏成功")
                } else {
                    try await appViewModel.favoriteViewModel.removeFavoriteRoom(room: roomInfoViewModel.currentRoom)
                    appViewModel.favoriteViewModel.roomList.removeAll(where: { $0.roomId == roomInfoViewModel.currentRoom.roomId })
                    roomInfoViewModel.currentRoomIsLiked = false
                    roomInfoViewModel.showToast(true, title: "取消收藏成功")
                }
                TopShelfManager.notifyContentChanged()
            } catch {
                let detail = FavoriteService.formatErrorCode(error: error)
                roomInfoViewModel.showToast(false, title: isAdding ? "收藏失败：\(detail)" : "取消收藏失败：\(detail)")
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
        guard roomInfoViewModel.supportsDanmu else { return }
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

    private func presentVolumeHUD() {
        volumeHUDHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            showVolumeHUD = true
        }
        volumeHUDHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showVolumeHUD = false
            }
        }
    }


    private func volumeIconName(for value: Float) -> String {
        if value <= 0.001 {
            return "speaker.slash.fill"
        } else if value < 0.34 {
            return "speaker.wave.1.fill"
        } else if value < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func volumeIcon(for value: Float) -> some View {
        Image(systemName: volumeIconName(for: value))
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36)
            .contentTransition(.symbolEffect(.replace))
    }

    private var volumeHUDView: some View {
        let raw = systemVolumeObserver.volume
        let value = CGFloat(max(0.0, min(1.0, raw)))
        return HStack(spacing: 14) {
            volumeIcon(for: raw)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(2, geo.size.width * value))
                }
            }
            .frame(width: 280, height: 8)

            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .adaptiveGlassEffectCapsule()
    }

    /// 弹幕状态气泡:黑色半透明胶囊 + 白字
    private func danmuHintBubble(text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.black.opacity(0.6), in: Capsule())
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
                for item in appViewModel.favoriteViewModel.roomList {
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
