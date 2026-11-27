//
//  DetailPlayerView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import Combine

/// FullUI routes explicitly declared episodic content to its own player surface.
struct DetailPlayerView: View {
    @Environment(\.fullUIRoomPlayerPushed) private var isPushed
    @State private var routedOnDemandRoom: LiveModel?
    let opensShortDramaHistory: Bool
    let viewModel: RoomInfoViewModel
    let categoryRooms: [LiveModel]
    let canLoadMoreCategoryRooms: () -> Bool
    let onLoadMoreCategoryRooms: (() async -> [LiveModel])?
    let entryRoomSource: RoomSwitchSource?

    private var presentsOverRoomList: Bool {
        if #available(iOS 18.0, *) { return !isPushed }
        return false
    }

    init(
        viewModel: RoomInfoViewModel,
        categoryRooms: [LiveModel] = [],
        canLoadMoreCategoryRooms: @escaping () -> Bool = { false },
        onLoadMoreCategoryRooms: (() async -> [LiveModel])? = nil,
        entryRoomSource: RoomSwitchSource? = nil,
        opensShortDramaHistory: Bool = false
    ) {
        self.opensShortDramaHistory = opensShortDramaHistory
        self.viewModel = viewModel
        self.categoryRooms = categoryRooms
        self.canLoadMoreCategoryRooms = canLoadMoreCategoryRooms
        self.onLoadMoreCategoryRooms = onLoadMoreCategoryRooms
        self.entryRoomSource = entryRoomSource
    }

    var body: some View {
        let room = routedOnDemandRoom ?? viewModel.currentRoom
        Group {
            if !opensShortDramaHistory && VodRouting.usesDirectPlayer(room) {
                VodDirectPlayerView(room: room)
                    .id(room.id)
            } else if !opensShortDramaHistory && VodRouting.declaresVod(room) {
                let detail = VodWorkDetailView(room: room, presentsOverSource: presentsOverRoomList)
                    .id(room.id)
                    .interactivePopGestureEnabled(false, edgeOnly: true)
                    .interactiveDismissDisabled()
                if presentsOverRoomList {
                    detail.presentationBackground(.clear)
                } else {
                    detail
                }
            } else if opensShortDramaHistory || ShortDramaRouting.isShortDrama(room) {
                let player = ShortDramaPlayerView(room: room, presentsOverSource: presentsOverRoomList)
                    .id(room.id)
                    .interactivePopGestureEnabled(false, edgeOnly: true)
                if presentsOverRoomList {
                    player.presentationBackground(.clear)
                } else {
                    player
                }
            } else {
                let player = LiveDetailPlayerView(
                    viewModel: viewModel,
                    categoryRooms: categoryRooms,
                    canLoadMoreCategoryRooms: canLoadMoreCategoryRooms,
                    onLoadMoreCategoryRooms: onLoadMoreCategoryRooms,
                    entryRoomSource: entryRoomSource,
                    presentsOverRoomList: presentsOverRoomList,
                    onRouteOnDemandRoom: { routedOnDemandRoom = $0 }
                )
                .interactiveDismissDisabled()
                if presentsOverRoomList {
                    player.presentationBackground(.clear)
                } else {
                    player
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.usesFullUIPlayerSheets, true)
        .fullUIWindowContext()
    }
}

struct LiveDetailPlayerView: View {
    private enum EntryPhase: Equatable {
        case waitingForSize
        case expandingDetails(aspectRatio: CGFloat)
        case resolvedLayout
        case finished

        var expandingAspectRatio: CGFloat? {
            guard case let .expandingDetails(aspectRatio) = self else { return nil }
            return aspectRatio
        }
    }

    @State var viewModel: RoomInfoViewModel
    let categoryRooms: [LiveModel]
    let canLoadMoreCategoryRooms: () -> Bool
    let onLoadMoreCategoryRooms: (() async -> [LiveModel])?
    let presentsOverRoomList: Bool
    let onRouteOnDemandRoom: ((LiveModel) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullUIWindowContext) private var windowContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(HistoryModel.self) private var historyModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// 全局播放器 coordinator，在整个 DetailPlayerView 生命周期中保持
    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()
    /// 稳定的播放器模型，避免随视图重建
    @StateObject private var playerModel = KSVideoPlayerModel(title: "", config: KSVideoPlayer.Coordinator(), options: KSOptions(), url: nil)
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary,
        supportedGlobalCapabilities: [.audioFocus, .nowPlaying, .pictureInPicture, .remoteCommands]
    )

    @State private var entryPhase = EntryPhase.waitingForSize
    @State private var declaredOrientation: HostContentOrientation?
    @State private var transientOrientationRequest: UUID?
    @State private var entryVLCPlaybackStarted = false

    /// Fullscreen intent is independent of whether the scene accepts a rotation request.
    @State private var isIPadFullscreen: Bool = false

    /// 播放画面与信息区共用已确认的媒体比例，避免独立高度反馈滞后。
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0

    /// 是否为竖屏直播模式
    @State private var isVerticalLiveMode: Bool = false
    /// 用户主动控制竖屏清屏状态，不随播放器的自动隐藏或播放状态改变。
    @State private var verticalLiveControlsVisible = true
    @State private var verticalLiveControlPopupPresented = false
    @State private var playerContentBlocksSwipe = false

    /// Only a vertically compact phone layout needs to hide the information panel.
    private var isIPhoneLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var usesExpandedLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    private var isFullscreen: Bool {
        isIPhoneLandscape || isIPadFullscreen
    }

    private var supportsEntryLoading: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && horizontalSizeClass == .compact && verticalSizeClass == .regular
            && !isFullscreen && !viewModel.isOnDemand
            && viewModel.currentRoom.liveState != LiveState.video.rawValue
    }

    /// iPad windows use an in-place action even when narrow; phone rotation
    /// remains available outside the expanded layout.
    private var usesInPlaceFullscreen: Bool {
        usesExpandedLayout || windowContext?.window?.traitCollection.userInterfaceIdiom == .pad
    }

    /// Orientation policy remains phone-specific; layout does not depend on idiom.
    private var usesPhoneOrientationPolicy: Bool {
        windowContext?.window?.traitCollection.userInterfaceIdiom == .phone
    }

    /// 进入后台前是否处于 iPhone 横屏全屏（用于回前台时保留用户主动触发的横屏）
    @State private var wasLandscapeBeforeBackground: Bool = false

    /// 用户离开底部时显示“查看最新评论”按钮
    @State private var showJumpToLatest: Bool = false
    /// 触发跳到底部的请求
    @State private var scrollToBottomRequest: Bool = false

