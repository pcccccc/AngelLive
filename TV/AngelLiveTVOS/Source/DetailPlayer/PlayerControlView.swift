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
#if DEBUG
import os
#endif

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
    case settings
    case progress
    case reveal
}

enum PlayControlTopField: Hashable {
    case section(Int)
    case list(Int)
}


struct PlayerControlView: View {

    @Environment(RoomInfoViewModel.self) var roomInfoViewModel
    @Environment(AppState.self) var appViewModel
    @Environment(\.usesFullUI) private var usesFullUI
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State var sectionList: [LiveModel] = []
    @State var selectIndex = 0
    @State private var showStatisticsPanel = false
    @State private var showQualityPanel = false
    @State private var settingsPage: TVLivePlayerSettingsPanel.Page?
    @State private var settingsReturnFocus: TVLivePlayerSettingsPanel.Item?
    @State private var hideGeneration = UUID()
    @State private var showSubtitleLanguages = false
    @State private var subtitleActivationID = UUID()
    @State private var subtitleFocusGeneration = UUID()
    @State private var suppressHiddenFocusActivation = false
    @State private var pendingVisibleFocusAfterReveal: PlayControlFocusableField?
    @State private var showVolumeHUD = false
    @State private var volumeHUDHideTask: Task<Void, Never>?
    @State private var timeline = KSRoomSeekTimeline()
    @State private var focusBeforeProgress: PlayControlFocusableField = .playPause
    @StateObject private var systemVolumeObserver = TVSystemVolumeObserver()

    @FocusState var state: PlayControlFocusableField?
    @FocusState var topState: PlayControlTopField?
    @FocusState var showDanmuSetting: Bool

    @ObservedObject var playerCoordinator: KSVideoPlayer.Coordinator
    let showsRoomBanner: Bool
    let onBottomControlVisibilityChange: (Bool) -> Void