    @State private var isRoomSwitcherPresented = false
    @State private var isPortraitRoomSwitcherPresented = false
    @State private var portraitRoomSwitcherExpanded = false
    private static let roomSwitcherDetent = PresentationDetent.fraction(0.58)
    @State private var pendingPortraitRoom: LiveModel?
    @State private var selectedRoomSource: RoomSwitchSource
    @State private var switchingRoom: LiveModel?
    @State private var failedRoomID: String?
    @State private var roomSwitchFailureMessage: String?
    @State private var roomSwitchTask: Task<Void, Never>?
    @State private var roomSwitchRequestID: UUID?
    @State private var portraitSwitchRoomID: String?
    @State private var switcherHistoryRooms: [LiveModel]?
    @State private var roomSwitchToast: LiveModel?
    @State private var roomBannerID: String?
    @State private var lastBannerRoomID: String?
    @State private var roomBannerTask: Task<Void, Never>?
    @State private var switcherCategoryRooms: [LiveModel]
    @State private var loadMoreCategoryTask: Task<[LiveModel], Never>?
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?
    @Environment(\.presentToast) private var presentToast


    init(
        viewModel: RoomInfoViewModel,
        categoryRooms: [LiveModel] = [],
        canLoadMoreCategoryRooms: @escaping () -> Bool = { false },
        onLoadMoreCategoryRooms: (() async -> [LiveModel])? = nil,
        entryRoomSource: RoomSwitchSource? = nil,
        presentsOverRoomList: Bool = false,
        onRouteOnDemandRoom: ((LiveModel) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.categoryRooms = categoryRooms
        self.canLoadMoreCategoryRooms = canLoadMoreCategoryRooms
        self.onLoadMoreCategoryRooms = onLoadMoreCategoryRooms
        self.presentsOverRoomList = presentsOverRoomList
        self.onRouteOnDemandRoom = onRouteOnDemandRoom
        let orientation = PlatformHostBehavior.declaredOrientation(for: viewModel.currentRoom)
        _declaredOrientation = State(initialValue: orientation)
        _isVerticalLiveMode = State(initialValue: orientation == .portrait)
        _entryPhase = State(initialValue: orientation == nil ? .waitingForSize : .resolvedLayout)
        let enteredFromCategory = categoryRooms.contains(viewModel.currentRoom)
        _selectedRoomSource = State(initialValue: entryRoomSource ?? (enteredFromCategory ? .category : .favorite))
        _switcherCategoryRooms = State(initialValue: categoryRooms)
    }

    private var currentPlaybackError: Error? {
        viewModel.playError
    }

    private var playbackErrorTitle: String {
        if currentPlaybackError?.isAuthRequired == true {
            let platformName = LiveParseTools.getLivePlatformName(viewModel.currentRoom.liveType)
            return "播放失败-请登录\(platformName)账号"
        }
        return "播放失败"
    }

    private var playbackErrorMessage: String {
        if let error = currentPlaybackError {
            return error.liveParseMessage
        }
        return viewModel.playErrorMessage ?? "播放失败"
    }

    private var shouldShowPlatformLoginPrompt: Bool {
        currentPlaybackError?.showsLoginAction == true
    }

    private var currentPluginID: String? {
        SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType)?.pluginId
    }