    private static let fullUIDanmakuHintFont = UIFont.systemFont(ofSize: 24, weight: .semibold)
    private static let fullUIDanmakuHintHorizontalInset: CGFloat = 24
    private let multiCameraTip = MultiCameraTip()
    #if DEBUG
    private static let navigationLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "AngelLiveTVOS",
        category: "PlayerNavigation"
    )
    #endif

    /// 是否有多机位（cdn数量大于1）
    private var hasMultiCamera: Bool {
        (roomInfoViewModel.currentRoomPlayArgs?.count ?? 0) > 1
    }

    private func topTabLabel(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, usesFullUI ? 0 : 22)
            .padding(.vertical, usesFullUI ? 0 : 8)
            .contentShape(Capsule())
    }


    var body: some View {
        
        @Bindable var roomInfoModel = roomInfoViewModel
        
        ZStack {
            if !usesFullUI, roomInfoViewModel.showControl && !roomInfoViewModel.showTop {
                // 遮罩独立贴住画面底边；按钮仍遵循原有安全区和焦点布局。
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.1), .black.opacity(0.5), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if roomInfoViewModel.showTop {
                VStack {
                    VStack(spacing: usesFullUI ? 32 : 105) {
                        // FullUI uses the same capsule clearance as the bottom controls.
                        HStack {
                            Spacer()
                            HStack(spacing: usesFullUI ? TVFullUIPlayerControlMetrics.spacing : 12) {
                                if showsFavoriteTopTab {
                                    Button(action: {}) {
                                        topTabLabel("收藏")
                                    }
                                    .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                                 isFocused: topState == .section(0), shape: .capsule))
                                    .focused($topState, equals: .section(0))
                                }
                                Button(action: {}) {
                                    topTabLabel("历史")
                                }
                                .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                             isFocused: topState == .section(1), shape: .capsule))
                                .focused($topState, equals: .section(1))
                                if roomInfoModel.roomType == .live {
                                    Button(action: {}) {
                                        topTabLabel("分区")
                                    }
                                    .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                                 isFocused: topState == .section(2), shape: .capsule))
                                    .focused($topState, equals: .section(2))
                                }
                            }
                            .modifier(TVFullUIPlayerControlGroupModifier(enabled: usesFullUI,
                                                                        legacyInsets: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)))
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .frame(height: usesFullUI ? TVFullUIPlayerControlMetrics.height + 2 * TVFullUIPlayerControlMetrics.inset : 55)
                        .focusSection()
                        .onChange(of: topState) { oldValue, newValue in
                            switch newValue {
                                case .section(let index):
                                    changeList(index)
                                default:
                                    break
                            }
                        }
                        
                        // FullUI keeps the card row at its intrinsic height so its
                        // title and focus growth are not compressed by the old shelf.
                        ScrollView(.horizontal) {
                            if usesFullUI {
                                LazyHStack(alignment: .top) {
                                    relatedRoomCards
                                }
                                .padding()
                            } else {
                                LazyHGrid(rows: [GridItem(.flexible())]) {
                                    relatedRoomCards
                                }
                                .padding()
                            }
                        }
                        .padding([.leading, .trailing], 55)
                        .padding(.top, usesFullUI ? 0 : 65)
                        .fixedSize(horizontal: false, vertical: usesFullUI)
                        .scrollClipDisabled()
                        .focusSection()
                        
                        if !usesFullUI {
                            Spacer()
                        }
                    }
                    .padding(.top, usesFullUI ? TVFullUIPlayerControlMetrics.screenInset : 0)
                    .padding(.bottom, usesFullUI ? 32 : 0)
                    .background(.black.opacity(0.6))
                    .frame(width: usesFullUI ? nil : 1920,
                           height: usesFullUI ? nil : 390)
                    .padding(.top, usesFullUI ? 0 : 30)
                    .transition(.move(edge: .top))
                    
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
                        }
                    }
                }

                if usesFullUI, let settingsPage {
                    GeometryReader { geometry in
                        TVLivePlayerSettingsPanel(
                            page: settingsPage, returnsFrom: settingsReturnFocus,
                            onOpen: { self.settingsPage = $0 },
                            onDanmaku: openDanmakuSettings,
                            onStatistics: showStatisticsAction,
                            onFavorite: favoriteAction,
                            onChooseLanguage: {
                                subtitleActivationID = roomInfoViewModel.subtitlePlayback.activationID
                                showSubtitleLanguages = true
                            },
                            onClose: closeSettingsPage
                        )
                        .frame(width: min(geometry.size.width * 0.4, 640))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .transition(panelTransition)
                    }
                    .zIndex(5)
                }

                if showStatisticsPanel {
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            TVPlayerStatisticsPanel(
                                playerCoordinator: playerCoordinator,
                                qualityTitle: usesFullUI ? roomInfoViewModel.fullUIQualityTitle : roomInfoViewModel.currentPlayQualityString,
                                streamURL: roomInfoViewModel.currentPlayURL
                            ) {
                                hideStatisticsPanel()
                            }
                            .frame(width: min(geometry.size.width * 0.4, 640), height: geometry.size.height - 80)
                            .padding(.vertical, 40)
                            .padding(.trailing, 48)
                            .transition(usesFullUI ? panelTransition : .move(edge: .trailing).combined(with: .opacity))
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
                                    roomInfoViewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex, selectionOrigin: .user)
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
                            .transition(usesFullUI ? panelTransition : .move(edge: .trailing).combined(with: .opacity))
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

                if usesFullUI {
                    fullUIDanmakuHint
                        .zIndex(7)
                } else if let hint = roomInfoViewModel.danmuStatusHint {
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

                if showsFullUIBottomControls {
                    fullUIControls
                        .disabled(settingsPage != nil)
                        .accessibilityHidden(settingsPage != nil)
                        .allowsHitTesting(settingsPage == nil)
                        .environment(\.tvPlayerControlsAreCovered, settingsPage != nil)
                } else if !usesFullUI, roomInfoViewModel.showControl {
                    VStack {
                        ZStack {
                            HStack {
                                Text("\(roomInfoViewModel.currentRoom.userName) - \(usesFullUI ? RoomTitleTranslationService.shared.displayTitle(for: roomInfoViewModel.currentRoom.roomTitle) : roomInfoViewModel.currentRoom.roomTitle)")
                                    .roomTitleTranslationTask(
                                        roomInfoViewModel.currentRoom.roomTitle,
                                        enabled: usesFullUI
                                    )
                                    .font(.title3)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.leading, usesFullUI ? TVFullUIPlayerControlMetrics.screenInset : 15)
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

                            if !usesFullUI {
                            Button(action: {}, label: {

                            })
                            .padding(.leading, -80)
                            .clipShape(.circle)
                            .frame(width: 40, height: 40)
                            .focused($state, equals: .left)
                            }

                        VStack {
                            HStack(spacing: usesFullUI ? TVFullUIPlayerControlMetrics.spacing : 0) {
                                Button(action: {
                                    guard ensureControlVisible() else { return }
                                    roomInfoViewModel.togglePlayPause()
                                }, label: {
                                    Image(systemName: roomInfoViewModel.userPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                })
                                .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                             isFocused: state == .playPause, shape: .circle, legacyShape: .circle))
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
                                .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                             isFocused: state == .refresh, shape: .circle, legacyShape: .circle))
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
                                            .padding(.top, usesFullUI ? 0 : 3)
                                    }
                                })
                                .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                             isFocused: state == .favorite, shape: .circle, legacyShape: .circle))
                                .focused($state, equals: .favorite)
                                .changeEffect(
                                    .spray(origin: UnitPoint(x: 0.25, y: 0.5)) {
                                        Image(systemName:roomInfoModel.currentRoomIsLiked ? "heart.fill" : "heart.slash.fill" )
                                        .foregroundStyle(.red)
                                    }, value: roomInfoModel.currentRoomIsLiked)
                            }
                            .modifier(TVFullUIPlayerControlGroupModifier(enabled: usesFullUI,
                                                                        legacyInsets: EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 5)))

                            if !usesFullUI {
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 150, height: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0.01)
                            }
                        }
                        .padding(.top, usesFullUI ? 0 : 60)
                       
                        Spacer()
                        VStack {
                            HStack(spacing: usesFullUI ? TVFullUIPlayerControlMetrics.spacing : 0) {
                                if roomInfoViewModel.showControl {
                                    Button {
                                        showQualityAction()
                                    } label: {
                                        qualityLabel()
                                    }
                                    .focused($state, equals: .playQuality)
                                    .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                                 isFocused: state == .playQuality, shape: .capsule,
                                                                                 legacyShape: .capsule, legacyHeight: 60))
                                } else {
                                    Button(action: {
                                        roomInfoViewModel.showControl = true
                                    }, label: {
                                        qualityLabel()
                                    })
                                    .focused($state, equals: .playQuality)
                                    .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                                 isFocused: state == .playQuality, shape: .capsule,
                                                                                 legacyShape: .capsule, legacyHeight: 60))
                                }