    private var legacyPlayerGestureMask: GestureMask {
        #if canImport(KSPlayer)
        if #available(iOS 18.0, *) {
            return .subviews
        }
        #endif
        return .all
    }

    // MARK: - Body

    private func playerCanvas(in geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        let entryEligible = supportsEntryLoading && !isLandscape
        let entryActive = entryEligible && entryPhase != .finished
        let waitsForEntrySize = entryActive && entryPhase == .waitingForSize
        let entryExpansionRatio = entryActive ? entryPhase.expandingAspectRatio : nil
        let expandsEntryDetails = entryExpansionRatio != nil
        let playback = portraitPlayback
        let defersEntryError = waitsForEntrySize || expandsEntryDetails
        let showsEntryCover = entryActive && (!playback.hasFailed || defersEntryError)
        let showsFullEntryCover = waitsForEntrySize || (isVerticalLiveMode && !expandsEntryDetails)
        let entryReady = entryPhase == .resolvedLayout && (playback.hasProgress || entryVLCPlaybackStarted)
        let usesPortraitRoomSwitcher = usesPhoneOrientationPolicy && isVerticalLiveMode
            && !isFullscreen && !isLandscape
        let landscapeLayout = isFullscreen && isLandscape ? FullUILandscapePlayerLayout(
            geometry: geometry, window: windowContext?.window, direction: layoutDirection
        ) : nil
        let streamAvailable = viewModel.currentPlayURL != nil && currentPlaybackError == nil
            && viewModel.playErrorMessage == nil && viewModel.displayState != .streamerOffline
        let canShowRoomBanner = landscapeLayout != nil && !viewModel.isOnDemand
        let bannerCandidate = canShowRoomBanner && streamAvailable ? viewModel.currentRoom.id : nil
        // 竖屏直播模式下隐藏信息面板，让播放器占满全屏
        let showInfoPanel = !waitsForEntrySize && !isFullscreen
            && (!isVerticalLiveMode || expandsEntryDetails)
        let usesRoomSwitcherSheet = showInfoPanel || usesPortraitRoomSwitcher
        let allowsPlayerSwipe = scenePhase == .active && !playerModel.isLocked && !playerContentBlocksSwipe
            && !verticalLiveControlPopupPresented && !isRoomSwitcherPresented && !isPortraitRoomSwitcherPresented
            && pendingPortraitRoom == nil && authenticationRecoveryRequest == nil
        let allowsDrawerSwipe = allowsPlayerSwipe && isFullscreen && !isVerticalLiveMode && !viewModel.isOnDemand
            && !showsEntryCover && !playback.hasFailed && viewModel.displayState != .streamerOffline
        // Reuse the 400pt information panel only with at least a compact
        // 320pt playback surface beside it; regular traits alone are not a width guarantee.
        let showsSidePanel = showInfoPanel && usesExpandedLayout && isLandscape
            && geometry.size.width >= 720

        // 计算播放器宽度
        let playerWidth: CGFloat = {
            let baseWidth = geometry.size.width
            if isVerticalLiveMode {
                return baseWidth // 竖屏直播占满宽度
            } else if showsSidePanel {
                return baseWidth - 400 // iPad 横屏减去右侧信息栏
            } else {
                return baseWidth
            }
        }()

        // 扩展布局保留既有高度规则；紧凑布局随真实媒体比例调整。
        let playerHeight: CGFloat = {
            if let entryExpansionRatio {
                return playerWidth / entryExpansionRatio
            }
            if isVerticalLiveMode || isFullscreen {
                return geometry.size.height // 竖屏直播占满高度
            } else if usesExpandedLayout {
                // iPad 保持原逻辑
                if showInfoPanel {
                    if showsSidePanel {
                        return geometry.size.height // 展开侧栏时占满可用高度
                    } else {
                        return playerWidth / 16 * 9 // iPad 竖屏保持 16:9
                    }
                } else {
                    return geometry.size.height // 全屏模式占满高度
                }
            } else {
                return playerWidth / videoAspectRatio
            }
        }()

        let entrySizeHandler: (@MainActor (CGSize) -> Void)?
        if waitsForEntrySize {
            entrySizeHandler = resolveEntryVideoSize
        } else {
            entrySizeHandler = nil
        }
        let playerSurface = PlayerContentView(
            playerCoordinator: playerCoordinator,
            playerModel: playerModel,
            isVerticalLiveMode: $isVerticalLiveMode,
            videoAspectRatio: $videoAspectRatio,
            showsPortraitRoomSwitcher: usesPortraitRoomSwitcher,
            keepsPortraitLayoutWhileDetecting: portraitSwitchRoomID == viewModel.currentRoom.id,
            declaredOrientation: declaredOrientation,
            pendingLoadingRoom: portraitSwitchRoomID == nil ? switchingRoom : nil,
            isCoveredByEntryLoading: showsEntryCover,
            onEntryVideoSize: entrySizeHandler,
            entryVLCPlaybackStarted: entryActive ? $entryVLCPlaybackStarted : nil,
            blocksPageSwipe: $playerContentBlocksSwipe
        )
        let fittedPlayer = playerSurface
            .id("stable_player")
            .environment(viewModel)
            .frame(
                width: playerWidth,
                height: playerHeight
            )
            .overlay(alignment: usesPortraitRoomSwitcher ? .top : .center) {
                if showInfoPanel || usesPortraitRoomSwitcher, let roomSwitchToast {
                    roomSwitchConfirmation(for: roomSwitchToast)
                        .padding(.top, usesPortraitRoomSwitcher
                            ? FullUIPlayerChrome.inset + FullUIPlayerChrome.controlSize + 12 : 0)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 新画面手势桥接未启用的系统或内核，保留原有播放器手势处理。
            .simultaneousGesture(
                DragGesture(minimumDistance: 1).onChanged { _ in },
                including: legacyPlayerGestureMask
            )
            .allowsHitTesting(!showsEntryCover)
            .accessibilityHidden(showsEntryCover)

        let page = ZStack(alignment: .topLeading) {
            // 模糊背景
            backgroundView

            // 主播已下播视图
            if !defersEntryError && viewModel.displayState == .streamerOffline {
                VStack(spacing: 20) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("主播已下播")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(viewModel.currentRoom.userName)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Button("返回") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(100)
            }
            // 错误视图 - 当播放出错时显示
            else if !defersEntryError && playback.hasFailed {
                ErrorView(
                    title: playbackErrorTitle,
                    message: playbackErrorMessage,
                    errorCode: nil,
                    detailMessage: currentPlaybackError?.liveParseDetail,
                    curlCommand: currentPlaybackError?.liveParseCurl,
                    showDismiss: true,
                    showRetry: true,
                    showLoginButton: shouldShowPlatformLoginPrompt,
                    showDetailButton: currentPlaybackError?.liveParseDetail?.isEmpty == false,
                    onDismiss: {
                        dismiss()
                    },
                    onRetry: {
                        Task {
                            await viewModel.loadPlayURL(force: true)
                        }
                    },
                    onLogin: shouldShowPlatformLoginPrompt ? {
                        authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                            pluginIDs: SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType)
                                .map { [$0.pluginId] } ?? []
                        )
                    } : nil
                )
                .zIndex(100)
            } else {
                fittedPlayer

                // 信息面板 - 根据布局动态显示/隐藏
                if showInfoPanel {
                    if showsSidePanel {
                        // iPad 横屏：右侧面板
                        informationArea
                        .frame(width: 400)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .offset(x: geometry.size.width - 400, y: 0)
                    } else {
                        // 竖屏：底部面板
                        informationArea
                        .frame(maxWidth: .infinity)
                        .frame(height: max(0, geometry.size.height - playerHeight))
                        .offset(x: 0, y: playerHeight)
                        .transition(expandsEntryDetails ? entryInformationTransition : .identity)
                        .allowsHitTesting(!expandsEntryDetails)
                        .accessibilityHidden(expandsEntryDetails)
                    }
                }
            }
        }

        let pageWithEntryCover = page.overlay(alignment: .topLeading) {
            if showsEntryCover {
                entryLoadingCover(geometry: geometry, playerHeight: playerHeight, fullscreen: showsFullEntryCover)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsEntryCover {
                FullUIPlayerBackButton { dismiss() }
                    .padding(FullUIPlayerChrome.inset)
                    .transition(.opacity)
            }
        }

        let openDrawerSwipe: ((CGPoint, UIWindow) -> PlayerPanAction?)? = if allowsDrawerSwipe {
            { start, window in drawerSwipeAction(start: start, in: window, geometry: geometry) }
        } else {
            nil
        }
        let interactivePage = pageWithEntryCover.modifier(PortraitRoomPager(
            enabled: allowsPlayerSwipe && isVerticalLiveMode && !isLandscape && !isFullscreen
                && !viewModel.isOnDemand && !defersEntryError && !playback.hasFailed,
            openDrawerSwipe: openDrawerSwipe,
            viewportWidth: geometry.size.width,
            viewportHeight: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom,
            availableHeight: geometry.size.height,
            playback: playback,
            loadingDiagnostics: PlayerLoadingDiagnostics(viewModel: viewModel, layer: playerCoordinator.playerLayer),
            currentPlayback: { portraitPlayback },
            source: selectedRoomSource,
            adjacentRoom: adjacentPortraitRoom,
            canLoadMore: canLoadMoreCategoryRooms,
            loadNextRoom: loadNextPortraitRoom,
            switchRoom: switchPortraitRoom,
            reportStartupFailure: reportPortraitRoomStartupFailure,
            showBoundary: showPortraitRoomBoundary
        ))
        .accessibilityHidden(isRoomSwitcherPresented || isPortraitRoomSwitcherPresented)
        .overlay {
            let showsPortraitBackdrop = isPortraitRoomSwitcherPresented
                && !portraitRoomSwitcherExpanded
            roomSwitcherOverlay(
                showsPortraitBackdrop: showsPortraitBackdrop,
                showsDrawer: !showsPortraitBackdrop && isRoomSwitcherPresented && !showInfoPanel && !usesPortraitRoomSwitcher,
                availableSize: geometry.size,
                trailingSafeArea: geometry.safeAreaInsets.trailing
            )
        }
        .modifier(PlayerBackSwipe(
            enabled: allowsPlayerSwipe,
            width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
            exitsFullscreen: isFullscreen,
            revealsRoomList: presentsOverRoomList && !isFullscreen,
            onReturn: finishSwipeReturn
        ))

        return interactivePage.environment(
            \.roomSwitcherPresentation,
            usesRoomSwitcherSheet ? $isPortraitRoomSwitcherPresented
                : $isRoomSwitcherPresented.animation(roomSwitcherDrawerAnimation)
        )
        .environment(\.fullUILandscapePlayerLayout, landscapeLayout)
        .environment(\.requestPlayerOrientation, requestPhoneOrientation)
        .environment(\.presentsPlayerPanelsAsSheets, !isLandscape)
        .environment(\.fullUIPlayerShowsRoomBanner, roomBannerID == viewModel.currentRoom.id)
        .defersSystemGestures(on: landscapeLayout?.defersSystemGestures == true && streamAvailable
            && !isRoomSwitcherPresented ? .all : [])
        .task(id: waitsForEntrySize) {
            guard waitsForEntrySize else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard !Task.isCancelled else { return }
            expandEntryDetails()
        }
        .onChange(of: entryEligible, initial: true) { _, eligible in
            if !eligible { entryPhase = .finished }
        }
        .onChange(of: playback.hasFailed, initial: true) { _, failed in
            guard entryActive, failed else { return }
            if waitsForEntrySize {
                expandEntryDetails()
            } else if entryPhase == .resolvedLayout {
                entryPhase = .finished
            }
        }
        .onChange(of: entryReady) { _, ready in
            if ready {
                withAnimation(PlayerLoadingScreen.fade) { entryPhase = .finished }
            }
        }
        .onChange(of: bannerCandidate, initial: true) { _, roomID in
            if let roomID, roomID != lastBannerRoomID {
                showRoomBanner(for: roomID)
            } else if !canShowRoomBanner || (roomID == nil && lastBannerRoomID != viewModel.currentRoom.id) {
                cancelRoomBanner()
            }
        }
        .onChange(of: usesRoomSwitcherSheet) { _, usesSheet in
            if usesSheet {
                isRoomSwitcherPresented = false
            } else {
                isPortraitRoomSwitcherPresented = false
            }
        }
        .onChange(of: isLandscape) { _, _ in closeFullscreenRoomSwitchers() }
    }

    var body: some View {
        let canvas = GeometryReader { geometry in playerCanvas(in: geometry) }
        let presentation = canvas.onChange(of: windowContext?.windowScene?.effectiveGeometry.interfaceOrientation) { previous, current in
            if let previous, let current, previous != .unknown, current != .unknown {
                closeFullscreenRoomSwitchers()
            }
        }
        .roomPlayerSheet(
            isPresented: $isPortraitRoomSwitcherPresented, initialDetent: Self.roomSwitcherDetent,
            selection: Binding(get: { portraitRoomSwitcherExpanded ? .large : Self.roomSwitcherDetent },
                               set: { portraitRoomSwitcherExpanded = $0 == .large }),
            onDismiss: switchToPendingPortraitRoom
        ) {
            portraitRoomSwitcherSheet
        }
        .environment(\.isIPadFullscreen, $isIPadFullscreen)
        .environment(\.fullUIPlayerIsFullscreen, isFullscreen)
        .environment(\.fullUIPlayerUsesExpandedLayout, usesExpandedLayout)
        .environment(\.fullUIPlayerUsesInPlaceFullscreen, usesInPlaceFullscreen)
        .onChange(of: usesInPlaceFullscreen) { _, usesInPlace in
            if !usesInPlace { isIPadFullscreen = false }
        }
        .onChange(of: usesExpandedLayout) { _, isExpanded in
            // Entering an expanded phone layout restores details. Fullscreen
            // choices within that layout and in iPad windows remain in place.
            if isExpanded, usesPhoneOrientationPolicy {
                isIPadFullscreen = false
            }
        }
        .onChange(of: verticalSizeClass) { oldValue, newValue in
            if !usesInPlaceFullscreen, oldValue == .compact, newValue == .regular {
                isIPadFullscreen = false
            }
        }
        .onChange(of: isFullscreen || isVerticalLiveMode) { _, usesOverlay in
            if !usesOverlay { isRoomSwitcherPresented = false }
        }
        .environment(\.verticalLiveControlsVisible, $verticalLiveControlsVisible)
        .environment(\.verticalLiveControlPopupPresented, $verticalLiveControlPopupPresented)
        .navigationBarBackButtonHidden()
        .interactivePopGestureEnabled(false, edgeOnly: true)

        let observedPlayback = presentation.onChange(of: viewModel.currentRoom.id) { _, _ in
            let orientation = PlatformHostBehavior.declaredOrientation(for: viewModel.currentRoom)
            if orientation != declaredOrientation {
                declaredOrientation = orientation
                isVerticalLiveMode = orientation == .portrait
                applyEntryOrientation()
            } else if orientation != nil {
                applyEntryOrientation()
            }
            verticalLiveControlsVisible = true
            verticalLiveControlPopupPresented = false
            showJumpToLatest = false
        }
        .onChange(of: portraitPlayback) { _, playback in
            if portraitSwitchRoomID == playback.room.id, playback.hasProgress || playback.hasFailed {
                portraitSwitchRoomID = nil
            }
        }
        .onChange(of: selectedRoomSource) { _, source in
            // Recording each switch changes MRU order. Keep the list and swipes on
            // the same sequence until the user selects a different source.
            switcherHistoryRooms = source == .history ? historyModel.watchList : nil
        }
        .task(id: roomSwitchToast) {
            guard roomSwitchToast != nil else { return }
            try? await Task.sleep(for: .milliseconds(1850))
            guard !Task.isCancelled else { return }
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22)) {
                roomSwitchToast = nil
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            Logger.debug("[PlayerFlow] Detail scenePhase -> \(newPhase), roomId=\(viewModel.currentRoom.roomId)", category: .player)
            switch newPhase {
            case .active:
                viewModel.resumeDanmuUpdatesIfNeeded()
                // iPhone：进后台前是横屏全屏（用户主动触发），回前台时保留横屏，
                // 否则会被设备姿态/系统重新查询 supportedInterfaceOrientations 扳回竖屏。
                if usesPhoneOrientationPolicy && wasLandscapeBeforeBackground {
                    wasLandscapeBeforeBackground = false
                    reassertLandscapeOrientation()
                }
            case .background:
                viewModel.pauseDanmuUpdatesForBackground()
                // 只在「从活跃态离开」时记录:回前台路径是 background→inactive→active,
                // 若在 inactive 也记录会被回程的 inactive 用已翻回竖屏的值覆盖,导致保留失效。
                if oldPhase == .active && usesPhoneOrientationPolicy {
                    wasLandscapeBeforeBackground = isIPhoneLandscape
                }
            case .inactive:
                // 系统弹窗会短暂进入 inactive；保留横屏记录，但不要取消弹幕翻译。
                if oldPhase == .active && usesPhoneOrientationPolicy {
                    wasLandscapeBeforeBackground = isIPhoneLandscape
                }
            @unknown default:
                break
            }
        }
        .onChange(of: windowContext?.window, initial: true) { _, window in
            guard window?.traitCollection.userInterfaceIdiom == .phone else { return }
            applyEntryOrientation()
        }
        .onChange(of: isVerticalLiveMode) { _, isVertical in
            // 竖向直播锁定竖屏，切回普通画幅时恢复自由旋转。
            if usesPhoneOrientationPolicy, declaredOrientation == nil {
                KSOptions.supportedInterfaceOrientations = isVertical ? .portrait : .allButUpsideDown
                if let rootVC = windowContext?.hostViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            NowPlayingManager.updatePlaybackState(
                isPlaying: isPlaying,
                surfaceID: playbackSession.surfaceID
            )
        }
        .onChange(of: playerCoordinator.state) { _, _ in
            playbackSession.attach(playerLayer: playerCoordinator.playerLayer)
        }
        .onChange(of: playbackSession.owns(.pictureInPicture)) {
            viewModel.updateAutoPictureInPicture()
        }
        .onChange(of: categoryRooms) { _, newValue in
            switcherCategoryRooms = newValue
        }

        observedPlayback.task {
            await viewModel.loadPlayURL()
        }
        .onAppear {
            if selectedRoomSource == .history, switcherHistoryRooms == nil {
                switcherHistoryRooms = historyModel.watchList
            }
            playbackSession.activate()
            playbackSession.attach(playerLayer: playerCoordinator.playerLayer)
            viewModel.playbackSurfaceID = playbackSession.surfaceID
            // 添加观看历史记录
            historyModel.addHistory(room: viewModel.currentRoom)
            // 设置 Now Playing 信息(占位;真正稳定的写入在 RoomInfoViewModel 的 readyToPlay 回调里补写)。
            // 远程控制命令(播放/暂停等)由 KSPlayer 的 registerRemoteControll 统一注册,此处不再重复注册。
            NowPlayingManager.update(
                room: viewModel.currentRoom,
                isPlaying: false,
                surfaceID: playbackSession.surfaceID
            )
        }
        .onDisappear {
            transientOrientationRequest = nil
            pendingPortraitRoom = nil
            roomSwitchTask?.cancel()
            roomSwitchRequestID = nil
            portraitSwitchRoomID = nil
            loadMoreCategoryTask?.cancel()
            cancelRoomBanner()
            viewModel.subtitlePlayback.stop()
            viewModel.endPlaybackDiagnostics()
            SupportDiagnosticsService.shared.recordAction(
                .closedRoom,
                context: SupportDiagnosticActionContext.room(
                    viewModel.currentRoom,
                    additional: ["playerKernel": String(viewModel.selectedPlayerKernel.rawValue)]
                )
            )
            Logger.debug("[PlayerFlow] Detail onDisappear, roomId=\(viewModel.currentRoom.roomId), kernel=\(viewModel.selectedPlayerKernel.rawValue)", category: .player)
            viewModel.disconnectSocket()
            // 清除 Now Playing 信息(远程控制命令由 KSPlayer 在 stop() 时自行注销)
            NowPlayingManager.clear(surfaceID: playbackSession.surfaceID)
            // 退出时沿用 representable 的拆除路径，立即清空 layer 并避免重复 stop。
            playerCoordinator.resetPlayer()
            playbackSession.invalidate()
            viewModel.playbackSurfaceID = nil
            // iPhone 返回时强制竖屏
            if usesPhoneOrientationPolicy {
                // 设置支持的方向为竖屏
                KSOptions.supportedInterfaceOrientations = .portrait

                guard let windowScene = windowContext?.windowScene else {
                    return
                }

                // 先通知 ViewController 刷新支持的方向
                if let rootVC = windowContext?.hostViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                guard windowScene.interfaceOrientation != .portrait else { return }
                DispatchQueue.main.async {
                    let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                        interfaceOrientations: .portrait
                    )
                    // UIKit 可能在后台调用失败回调；日志闭包不继承 MainActor。
                    windowScene.requestGeometryUpdate(geometryPreferences) { @Sendable error in
                        Logger.error("[PlayerFlow] 强制竖屏失败: \(error.localizedDescription)", category: .player)
                    }
                }
            }
        }
        .roomPlayerSheet(item: $authenticationRecoveryRequest) { request in
            NavigationStack {
                PlatformAccountLoginView(recoveryPluginIDs: request.pluginIDs)
            }
        }
        // 画质面板点击「登录后可用」档位：复用登录恢复 sheet
        .onChange(of: viewModel.pendingLoginRequest?.id) { _, _ in
            guard let request = viewModel.pendingLoginRequest else { return }
            viewModel.pendingLoginRequest = nil
            authenticationRecoveryRequest = request
        }
        .onChange(of: viewModel.lockedQualityNotice) { _, notice in
            guard let notice else { return }
            viewModel.lockedQualityNotice = nil
            presentToast(ToastValue(icon: Image(systemName: "lock.fill"), message: notice))
        }
        // 当前平台登录状态变化后重新取流，让被锁定的画质解锁
        .onReceive(
            NotificationCenter.default.publisher(for: .platformSessionMetadataDidChange)
                .receive(on: RunLoop.main)
                .compactMap { $0.object as? String }
        ) { pluginId in
            guard pluginId == currentPluginID else { return }
            viewModel.refreshPlayback()
        }
        .modifier(RoomPlayerSheetHost(viewModel: viewModel))
    }

    private var entryInformationTransition: AnyTransition {
        accessibilityReduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    @ViewBuilder
    private func entryLoadingCover(geometry: GeometryProxy, playerHeight: CGFloat, fullscreen: Bool) -> some View {
        let diagnostics = PlayerLoadingDiagnostics(viewModel: viewModel, layer: playerCoordinator.playerLayer)
        if accessibilityReduceMotion {
            ZStack(alignment: .topLeading) {
                if fullscreen {
                    entryLoadingViewport(geometry, playerHeight: playerHeight, diagnostics: diagnostics, progress: 0)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    entryLoadingViewport(geometry, playerHeight: playerHeight, diagnostics: diagnostics, progress: 1)
                        .transition(.opacity)
                }
            }
        } else {
            entryLoadingViewport(geometry, playerHeight: playerHeight, diagnostics: diagnostics, progress: fullscreen ? 0 : 1)
        }
    }

    private func entryLoadingViewport(
        _ geometry: GeometryProxy, playerHeight: CGFloat, diagnostics: PlayerLoadingDiagnostics, progress: CGFloat
    ) -> some View {
        PlayerEntryLoadingViewport(
            room: viewModel.currentRoom, diagnostics: diagnostics, size: geometry.size,
            safeArea: geometry.safeAreaInsets, playerHeight: playerHeight, detailProgress: progress
        )
    }

    private func resolveEntryVideoSize(_ size: CGSize) {
        guard entryPhase == .waitingForSize, supportsEntryLoading else { return }
        if portraitPlayback.hasFailed {
            expandEntryDetails()
        } else if size.width < size.height {
            isVerticalLiveMode = true
            entryPhase = .resolvedLayout
        } else {
            expandEntryDetails(aspectRatio: size.width / size.height)
        }
    }

    private func expandEntryDetails(aspectRatio: CGFloat = 16.0 / 9.0) {
        guard entryPhase == .waitingForSize, supportsEntryLoading else { return }
        let animation: Animation = accessibilityReduceMotion ? PlayerLoadingScreen.fade : .spring(
            response: PortraitPlayerSpring.response, dampingFraction: PortraitPlayerSpring.dampingRatio
        ).logicallyComplete(after: 0.4)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            entryPhase = .expandingDetails(aspectRatio: aspectRatio)
        } completion: {
            guard entryPhase.expandingAspectRatio != nil else { return }
            entryPhase = portraitPlayback.hasFailed ? .finished : .resolvedLayout
        }
    }

    // MARK: - Orientation

    private func applyEntryOrientation() {
        guard usesPhoneOrientationPolicy else { return }
        transientOrientationRequest = nil
        let mask: UIInterfaceOrientationMask = switch declaredOrientation {
        case .landscape: .landscape
        case .portrait: .portrait
        case nil: isVerticalLiveMode ? .portrait : .allButUpsideDown
        }
        KSOptions.supportedInterfaceOrientations = mask
        windowContext?.hostViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if declaredOrientation != nil {
            windowContext?.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            windowContext?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }

    /// iPhone 回前台后保留横屏全屏:临时锁定横屏发起几何更新,完成后恢复自由旋转,
    /// 这样既保留用户主动横屏,又允许之后旋转/双击切回竖屏。
    private func reassertLandscapeOrientation() {
        requestPhoneOrientation(.landscape)
    }

    private func requestPhoneOrientation(_ orientation: UIInterfaceOrientationMask) {
        guard usesPhoneOrientationPolicy else { return }
        KSOptions.supportedInterfaceOrientations = orientation
        guard let windowScene = windowContext?.windowScene else { return }
        let requestID = UUID()
        transientOrientationRequest = requestID
        // 先通知 ViewController 刷新支持的方向
        if let rootVC = windowContext?.hostViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        // 延迟到下一个 run loop,确保 VC 已刷新支持的方向
        DispatchQueue.main.async {
            guard transientOrientationRequest == requestID else { return }
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: orientation
            )
            windowScene.requestGeometryUpdate(geometryPreferences) { @Sendable error in
                Logger.warning("[PlayerFlow] 方向更新失败: \(error.localizedDescription)", category: .player)
            }
            // 旋转完成后恢复自由旋转,允许用户后续旋转/双击切回竖屏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard transientOrientationRequest == requestID else { return }
                transientOrientationRequest = nil
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                if let rootVC = windowContext?.hostViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        BlurredBackgroundView(imageURL: viewModel.currentRoom.userHeadImg)
            .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Layouts

    /// 全屏播放器布局（iPhone 横屏 或 iPad 全屏）
    private var fullscreenPlayerLayout: some View {
        PlayerContentView(
            playerCoordinator: playerCoordinator,
            playerModel: playerModel,
            isVerticalLiveMode: $isVerticalLiveMode,
            videoAspectRatio: $videoAspectRatio
        )
            .id("stable_player") // 关键：所有布局使用相同的 id
            .environment(viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }

    /// iPad 横屏布局（左右分栏）
    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // 左侧：播放器
            PlayerContentView(
                playerCoordinator: playerCoordinator,
                playerModel: playerModel,
                isVerticalLiveMode: $isVerticalLiveMode,
                videoAspectRatio: $videoAspectRatio
            )
                .id("stable_player") // 关键：所有布局使用相同的 id
                .environment(viewModel)
                .frame(maxWidth: .infinity)

            informationArea
                .frame(width: 400)
        }
    }

    /// 竖屏布局（上下排列）
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // 播放器容器
            PlayerContentView(
                playerCoordinator: playerCoordinator,
                playerModel: playerModel,
                isVerticalLiveMode: $isVerticalLiveMode,
                videoAspectRatio: $videoAspectRatio
            )
                .id("stable_player") // 关键：所有布局使用相同的 id
                .environment(viewModel)
                .frame(maxWidth: .infinity)

            informationArea
        }
    }

    // MARK: - 播放器下方信息区

    private var informationArea: some View {
        VStack(spacing: 0) {
            StreamerInfoView()
                .modifier(RoomHeaderSheetVisibility())
                .padding(.bottom, 20)

            RoomActionDock(
                room: viewModel.currentRoom,
                onOpenSwitcher: { isPortraitRoomSwitcherPresented = true },
                onClearChat: clearChat,
                onJumpToLatestChat: showJumpToLatest ? { scrollToBottomRequest = true } : nil
            )
            .modifier(RoomHeaderSheetVisibility())
            chatListView.id(viewModel.currentRoom.id)
        }
        .environment(viewModel)
        .environment(\.colorScheme, .dark)
    }

    private var chatListView: some View {
        ChatTableView(
            messages: viewModel.danmuMessages,
            topSpacing: 8,
            showJumpToLatest: $showJumpToLatest,
            scrollToBottomRequest: $scrollToBottomRequest
        )
    }

    private func roomSwitchConfirmation(for room: LiveModel) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .foregroundStyle(FullUIPlayerDetailChrome.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text("已切换到 \(room.userName.orDash)")
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, FullUIPlayerDetailChrome.inset + FullUIPlayerChrome.controlSize)
        .allowsHitTesting(false)
    }

    private var roomSwitcherContent: RoomSwitcherListContent {
        RoomSwitcherListContent(
            currentRoom: viewModel.currentRoom,
            favorites: favoriteModel.roomList,
            history: switcherHistoryRooms ?? historyModel.watchList,
            category: switcherCategoryRooms,
            source: selectedRoomSource,
            switchingRoomID: switchingRoom?.id,
            failedRoomID: failedRoomID,
            failureMessage: roomSwitchFailureMessage,
            canLoadMoreCategory: canLoadMoreCategoryRooms,
            isLoadingMoreCategory: loadMoreCategoryTask != nil,
            onLoadMoreCategory: loadMoreSwitcherCategoryRooms
        )
    }

    private var portraitPlayback: PortraitRoomPager.Playback {
        .init(
            room: viewModel.currentRoom,
            hasProgress: viewModel.hasPlaybackProgress(for: playerCoordinator.playerLayer?.url),
            hasFailed: viewModel.playError != nil || viewModel.playErrorMessage != nil
                || viewModel.displayState == .streamerOffline
        )
    }

    private func adjacentPortraitRoom(
        _ direction: RoomSwitchCandidates.Direction, to room: LiveModel
    ) -> LiveModel? {
        RoomSwitchCandidates.adjacentRoom(
            direction, for: selectedRoomSource, currentRoom: room,
            favorites: favoriteModel.roomList,
            history: switcherHistoryRooms ?? historyModel.watchList,
            category: switcherCategoryRooms,
            includesOnDemand: true
        )
    }

    private func loadNextPortraitRoom(after room: LiveModel) async -> LiveModel? {
        let rooms = await loadMoreSwitcherCategoryRooms()
        guard !Task.isCancelled, selectedRoomSource == .category else { return nil }
        return RoomSwitchCandidates.adjacentRoom(
            .next, for: .category, currentRoom: room,
            favorites: [], history: [], category: rooms
        )
    }

    private func showPortraitRoomBoundary(_ direction: RoomSwitchCandidates.Direction) {
        presentToast(ToastValue(
            icon: Image(systemName: "info.circle"),
            message: direction == .previous ? "已经是第一个" : "已经是最后一个"
        ))
    }

    private func switchPortraitRoom(
        _ room: LiveModel, showsConfirmation: Bool, completion: @escaping (Bool) -> Void
    ) {
        switchRoom(room, showsConfirmation: showsConfirmation, portraitCompletion: completion)
    }

    private func reportPortraitRoomStartupFailure(_ room: LiveModel) {
        let message = viewModel.playErrorMessage ?? viewModel.playError?.localizedDescription ?? "主播已下播"
        failedRoomID = room.id
        roomSwitchFailureMessage = message
        presentToast(ToastValue(icon: Image(systemName: "exclamationmark.circle"), message: message))
    }

    private var portraitRoomSwitcherSheet: some View {
        RoomSwitcherPanel(
            content: roomSwitcherContent,
            selectedSource: $selectedRoomSource,
            isSheet: true,
            onSelect: selectPortraitRoom,
            onDismiss: { isPortraitRoomSwitcherPresented = false }
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { isPortraitRoomSwitcherPresented = false }
        // Route taps on the exposed portion of the player to the dismiss backdrop.
        .presentationBackgroundInteraction(.enabled(upThrough: Self.roomSwitcherDetent))
    }

    private func selectPortraitRoom(_ room: LiveModel) {
        guard isPortraitRoomSwitcherPresented else { return }
        pendingPortraitRoom = room
        isPortraitRoomSwitcherPresented = false
    }

    private func switchToPendingPortraitRoom() {
        portraitRoomSwitcherExpanded = false
        guard let room = pendingPortraitRoom else { return }
        pendingPortraitRoom = nil
        switchRoom(room, showsConfirmation: true)
    }

    private func roomSwitcherBackdrop(onTap: @escaping () -> Void) -> some View {
        Color.black.opacity(0.46)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    private func roomSwitcherOverlay(
        showsPortraitBackdrop: Bool, showsDrawer: Bool, availableSize: CGSize, trailingSafeArea: CGFloat
    ) -> some View {
        // 保留覆盖层容器，让遮罩和抽屉分别执行插入、移除过渡。
        ZStack(alignment: .trailing) {
            if showsPortraitBackdrop {
                roomSwitcherBackdrop { isPortraitRoomSwitcherPresented = false }
            } else if showsDrawer {
                roomSwitcherBackdrop(onTap: dismissRoomSwitcher)
            }

            if showsDrawer {
                roomSwitcherDrawer(width: roomSwitcherPanelWidth(for: availableSize), trailingSafeArea: trailingSafeArea)
                    .transition(accessibilityReduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func roomSwitcherDrawer(width: CGFloat, trailingSafeArea: CGFloat) -> some View {
        RoomSwitcherPanel(
            content: roomSwitcherContent,
            selectedSource: $selectedRoomSource,
            onSelect: selectDrawerRoom,
            onDismiss: dismissRoomSwitcher
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismissRoomSwitcher)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background { BlurredBackgroundView(imageURL: viewModel.currentRoom.userHeadImg) }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 26,
                bottomLeadingRadius: 26
            )
        )
        .shadow(color: .black.opacity(0.34), radius: 24, x: -10)
        .environment(\.colorScheme, .dark)
        .modifier(RoomSwitcherDrawerSwipe(
            width: width, trailingSafeArea: trailingSafeArea, onDismiss: dismissRoomSwitcher
        ))
    }

    private var roomSwitcherDrawerAnimation: Animation {
        accessibilityReduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.32)
    }

    private func roomSwitcherPanelWidth(for size: CGSize) -> CGFloat {
        if horizontalSizeClass == .regular {
            return min(480, max(400, size.width * 0.46))
        }
        if size.width > size.height {
            return min(420, max(320, size.width * 0.48))
        }
        return max(300, size.width - 16)
    }

    // MARK: - Helper Methods

    private func clearChat() {
        withAnimation {
            viewModel.danmuMessages.removeAll()
            showJumpToLatest = false
        }
    }

    private func finishSwipeReturn() {
        if isFullscreen {
            closeFullscreenRoomSwitchers()
            isIPadFullscreen = false
            if !usesInPlaceFullscreen {
                requestPhoneOrientation(.portrait)
            }
            return
        }

        dismiss()
    }

    private func drawerSwipeAction(start: CGPoint, in window: UIWindow, geometry: GeometryProxy) -> PlayerPanAction? {
        let isLTR = layoutDirection == .leftToRight
        let fromLeading = isLTR ? start.x - window.bounds.minX : window.bounds.maxX - start.x
        guard GeneralSettingModel().enablePlayerGesture,
              fromLeading >= geometry.safeAreaInsets.leading + geometry.size.width * 0.55 else { return nil }
        return PlayerPanAction(
            kind: .openDrawer, axis: .horizontal, sign: isLTR ? -1 : 1,
            begin: { _ in }, update: { _ in },
            canEnd: { abs($0.x) > abs($0.y) * 1.5 },
            end: { travel, _ in
                guard travel >= 70 else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(roomSwitcherDrawerAnimation) { isRoomSwitcherPresented = true }
            },
            cancel: {}
        )
    }

    private func dismissRoomSwitcher() {
        withAnimation(roomSwitcherDrawerAnimation) {
            isRoomSwitcherPresented = false
        }
    }

    private func closeFullscreenRoomSwitchers() {
        isRoomSwitcherPresented = false
        isPortraitRoomSwitcherPresented = false
    }

    private func selectDrawerRoom(_ room: LiveModel) {
        guard isRoomSwitcherPresented else { return }
        dismissRoomSwitcher()
        switchRoom(room, showsConfirmation: false)
    }

    private func switchRoom(
        _ room: LiveModel,
        showsConfirmation: Bool,
        portraitCompletion: ((Bool) -> Void)? = nil
    ) {
        if portraitCompletion == nil, room == viewModel.currentRoom || switchingRoom == room { return }
        if let onRouteOnDemandRoom, VodRouting.declaresVod(room) || ShortDramaRouting.isShortDrama(room) {
            roomSwitchTask?.cancel()
            portraitCompletion?(true)
            onRouteOnDemandRoom(room)
            return
        }
        // Subsequent room selections are owned by the existing switch loading paths.
        entryPhase = .finished
        let previousTask = roomSwitchTask
        previousTask?.cancel()
        cancelRoomBanner()
        let requestID = UUID()
        roomSwitchRequestID = requestID
        switchingRoom = room
        portraitSwitchRoomID = portraitCompletion == nil ? nil : room.id
        failedRoomID = nil
        roomSwitchFailureMessage = nil
        let requestRoomID = room.id

        roomSwitchTask = Task { @MainActor in
            // The active resolver must unwind before a newer swipe may issue a plugin request.
            await previousTask?.value
            guard !Task.isCancelled, roomSwitchRequestID == requestID else { return }
            defer {
                if roomSwitchRequestID == requestID { roomSwitchTask = nil }
            }
            do {
                if room != viewModel.currentRoom {
                    try await viewModel.switchRoom(to: room)
                    try Task.checkCancellation()

                    historyModel.addHistory(room: room)
                    NowPlayingManager.update(
                        room: room,
                        isPlaying: false,
                        surfaceID: playbackSession.surfaceID
                    )
                }
                guard roomSwitchRequestID == requestID else { return }

                switchingRoom = nil
                if portraitSwitchRoomID == room.id, portraitPlayback.hasProgress || portraitPlayback.hasFailed {
                    portraitSwitchRoomID = nil
                }
                if showsConfirmation {
                    withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22)) {
                        roomSwitchToast = room
                    }
                    AccessibilityNotification.Announcement("已切换到 \(room.userName.orDash)").post()
                }
                portraitCompletion?(true)
            } catch is CancellationError {
                guard !Task.isCancelled, roomSwitchRequestID == requestID else { return }
                switchingRoom = nil
                portraitSwitchRoomID = nil
                portraitCompletion?(false)
            } catch {
                guard !Task.isCancelled, roomSwitchRequestID == requestID else { return }
                switchingRoom = nil
                portraitSwitchRoomID = nil
                failedRoomID = requestRoomID
                roomSwitchFailureMessage = error.localizedDescription
                if portraitCompletion != nil {
                    presentToast(ToastValue(icon: Image(systemName: "exclamationmark.circle"), message: error.localizedDescription))
                }
                portraitCompletion?(false)
            }
        }
    }

    private func showRoomBanner(for roomID: String) {
        cancelRoomBanner()
        lastBannerRoomID = roomID
        roomBannerID = roomID
        roomBannerTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled, roomBannerID == roomID else { return }
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22)) {
                roomBannerID = nil
            }
            roomBannerTask = nil
        }
    }

    private func cancelRoomBanner() {
        roomBannerTask?.cancel()
        roomBannerTask = nil
        roomBannerID = nil
    }

    @MainActor
    private func loadMoreSwitcherCategoryRooms() async -> [LiveModel] {
        if let loadMoreCategoryTask {
            return await loadMoreCategoryTask.value
        }
        guard let onLoadMoreCategoryRooms else { return switcherCategoryRooms }
        let task = Task { @MainActor in
            let rooms = await onLoadMoreCategoryRooms()
            guard !Task.isCancelled else { return switcherCategoryRooms }
            switcherCategoryRooms = rooms
            return rooms
        }
        loadMoreCategoryTask = task
        defer { loadMoreCategoryTask = nil }
        return await task.value
    }
}

// MARK: - iPad Fullscreen Support

/// iPad 全屏状态的 Environment Key
private struct IPadFullscreenEnvironmentKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var isIPadFullscreen: Binding<Bool> {
        get { self[IPadFullscreenEnvironmentKey.self] }
        set { self[IPadFullscreenEnvironmentKey.self] = newValue }
    }
}

// MARK: - Room Switcher Presentation

private struct RoomSwitcherPresentationEnvironmentKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var roomSwitcherPresentation: Binding<Bool> {
        get { self[RoomSwitcherPresentationEnvironmentKey.self] }
        set { self[RoomSwitcherPresentationEnvironmentKey.self] = newValue }
    }
}

// MARK: - Vertical Live Mode Environment Key

/// 竖屏直播模式的 Environment Key
struct VerticalLiveModeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct VerticalLiveControlsVisibleKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

private struct VerticalLiveControlPopupPresentedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var verticalLiveControlsVisible: Binding<Bool> {
        get { self[VerticalLiveControlsVisibleKey.self] }
        set { self[VerticalLiveControlsVisibleKey.self] = newValue }
    }

    var verticalLiveControlPopupPresented: Binding<Bool> {
        get { self[VerticalLiveControlPopupPresentedKey.self] }
        set { self[VerticalLiveControlPopupPresentedKey.self] = newValue }
    }

    var isVerticalLiveMode: Bool {
        get { self[VerticalLiveModeEnvironmentKey.self] }
        set { self[VerticalLiveModeEnvironmentKey.self] = newValue }
    }
}