//                                .popoverTip(multiCameraTip, arrowEdge: .top) { _ in
//                                    // 点击 Tip 后关闭
//                                }

                                if roomInfoViewModel.supportsDanmu {
                                    if !usesFullUI {
                                    Text("")
                                        .frame(width: 15)
                                    }

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
                                    .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                                 isFocused: state == .danmuSetting, shape: .circle, legacyShape: .circle))
                                    .focused($state, equals: .danmuSetting)

                                    Button(action: {
                                        danmuAction()
                                    }, label: {
                                        Image(appViewModel.danmuSettingsViewModel.showDanmu ? "icon-danmu-open-focus" : "icon-danmu-close-focus")
                                            .resizable()
                                            .frame(width: 40, height: 40)
                                    })
                                    .modifier(TVFullUIPlayerControlButtonModifier(enabled: usesFullUI,
                                                                                 isFocused: state == .danmu, shape: .circle, legacyShape: .circle))
                                    .focused($state, equals: .danmu)
                                }
                            }
                            .modifier(TVFullUIPlayerControlGroupModifier(enabled: usesFullUI,
                                                                        legacyInsets: EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 0)))
                            .onAppear {
                                if !hasMultiCamera {
                                    multiCameraTip.invalidate(reason: .actionPerformed)
                                }
                            }

                            if !usesFullUI {
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 150, height: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0.01)
                            }
                        }
                        .padding(.top, usesFullUI ? 0 : 60)
                        
                        if !usesFullUI {
                        Button(action: {}, label: {
                            
                        })
                        .padding(.trailing, -80)
                        .clipShape(.circle)
                        .frame(width: 40, height: 40)
                        .focused($state, equals: .right)
                        }
                    }
                    .frame(height: usesFullUI ? TVFullUIPlayerControlMetrics.height + 2 * TVFullUIPlayerControlMetrics.inset : 150)
                    .padding(.horizontal, usesFullUI ? TVFullUIPlayerControlMetrics.screenInset : 0)
                    .padding(.bottom, usesFullUI ? TVFullUIPlayerControlMetrics.screenInset : 0)
                    }
                    .environment(\.colorScheme, .dark)
                    .focusSection()
                    .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if usesFullUI && showsRoomBanner && !roomInfoViewModel.isOnDemand && !hasOpenPanel {
                fullUIRoomBanner
            }
        }
        #if canImport(KSPlayer)
        .tvPlayerContrast(while: usesFullUI && !roomInfoViewModel.showTop
                          && (roomInfoViewModel.showControl || roomInfoViewModel.showsFullUIDanmakuHint
                              || roomInfoViewModel.danmuStatusHint != nil),
                          sourceID: roomInfoViewModel.currentPlayURL) {
            playerCoordinator.playerLayer?.player
        }
        #endif
        .onAppear {
            Logger.debug("[VolumeHUD] PlayerControlView appeared, initial volume=\(systemVolumeObserver.volume)", category: .ui)
            roomInfoViewModel.showControl = true
            restoreControlFocus()
        }
        .onChange(of: showsFullUIBottomControls, initial: true) { _, visible in
            guard usesFullUI else { return }
            onBottomControlVisibilityChange(visible)
            if !visible { timeline.cancelScrubbing() }
        }
        .onChange(of: timeline.target != nil) { _, _ in hideGeneration = UUID() }
        .onChange(of: roomInfoViewModel.currentPlayURL) { if usesFullUI { timeline.reset() } }
        .onChange(of: roomInfoViewModel.currentRoom.id) { if usesFullUI { timeline.reset() } }
        .task(id: showsFullUIBottomControls && roomInfoViewModel.isOnDemand ? roomInfoViewModel.currentPlayURL : nil) {
            guard showsFullUIBottomControls, roomInfoViewModel.isOnDemand, roomInfoViewModel.currentPlayURL != nil else { return }
            while !Task.isCancelled {
                timeline.sample(currentTimelineLayer)
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
        .onDisappear { if usesFullUI { timeline.reset() } }
        .sheet(isPresented: $showSubtitleLanguages) {
            LiveSubtitleLanguageSelectionSheet(
                playback: roomInfoViewModel.subtitlePlayback,
                activationID: subtitleActivationID
            )
        }
        .onChange(of: roomInfoViewModel.subtitlePlayback.activationID) { _, _ in
            showSubtitleLanguages = false
        }
        .onChange(of: showSubtitleLanguages) { _, isPresented in
            subtitleFocusGeneration = UUID()
            if isPresented {
                roomInfoViewModel.contolTimer?.invalidate()
                pendingVisibleFocusAfterReveal = nil
                state = nil
            } else if !usesFullUI {
                pendingVisibleFocusAfterReveal = .playPause
                let wasVisible = roomInfoViewModel.showControl
                roomInfoViewModel.showControl = true
                if wasVisible {
                    restoreControlFocus()
                }
            }
        }
        .onDisappear {
            subtitleFocusGeneration = UUID()
            volumeHUDHideTask?.cancel()
            volumeHUDHideTask = nil
        }
        // 订阅 TVSystemVolumeObserver:tick 每次音量回调 +1,触发 HUD
        // 触发条件:音频路由经 Apple TV 控制(HomePod / AirPods / AirPlay 2)。
        // HDMI-CEC 让电视自管音量时,系统不会回传给 App,这是平台限制。
        .onChange(of: systemVolumeObserver.changeTick) { _, _ in
            presentVolumeHUD()
        }
        .onChange(of: appViewModel.danmuSettingsViewModel.showDanmu) { _, isEnabled in
            guard roomInfoViewModel.supportsDanmu else { return }
            if isEnabled {
                roomInfoViewModel.getDanmuInfo()
            } else {
                roomInfoViewModel.disConnectSocket()
            }
        }
        .onChange(of: roomInfoViewModel.showControl) { oldValue, isVisible in
            guard !showSubtitleLanguages else {
                roomInfoViewModel.contolTimer?.invalidate()
                return
            }
            if isVisible {
                restoreControlFocus()
            } else {
                pendingVisibleFocusAfterReveal = nil
                restoreHiddenControlFocus()
            }
        }
        .onChange(of: state, { oldValue, newValue in
            guard !showSubtitleLanguages else { return }
            if usesFullUI {
                hideGeneration = UUID()
            } else {
                roomInfoViewModel.controlViewOptionSecond = 5
            }

            if oldValue != .list && oldValue != .reveal && oldValue != .progress
                && isListContentField(oldValue) == false && oldValue != nil {
                roomInfoViewModel.lastOptionState = oldValue
            }

            guard roomInfoViewModel.showTop == false,
                  roomInfoViewModel.showDanmuSettingView == false,
                  showStatisticsPanel == false,
                  showQualityPanel == false,
                  settingsPage == nil else {
                return
            }

            if roomInfoViewModel.showControl == false {
                if suppressHiddenFocusActivation {
                    suppressHiddenFocusActivation = false
                }
                return
            }

            if newValue == .left {
                state = roomInfoViewModel.supportsDanmu ? .danmu : .playQuality
            }else if newValue == .right {
                state = .playPause
            }else if newValue == .list {
                showRelatedRoomsPanel()
            }
        })
        .task(id: canAutoHide ? hideGeneration : nil) {
            guard canAutoHide else { return }
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard !Task.isCancelled, canAutoHide else { return }
            hideFullUIControls()
            if !roomInfoViewModel.onceTips { roomInfoViewModel.showTips = true }
        }
        .modifier(TVFullUIPlayPauseModifier(enabled: usesFullUI, action: toggleFullUIPlayback))
        .onExitCommand {
            logNavigation("exitCommand")
            handleBackCommand()
        }
        .onKeyPress(.escape, phases: .all) { press in
            logNavigation("escape phase=\(press.phase)")
            // 原生 Escape 不一定转换为 Exit。消费整个按键，只在松开时返回一层，
            // 避免按下收起列表后，同一次按键的松开又退出播放。
            if press.phase == .up {
                handleBackCommand()
            }
            return .handled
        }
    }

    private var hasOpenPanel: Bool {
        roomInfoViewModel.showTop || roomInfoViewModel.showDanmuSettingView || showQualityPanel
            || showStatisticsPanel || settingsPage != nil || showSubtitleLanguages
    }

    private var canAutoHide: Bool {
        usesFullUI && roomInfoViewModel.showControl && !hasOpenPanel && !voiceOverEnabled
            && roomInfoViewModel.isPlaying && !roomInfoViewModel.userPaused && scenePhase == .active
            && timeline.target == nil && !timeline.isCommitting
    }

    private var showsFullUIBottomControls: Bool {
        usesFullUI && roomInfoViewModel.showControl && !roomInfoViewModel.showTop
            && (!hasOpenPanel || settingsPage != nil)
    }

    private var visibilityAnimation: Animation {
        TVFullUIPlayerControlMetrics.visibilityAnimation(reduceMotion: reduceMotion)
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var fullUIControls: some View {
        ZStack {
            VStack(spacing: TVPlayerTimeline.buttonGap) {
                Spacer(minLength: 0)
                if roomInfoViewModel.isOnDemand, timeline.duration > 0 {
                    fullUIProgress
                }
                HStack(spacing: TVFullUIPlayerControlMetrics.spacing) {
                    TVFullUIPlayerControlGroup {
                        liveControl(roomInfoViewModel.userPaused ? "播放" : "暂停",
                                    symbol: roomInfoViewModel.userPaused ? "play.fill" : "pause.fill",
                                    focus: .playPause, action: toggleFullUIPlayback)
                        liveControl("刷新", symbol: "arrow.counterclockwise",
                                    focus: .refresh, action: refreshAction)
                    }
                    Spacer(minLength: 0)
                    TVFullUIPlayerControlGroup {
                        if roomInfoViewModel.supportsDanmu {
                            fullUIDanmakuButton
                        }
                        Button(action: showQualityAction) {
                            TVPlayerName(name: roomInfoViewModel.fullUIQualityTitle,
                                         font: .systemFont(ofSize: 26, weight: .semibold), maximumWidth: 6 * 26)
                        }
                        .modifier(TVFullUIPlayerControlButtonModifier(enabled: true, isFocused: state == .playQuality,
                                                                     shape: .capsule))
                        .focused($state, equals: .playQuality)
                        .accessibilityLabel("清晰度")
                        .accessibilityValue(roomInfoViewModel.fullUIQualityTitle)
                        liveControl("设置", symbol: "gearshape", focus: .settings, action: openSettingsPanel)
                    }
                }
                .frame(height: TVFullUIPlayerControlMetrics.groupHeight)
                .opacity(timeline.target == nil ? 1 : 0)
                .disabled(timeline.target != nil)
                .accessibilityHidden(timeline.target != nil)
                .animation(visibilityAnimation, value: timeline.target == nil)
                .focusSection()
                .onMoveCommand(perform: handleFullUIControlMove)
            }
            .padding(TVFullUIPlayerControlMetrics.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let target = timeline.target {
                TVPlayerSeekReadout(time: target, duration: timeline.duration, preview: timeline.preview)
                    .transition(.opacity)
            }
        }
        .defaultFocus($state, resolvedVisibleControlFocus(from: roomInfoViewModel.lastOptionState))
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
    }

    private var fullUIRoomBanner: some View {
        TVLivePlayerRoomIdentity(room: roomInfoViewModel.currentRoom)
            .padding(.leading, 16)
            .padding(.trailing, 24)
            .padding(.vertical, 10)
            .frame(maxWidth: 640, alignment: .leading)
            .tvPlayerGlass(in: Capsule(), interactive: false)
            .tvPlayerShadow(in: Capsule())
            .environment(\.tvPlayerPrefersRegularGlass, true)
            .environment(\.colorScheme, .dark)
            .padding(TVFullUIPlayerControlMetrics.screenInset)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var fullUIProgress: some View {
        Button {
            if let target = timeline.target { timeline.seek(to: target, on: currentTimelineLayer) }
        } label: {
            TVPlayerTimeline(elapsed: timeline.elapsed, duration: timeline.duration, target: timeline.target,
                             isFocused: state == .progress)
        }
        .buttonStyle(TVFullUIHiddenControlButtonStyle())
        .focused($state, equals: .progress)
        .focusSection()
        .disabled(!timeline.canSeek)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(tvPlayerTimeLabel(timeline.target ?? timeline.elapsed))，总时长\(tvPlayerTimeLabel(timeline.duration))")
        .accessibilityHint(timeline.target == nil ? "左右调整进度" : "按下选择键确认，按菜单键取消")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: timeline.seek(to: timeline.elapsed + 15, on: currentTimelineLayer)
            case .decrement: timeline.seek(to: timeline.elapsed - 15, on: currentTimelineLayer)
            @unknown default: break
            }
        }
        .onMoveCommand { direction in
            hideGeneration = UUID()
            switch direction {
            case .left: adjustProgress(by: -15)
            case .right: adjustProgress(by: 15)
            case .down:
                if let target = timeline.target { timeline.seek(to: target, on: currentTimelineLayer) }
                state = focusBeforeProgress
            default: break
            }
        }
    }

    private var currentTimelineLayer: KSPlayerLayer? {
        guard let layer = playerCoordinator.playerLayer, layer.url == roomInfoViewModel.currentPlayURL else { return nil }
        return layer
    }

    private func adjustProgress(by delta: Double) {
        guard currentTimelineLayer != nil else { return }
        timeline.beginScrubbing()
        guard let target = timeline.target else { return }
        let selection = RoomPlaybackResolver.selection(in: roomInfoViewModel.currentRoomPlayArgs,
                                                       cdnIndex: roomInfoViewModel.currentCdnIndex,
                                                       qualityIndex: roomInfoViewModel.currentQualityIndex)
        timeline.updateScrub(to: target + delta, url: roomInfoViewModel.currentPlayURL, quality: selection?.quality)
    }

    private func liveControl(_ label: LocalizedStringKey, symbol: String, focus: PlayControlFocusableField,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 40, height: 40)
        }
        .modifier(TVFullUIPlayerControlButtonModifier(enabled: true, isFocused: state == focus, shape: .circle))
        .focused($state, equals: focus)
        .accessibilityLabel(Text(label))
        .foregroundStyle(.white)
    }

    private var fullUIDanmakuButton: some View {
        let enabled = appViewModel.danmuSettingsViewModel.showDanmu
        let status = collapsedDanmakuStatus
        return Button(action: danmuAction) {
            Image(systemName: enabled ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 40, height: 40)
                .overlay(alignment: .topTrailing) {
                    if status != nil {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                    }
                }
        }
        .modifier(TVFullUIPlayerControlButtonModifier(enabled: true, isFocused: state == .danmu, shape: .circle))
        .focused($state, equals: .danmu)
        .accessibilityLabel(enabled ? "关闭弹幕" : "开启弹幕")
        .accessibilityValue(status?.title ?? "")
        .foregroundStyle(.white)
    }

    private var collapsedDanmakuStatus: DanmakuConnectionStatus? {
        guard !roomInfoViewModel.showsFullUIDanmakuHint, let status = roomInfoViewModel.fullUIDanmakuStatus,
              status == .failed || status == .reconnecting else { return nil }
        return status
    }

    private var fullUIDanmakuHintTitle: String? {
        let status: DanmakuConnectionStatus?
        if hasOpenPanel {
            status = nil
        } else if roomInfoViewModel.showsFullUIDanmakuHint {
            status = roomInfoViewModel.fullUIDanmakuStatus
        } else {
            status = state == .danmu ? collapsedDanmakuStatus : nil
        }
        return status?.title ?? (hasOpenPanel ? nil : roomInfoViewModel.danmuStatusHint)
    }

    private var fullUIDanmakuHint: some View {
        let title = fullUIDanmakuHintTitle
        let bottom = roomInfoViewModel.showControl
            ? TVFullUIPlayerControlMetrics.screenInset + TVFullUIPlayerControlMetrics.groupHeight + 8 : 24
        return ZStack(alignment: .bottom) {
            if let title {
                Text(title)
                    .font(Font(Self.fullUIDanmakuHintFont))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Self.fullUIDanmakuHintHorizontalInset)
                    .padding(.vertical, 14)
                    .tvPlayerGlass(in: Capsule(), interactive: false)
                    .tvPlayerShadow(in: Capsule())
                    .padding(.bottom, bottom)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .animation(visibilityAnimation, value: title)
        .environment(\.colorScheme, .dark)
    }

    private var relatedRoomCards: some View {
        ForEach(sectionList.indices, id: \.self) { index in
            PlayerControlCardView { liveModel in
                changeRoom(liveModel)
            }
            .environment(PlayerControlCardViewModel(liveModel: sectionList[index], cardIndex: index, selectIndex: selectIndex))
        }
    }

    private func handleBackCommand() {
        if showSubtitleLanguages {
            showSubtitleLanguages = false
            return
        }
        if roomInfoViewModel.showTop {
            logNavigation("closeRelatedRooms")
            withAnimation {
                roomInfoViewModel.showTop = false
            }
            topState = nil
            DispatchQueue.main.async {
                if roomInfoViewModel.showControl {
                    restoreControlFocus()
                } else {
                    restoreHiddenControlFocus()
                }
            }
            return
        }

        if roomInfoViewModel.showDanmuSettingView {
            roomInfoViewModel.showDanmuSettingView = false
            showDanmuSetting = false
            if usesFullUI {
                settingsReturnFocus = .danmaku
                settingsPage = .menu
                return
            }
            state = roomInfoViewModel.lastOptionState
            roomInfoViewModel.showControl = true
            return
        }

        if showStatisticsPanel {
            hideStatisticsPanel()
            return
        }

        if showQualityPanel {
            hideQualityPanel()
            return
        }

        if settingsPage != nil {
            closeSettingsPage()
            return
        }

        if usesFullUI, timeline.target != nil {
            timeline.cancelScrubbing()
            return
        }

        if roomInfoViewModel.showControl {
            logNavigation("hideControls")
            if usesFullUI {
                hideFullUIControls()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    roomInfoViewModel.showControl = false
                }
            }
        } else {
            logNavigation("endPlayback")
            roomInfoViewModel.stopLiveStatusPolling()
            NotificationCenter.default.post(name: SimpleLiveNotificationNames.playerEndPlay, object: nil)
        }
    }

    private func logNavigation(_ event: String) {
        let message = "PlayerNavigation \(event) top=\(roomInfoViewModel.showTop) controls=\(roomInfoViewModel.showControl) focus=\(String(describing: state)) topFocus=\(String(describing: topState))"
        Logger.debug(message, category: .ui)
        #if DEBUG
        os_log("%{public}@", log: Self.navigationLog, type: .default, message)
        #endif
    }

    private func showStatisticsAction() {
        if usesFullUI {
            withAnimation(visibilityAnimation) {
                settingsPage = nil
                showStatisticsPanel = true
            }
            return
        }
        guard ensureControlVisible() else { return }
        roomInfoViewModel.lastOptionState = state ?? .playPause
        state = nil
        withAnimation(.easeInOut(duration: 0.28)) {
            showStatisticsPanel = true
            roomInfoViewModel.showControl = false
        }
    }

    private func hideStatisticsPanel() {
        if usesFullUI {
            withAnimation(visibilityAnimation) {
                showStatisticsPanel = false
                settingsReturnFocus = .statistics
                settingsPage = .menu
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            showStatisticsPanel = false
            roomInfoViewModel.showControl = true
        }
    }

    private func showQualityAction() {
        guard ensureControlVisible() else { return }
        roomInfoViewModel.lastOptionState = usesFullUI ? .playQuality : (state ?? .playQuality)
        state = nil
        withAnimation(usesFullUI ? visibilityAnimation : .easeInOut(duration: 0.28)) {
            showQualityPanel = true
            roomInfoViewModel.showControl = false
        }
    }

    private func hideQualityPanel() {
        withAnimation(usesFullUI ? visibilityAnimation : .easeInOut(duration: 0.28)) {
            showQualityPanel = false
            roomInfoViewModel.showControl = true
        }
    }

    private func openSettingsPanel() {
        roomInfoViewModel.lastOptionState = .settings
        settingsReturnFocus = nil
        state = nil
        withAnimation(visibilityAnimation) { settingsPage = .menu }
    }

    private func closeSettingsPage() {
        if settingsPage == .subtitles {
            settingsReturnFocus = .subtitles
            settingsPage = .menu
        } else if settingsPage == .playback {
            settingsReturnFocus = .playback
            settingsPage = .menu
        } else {
            withAnimation(visibilityAnimation) { settingsPage = nil }
            restoreControlFocus()
        }
    }

    private func openDanmakuSettings() {
        settingsPage = nil
        roomInfoViewModel.showDanmuSettingView = true
        showDanmuSetting = true
    }

    private func toggleFullUIPlayback() {
        guard !hasOpenPanel, timeline.target == nil, !timeline.isCommitting else { return }
        revealFullUIControls()
        roomInfoViewModel.togglePlayPause()
        hideGeneration = UUID()
    }

    private func revealFullUIControls() {
        guard !roomInfoViewModel.showControl else { return }
        roomInfoViewModel.lastOptionState = .playPause
        withAnimation(visibilityAnimation) { roomInfoViewModel.showControl = true }
    }

    private func hideFullUIControls() {
        withAnimation(visibilityAnimation) { roomInfoViewModel.showControl = false }
    }

    private var shouldShowHiddenControlAnchors: Bool {
        !roomInfoViewModel.showControl && !hasOpenPanel
    }

    @ViewBuilder
    private var hiddenControlAnchorOverlay: some View {
        if usesFullUI {
            fullUIHiddenControlAnchorOverlay
        } else {
            legacyHiddenControlAnchorOverlay
        }
    }

    private var fullUIHiddenControlAnchorOverlay: some View {
        Button(action: revealFullUIControls) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(TVFullUIHiddenControlButtonStyle())
        .focused($state, equals: .reveal)
        .defaultFocus($state, .reveal)
        .accessibilityLabel("显示播放控制")
        .onMoveCommand { direction in
            if direction == .down { showRelatedRoomsPanel() }
            else { revealFullUIControls() }
        }
    }

    private var legacyHiddenControlAnchorOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 15) {
                hiddenControlAnchor(width: 40, height: 40, focus: .left)
                    .padding(.leading, -80)

                VStack(spacing: 20) {
                    HStack(spacing: usesFullUI ? TVFullUIPlayerControlMetrics.spacing : 0) {
                        hiddenControlAnchor(width: usesFullUI ? 70 : 50, height: usesFullUI ? 70 : 60, focus: .playPause)
                        hiddenControlAnchor(width: usesFullUI ? 70 : 50, height: usesFullUI ? 70 : 60, focus: .refresh)
                        hiddenControlAnchor(width: usesFullUI ? 70 : 50, height: usesFullUI ? 70 : 60, focus: .favorite)
                    }
                    .padding(.horizontal, usesFullUI ? TVFullUIPlayerControlMetrics.inset : 5)
                    .padding(.vertical, usesFullUI ? TVFullUIPlayerControlMetrics.inset : 10)

                    if !usesFullUI {
                    hiddenControlAnchor(width: 150, height: 40, focus: .list)
                    }
                }

                Spacer()

                VStack(spacing: 20) {
                    HStack(spacing: usesFullUI ? TVFullUIPlayerControlMetrics.spacing : 0) {
                        hiddenControlAnchor(width: 150, height: 60, focus: .playQuality)
                        if roomInfoViewModel.supportsDanmu {
                            Color.clear.frame(width: 15)
                            hiddenControlAnchor(width: 50, height: 60, focus: .danmuSetting)
                            hiddenControlAnchor(width: 50, height: 60, focus: .danmu)
                        }
                    }
                    .padding(.leading, usesFullUI ? TVFullUIPlayerControlMetrics.inset : 15)
                    .padding(.trailing, usesFullUI ? TVFullUIPlayerControlMetrics.inset : 0)
                    .padding(.vertical, usesFullUI ? TVFullUIPlayerControlMetrics.inset : 10)

                    if !usesFullUI {
                    hiddenControlAnchor(width: 150, height: 40, focus: .list)
                    }
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
        Button(action: {
            pendingVisibleFocusAfterReveal = resolvedVisibleControlFocus(from: focus)
            roomInfoViewModel.showControl = true
        }) {
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
        guard !hasOpenPanel else { return }
        if usesFullUI {
            state = resolvedVisibleControlFocus(from: roomInfoViewModel.lastOptionState)
            return
        }

        let preferredFocus = pendingVisibleFocusAfterReveal ?? (state == .list ? roomInfoViewModel.lastOptionState : (state ?? roomInfoViewModel.lastOptionState))
        let target = resolvedVisibleControlFocus(from: preferredFocus)
        let generation = subtitleFocusGeneration
        DispatchQueue.main.async {
            guard generation == subtitleFocusGeneration, !showSubtitleLanguages else { return }
            state = nil
            DispatchQueue.main.async {
                guard generation == subtitleFocusGeneration, !showSubtitleLanguages else { return }
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
        if usesFullUI {
            state = .reveal
            return
        }

        let preferredFocus = state == .list ? roomInfoViewModel.lastOptionState : (state ?? roomInfoViewModel.lastOptionState)
        let target = resolvedHiddenAnchorFocus(from: preferredFocus)
        let generation = subtitleFocusGeneration

        suppressHiddenFocusActivation = true
        DispatchQueue.main.async {
            guard generation == subtitleFocusGeneration, !showSubtitleLanguages else { return }
            state = nil
            DispatchQueue.main.async {
                guard generation == subtitleFocusGeneration, !showSubtitleLanguages else { return }
                state = target
            }
        }
    }

    private func showRelatedRoomsPanel() {
        logNavigation("openRelatedRooms")
        let initialSection = preferredTopSectionIndex()
        changeList(initialSection)

        withAnimation(.easeInOut(duration: 0.2)) {
            roomInfoViewModel.showTop = true
        }

        DispatchQueue.main.async {
            guard roomInfoViewModel.showTop else { return }
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
        if usesFullUI {
            switch candidate {
            case .refresh: return .refresh
            case .danmu: return firstRightControl
            case .playQuality: return .playQuality
            case .settings: return .settings
            default: return .playPause
            }
        }
        switch candidate {
        case .danmu, .danmuSetting:
            return roomInfoViewModel.supportsDanmu ? (candidate ?? .playQuality) : .playQuality
        case .refresh, .favorite, .playQuality, .left, .right:
            return candidate ?? .playPause
        case .playPause:
            return .playPause
        default:
            return .playPause
        }
    }

    private func handleFullUIControlMove(_ direction: MoveCommandDirection) {
        hideGeneration = UUID()
        switch direction {
        case .up where roomInfoViewModel.isOnDemand && timeline.canSeek && !timeline.isCommitting:
            focusBeforeProgress = resolvedVisibleControlFocus(from: state)
            state = .progress
        case .down:
            showRelatedRoomsPanel()
        case .right where state == .refresh:
            state = firstRightControl
        case .left where state == firstRightControl:
            state = .refresh
        default:
            break
        }
    }

    private var firstRightControl: PlayControlFocusableField {
        roomInfoViewModel.supportsDanmu ? .danmu : .playQuality
    }

    private func resolvedHiddenAnchorFocus(from candidate: PlayControlFocusableField?) -> PlayControlFocusableField {
        switch candidate {
        case .danmu, .danmuSetting:
            return roomInfoViewModel.supportsDanmu ? (candidate ?? .playQuality) : .playQuality
        case .playPause, .refresh, .favorite, .playQuality, .list, .left, .right:
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
            return roomInfoViewModel.supportsDanmu ? .danmuSetting : .right
        case (.danmuSetting, .left):
            return .playQuality
        case (.danmuSetting, .right):
            return .danmu
        case (.danmu, .left):
            return .danmuSetting
        case (.danmu, .right):
            return .right
        case (.right, .left):
            return roomInfoViewModel.supportsDanmu ? .danmu : .playQuality
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
    }

    @discardableResult
    private func ensureControlVisible() -> Bool {
        if usesFullUI { hideGeneration = UUID() }
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
        if usesFullUI {
            Text(roomInfoViewModel.currentPlayQualityString)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(.white)
        } else if #available(tvOS 26.0, *) {
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

private struct TVFullUIPlayPauseModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled { content.onPlayPauseCommand(perform: action) }
        else { content }
    }
}
