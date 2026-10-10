import SwiftUI
import AngelLiveCore

#if canImport(KSPlayer)
import UIKit
import Observation
import AngelLiveDependencies
import KSPlayer
import Kingfisher

/// FullUI short-drama playback. Episode resolution and completion policy stay in the model.
struct ShortDramaPlayerView: View {
    let room: LiveModel

    @State private var model: ShortDramaPlaybackModel
    @State private var playerController = ShortDramaPlayerController()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary,
        supportedGlobalCapabilities: [.audioFocus]
    )
    @State private var isPlaying = false
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var videoNaturalSize: CGSize?
    @State private var seekValue = 0.0
    @State private var isSeeking = false
    @State private var playbackRate: Float = 1
    @State private var panel: ShortDramaPanel?
    @State private var latestPanelMetrics: ShortDramaPanelMetrics?
    @State private var panelVisibleHeight: CGFloat = 0
    @State private var panelPresentationOpacity = 0.0
    @State private var panelTargetDetent: ShortDramaPanelDetent = .medium
    @State private var panelDragStartHeight: CGFloat?
    @State private var panelDragStartDetent: ShortDramaPanelDetent?
    @State private var resumeAfterPanel = false
    @State private var resumeSelectedEpisodeAfterPanel = false
    @State private var panelPlaybackID: UUID?
    @State private var panelTransitioning = false
    @State private var isLeavingPage = false
    @State private var wasPlayingBeforeBackground = false
    @State private var boundaryMessage: String?
    @State private var boundaryMessageToken = UUID()
    @State private var readyPlaybackID: UUID?
    @GestureState private var episodeSwipeGesture = ShortDramaEpisodeSwipeGestureState()
    @State private var episodeSwipeSettlementOffset: CGFloat = 0
    @State private var episodeSwipeSettlementOpacity = 1.0
    @State private var episodeSwipeTransitioning = false
    @State private var episodeSwipeSelecting = false
    @State private var episodeSwipeAwaitingGestureReset = false
    @State private var episodeSwipeToken = UUID()
    @State private var episodeSwipeHoldActive = false
    @State private var episodeSwipeHoldTask: Task<Void, Never>?
    @State private var panelAnimationToken = UUID()
    @ScaledMetric(relativeTo: .headline) private var titleFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var quickRateDiameter: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var quickRateLabelSize: CGFloat = 13
    @AccessibilityFocusState private var accessibilityFocus: ShortDramaAccessibilityFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(room: LiveModel) {
        self.room = room
        _model = State(initialValue: ShortDramaPlaybackModel(room: room))
    }

    var body: some View {
        GeometryReader { geometry in
            let safeInsets = geometry.safeAreaInsets
            let fullSize = CGSize(
                width: geometry.size.width + safeInsets.leading + safeInsets.trailing,
                height: geometry.size.height + safeInsets.top + safeInsets.bottom
            )
            let panelMetrics = ShortDramaPanelMetrics(
                containerSize: CGSize(width: fullSize.width, height: geometry.size.height),
                safeTop: safeInsets.top,
                safeBottom: safeInsets.bottom,
                isPad: UIDevice.current.userInterfaceIdiom == .pad
            )

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    GeometryReader { videoGeometry in
                        videoRegion(
                            size: videoGeometry.size,
                            metrics: panelMetrics,
                            safeInsets: safeInsets
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomControls(metrics: panelMetrics, safeInsets: safeInsets)
                        .opacity(panel != nil || panelTransitioning ? 0 : 1)
                        .allowsHitTesting(
                            panel == nil
                                && !panelTransitioning
                                && !episodeSwipeHoldActive
                                && !episodeSwipeTransitioning
                        )
                        .accessibilityHidden(
                            panel != nil
                                || panelTransitioning
                                || episodeSwipeHoldActive
                                || episodeSwipeTransitioning
                        )
                }
                .frame(width: fullSize.width, height: fullSize.height, alignment: .topLeading)
                .offset(x: -safeInsets.leading, y: -safeInsets.top)

                panelOverlay(metrics: panelMetrics)
                    .zIndex(10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(Color.black)
            .onAppear {
                latestPanelMetrics = panelMetrics
            }
            .onChange(of: geometry.size) { _, _ in
                latestPanelMetrics = panelMetrics
                cancelEpisodeSwipe()
                cancelPanelDetentDrag(using: panelMetrics)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: panel?.id) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in
                await Task.yield()
                switch newValue {
                case ShortDramaPanel.episodes.id: accessibilityFocus = .episodesTitle
                case ShortDramaPanel.settings.id: accessibilityFocus = .settingsTitle
                default: break
                }
            }
        }
        .task {
            if model.episodes.isEmpty, !model.isLoading, model.errorMessage == nil {
                await model.load()
            }
        }
        .task(id: PlaybackObservationKey(playbackID: model.playback?.id, isActive: scenePhase == .active)) {
            await observePlaybackTime(isActive: scenePhase == .active)
        }
        .onChange(of: playbackRate) { _, newValue in
            playerController.setRate(newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
            if phase != .active, let latestPanelMetrics {
                cancelPanelDetentDrag(using: latestPanelMetrics)
            }
        }
        .onChange(of: episodeSwipeGesture) { oldValue, newValue in
            if !newValue.isVerticalLocked, episodeSwipeAwaitingGestureReset {
                episodeSwipeAwaitingGestureReset = false
                if !episodeSwipeHoldActive {
                    episodeSwipeTransitioning = false
                }
                return
            }
            guard oldValue.isVerticalLocked,
                  !newValue.isVerticalLocked,
                  !episodeSwipeTransitioning,
                  !isLeavingPage else { return }
            Task { @MainActor in
                await Task.yield()
                guard episodeSwipeHoldActive, !episodeSwipeTransitioning, !isLeavingPage else { return }
                let opacity = reduceMotion
                    ? 1 - min(abs(oldValue.rawVerticalTranslation) / 800, 0.15)
                    : 1
                settleEpisodeSwipeBack(
                    from: oldValue.verticalOffset,
                    message: nil,
                    startingOpacity: opacity
                )
            }
        }
        .onChange(of: model.playback?.id) { oldValue, newValue in
            if oldValue != newValue {
                videoNaturalSize = nil
            }
            if readyPlaybackID != newValue {
                readyPlaybackID = nil
                isPlaying = false
            }
            if newValue == nil, model.isLoading, episodeSwipeSelecting {
                resetEpisodeSwipeVisualsAfterSelectionStarts()
            }
        }
        .onDisappear {
            isLeavingPage = true
            panelAnimationToken = UUID()
            panelTransitioning = false
            panelDragStartHeight = nil
            panelDragStartDetent = nil
            panelVisibleHeight = 0
            panelPresentationOpacity = 0
            panelTargetDetent = .closed
            invalidateEpisodeSwipe()
            model.cancel()
            playerController.stop()
            playbackSession.invalidate(releasingResources: false)
        }
    }

    private func videoRegion(
        size: CGSize,
        metrics: ShortDramaPanelMetrics,
        safeInsets: EdgeInsets
    ) -> some View {
        ZStack {
            playbackSurface(in: size)
                .offset(y: playbackSurfaceOffset)
                .opacity(playbackSurfaceOpacity)
                .accessibilityHidden(panel != nil || panelTransitioning)

            episodeInteractionLayer(availableHeight: size.height)
                .allowsHitTesting(
                    panel == nil
                        && !panelTransitioning
                        && !episodeSwipeTransitioning
                        && isCurrentPlaybackReady
                )
                .accessibilityHidden(
                    panel != nil
                        || panelTransitioning
                        || !isCurrentPlaybackReady
                )

            if model.errorMessage == nil,
               let playbackID = model.playback?.id,
               (!playerController.wantsPlayback || (readyPlaybackID == playbackID && !isPlaying)),
               !episodeSwipeHoldActive,
               !episodeSwipeTransitioning,
               panel == nil,
               !panelTransitioning {
                Button(action: togglePlayback) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background { controlGlassCircle }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.hasFinished ? "重播本集" : "继续播放")
                .accessibilityHint(model.hasFinished ? "双击从头重播本集" : "双击从当前进度继续播放")
                .zIndex(2)
            }

            if let boundaryMessage {
                Text(boundaryMessage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.66), in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)
                    .transition(reduceMotion ? .identity : .opacity)
                    .zIndex(3)
            }
        }
        .overlay(alignment: .top) {
            topControls(metrics: metrics)
                .padding(.top, max(8, safeInsets.top + 4))
                .padding(.leading, 16 + safeInsets.leading)
                .padding(.trailing, 16 + safeInsets.trailing)
                .allowsHitTesting(
                    panel == nil
                        && !panelTransitioning
                        && !episodeSwipeHoldActive
                        && !episodeSwipeTransitioning
                )
                .accessibilityHidden(
                    panel != nil
                        || panelTransitioning
                        || episodeSwipeHoldActive
                        || episodeSwipeTransitioning
                )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func playbackSurface(in viewport: CGSize) -> some View {
        let fittedSize = fittedVideoSize(in: viewport)

        return ZStack(alignment: .top) {
            coverBackground

            if let playback = model.playback {
                ShortDramaPlayerSurface(
                    playback: playback,
                    playbackRate: playbackRate,
                    desiredPlayback: playerController.wantsPlayback,
                    model: model,
                    controller: playerController,
                    playbackSession: playbackSession,
                    onReady: handlePlaybackReady,
                    onPlayingChanged: handlePlayingChanged,
                    onVideoSize: { playbackID, size in
                        guard model.playback?.id == playbackID,
                              playerController.playbackID == playbackID else { return }
                        if videoNaturalSize != size {
                            videoNaturalSize = size
                        }
                    }
                )
                .id(playback.id)
                .frame(width: fittedSize.width, height: fittedSize.height)
                .opacity(readyPlaybackID == playback.id && videoNaturalSize != nil ? 1 : 0)
                .transition(.opacity)
            }
        }
        .overlay {
            if model.errorMessage != nil {
                loadState
                    .transition(.opacity)
            } else if isPreparingPlayback {
                preparingOverlay
                    .transition(.opacity)
            } else if model.playback == nil {
                loadState
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .animation(.easeOut(duration: 0.15), value: model.playback?.id)
        .animation(.easeOut(duration: 0.15), value: readyPlaybackID)
    }

    private func fittedVideoSize(in viewport: CGSize) -> CGSize {
        guard let videoNaturalSize,
              videoNaturalSize.width.isFinite, videoNaturalSize.height.isFinite,
              videoNaturalSize.width > 1, videoNaturalSize.height > 1 else {
            return viewport
        }

        let aspectRatio = videoNaturalSize.width / videoNaturalSize.height
        guard aspectRatio.isFinite, aspectRatio > 0 else { return viewport }
        let width = min(viewport.width, viewport.height * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }

    private var isPreparingPlayback: Bool {
        guard model.errorMessage == nil else { return false }
        if model.isLoading { return true }
        guard let playbackID = model.playback?.id else { return false }
        return readyPlaybackID != playbackID || videoNaturalSize == nil
    }

    private var isCurrentPlaybackReady: Bool {
        guard model.errorMessage == nil, let playbackID = model.playback?.id else { return false }
        return readyPlaybackID == playbackID
    }

    private var preparingEpisodeMessage: String {
        if let episode = model.selectedEpisode {
            return "正在准备第 \(episode.number) 集"
        }
        return "正在加载剧集"
    }

    private var coverBackground: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let url = URL(string: room.roomCover), !room.roomCover.isEmpty {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .overlay(Color.black.opacity(isPreparingPlayback ? 0.58 : 1))
        }
        .accessibilityHidden(true)
    }

    private var preparingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white)
            Text(preparingEpisodeMessage)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preparingEpisodeMessage)
        .allowsHitTesting(false)
    }

    private func episodeInteractionLayer(availableHeight: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture(perform: togglePlayback)
            .accessibilityLabel(isPlaying ? "暂停播放" : "继续播放")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("双击暂停或继续；使用上下集无障碍操作切换剧集")
            .accessibilityAction(.default, togglePlayback)
            .accessibilityAction(named: Text("上一集")) { changeEpisode(by: -1) }
            .accessibilityAction(named: Text("下一集")) { changeEpisode(by: 1) }
            .simultaneousGesture(episodeSwipeGestureForVideo(availableHeight: availableHeight))
    }

    private func episodeSwipeGestureForVideo(availableHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($episodeSwipeGesture) { value, state, transaction in
                transaction.animation = nil
                guard panel == nil,
                      !panelTransitioning,
                      !episodeSwipeTransitioning else {
                    state = .zero
                    return
                }
                let translation = value.translation
                if state.isVerticalLocked || abs(translation.height) > abs(translation.width) * 1.3 {
                    state = ShortDramaEpisodeSwipeGestureState(
                        isVerticalLocked: true,
                        rawVerticalTranslation: translation.height,
                        verticalOffset: episodeSwipeDragOffset(
                            translation.height,
                            availableHeight: availableHeight
                        )
                    )
                } else {
                    state = .zero
                }
            }
            .onChanged { value in
                guard panel == nil,
                      !panelTransitioning,
                      !episodeSwipeTransitioning,
                      abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
                beginEpisodeSwipeHold()
            }
            .onEnded { value in
                finishEpisodeSwipe(value, availableHeight: availableHeight)
            }
    }

    private var playbackSurfaceOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        if episodeSwipeTransitioning { return episodeSwipeSettlementOffset }
        return episodeSwipeGesture.isVerticalLocked ? episodeSwipeGesture.verticalOffset : 0
    }

    private var playbackSurfaceOpacity: Double {
        if episodeSwipeTransitioning { return episodeSwipeSettlementOpacity }
        guard reduceMotion, episodeSwipeGesture.isVerticalLocked else { return 1 }
        let fade = min(abs(episodeSwipeGesture.rawVerticalTranslation) / 800, 0.15)
        return 1 - fade
    }

    private func episodeSwipeDragOffset(_ translation: CGFloat, availableHeight: CGFloat) -> CGFloat {
        guard !reduceMotion, translation != 0 else { return 0 }
        let direction = translation < 0 ? 1 : -1
        guard targetEpisode(for: direction) != nil else {
            let damped = min(32, abs(translation) * 0.22)
            return translation < 0 ? -damped : damped
        }
        let limit = max(0, availableHeight)
        return min(max(translation, -limit), limit)
    }

    private func targetEpisode(for direction: Int) -> ShortDramaEpisode? {
        guard let id = model.selectedEpisodeID,
              let index = model.episodes.firstIndex(where: { $0.id == id }) else { return nil }
        let targetIndex = index + direction
        guard model.episodes.indices.contains(targetIndex) else { return nil }
        return model.episodes[targetIndex]
    }

    private func beginEpisodeSwipeHold() {
        guard !episodeSwipeHoldActive else { return }
        episodeSwipeHoldActive = true
        let model = model
        episodeSwipeHoldTask = Task { @MainActor in
            await model.setEpisodeSwipeActive(true)
        }
    }

    private func releaseEpisodeSwipeHold() async {
        guard episodeSwipeHoldActive else { return }
        let holdTask = episodeSwipeHoldTask
        await holdTask?.value
        guard !isLeavingPage else { return }
        await model.setEpisodeSwipeActive(false)
        episodeSwipeHoldTask = nil
        episodeSwipeHoldActive = false
    }

    private func finishEpisodeSwipe(_ value: DragGesture.Value, availableHeight: CGFloat) {
        guard !isLeavingPage,
              panel == nil,
              !panelTransitioning,
              !episodeSwipeTransitioning,
              episodeSwipeHoldActive else { return }

        let translation = value.translation
        guard abs(translation.height) > abs(translation.width) * 1.3 else {
            settleEpisodeSwipeBack(from: episodeSwipeGesture.verticalOffset, message: nil)
            return
        }

        let direction = translation.height < 0 ? 1 : -1
        let magnitude = abs(translation.height)
        let minimumDistance = min(120, max(0, availableHeight) * 0.18)
        let sameDirectionFlick = magnitude >= 28
            && abs(value.velocity.height) >= 650
            && value.velocity.height.sign == translation.height.sign
        let commits = magnitude >= minimumDistance || sameDirectionFlick
        let currentOffset = episodeSwipeDragOffset(
            translation.height,
            availableHeight: availableHeight
        )

        guard let target = targetEpisode(for: direction) else {
            if commits {
                settleEpisodeSwipeBack(
                    from: currentOffset,
                    message: direction < 0 ? "已经是第一集" : "已经是最后一集"
                )
            } else {
                settleEpisodeSwipeBack(from: currentOffset, message: nil)
            }
            return
        }

        guard commits else {
            settleEpisodeSwipeBack(from: currentOffset, message: nil)
            return
        }
        commitEpisodeSwipe(
            target: target,
            direction: direction,
            startingOffset: currentOffset,
            availableHeight: availableHeight
        )
    }

    private func settleEpisodeSwipeBack(from offset: CGFloat, message: String?) {
        settleEpisodeSwipeBack(from: offset, message: message, startingOpacity: playbackSurfaceOpacity)
    }

    private func settleEpisodeSwipeBack(
        from offset: CGFloat,
        message: String?,
        startingOpacity: Double
    ) {
        let token = UUID()
        episodeSwipeToken = token
        episodeSwipeTransitioning = true
        withTransaction(Transaction(animation: nil)) {
            episodeSwipeSettlementOffset = offset
            episodeSwipeSettlementOpacity = startingOpacity
        }
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(duration: 0.28, bounce: 0.08)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            episodeSwipeSettlementOffset = 0
            episodeSwipeSettlementOpacity = 1
        } completion: {
            guard episodeSwipeToken == token, !isLeavingPage else { return }
            Task { @MainActor in
                await releaseEpisodeSwipeHold()
                guard episodeSwipeToken == token, !isLeavingPage else { return }
                if !episodeSwipeAwaitingGestureReset {
                    episodeSwipeTransitioning = false
                }
                if let message { showBoundary(message) }
            }
        }
    }

    private func commitEpisodeSwipe(
        target: ShortDramaEpisode,
        direction: Int,
        startingOffset: CGFloat,
        availableHeight: CGFloat
    ) {
        let token = UUID()
        episodeSwipeToken = token
        episodeSwipeTransitioning = true
        episodeSwipeSelecting = false
        let startingOpacity = playbackSurfaceOpacity
        withTransaction(Transaction(animation: nil)) {
            episodeSwipeSettlementOffset = startingOffset
            episodeSwipeSettlementOpacity = startingOpacity
        }

        let animation: Animation = reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            if reduceMotion {
                episodeSwipeSettlementOpacity = 0
            } else {
                episodeSwipeSettlementOffset = direction > 0
                    ? -max(availableHeight, abs(startingOffset))
                    : max(availableHeight, abs(startingOffset))
            }
        } completion: {
            guard episodeSwipeToken == token, !isLeavingPage else { return }
            Task { @MainActor in
                guard episodeSwipeToken == token, !isLeavingPage else { return }
                episodeSwipeSelecting = true
                await episodeSwipeHoldTask?.value
                guard episodeSwipeToken == token, !isLeavingPage else { return }
                playerController.setDesiredPlayback(scenePhase == .active, applyImmediately: false)
                await model.selectEpisode(id: target.id)
                guard episodeSwipeToken == token, !isLeavingPage else { return }
                await releaseEpisodeSwipeHold()
                guard episodeSwipeToken == token, !isLeavingPage else { return }
                episodeSwipeSelecting = false
                if !episodeSwipeAwaitingGestureReset {
                    episodeSwipeTransitioning = false
                }
                withTransaction(Transaction(animation: nil)) {
                    episodeSwipeSettlementOffset = 0
                    episodeSwipeSettlementOpacity = 1
                }
            }
        }
    }

    private func resetEpisodeSwipeVisualsAfterSelectionStarts() {
        withTransaction(Transaction(animation: nil)) {
            episodeSwipeSettlementOffset = 0
            episodeSwipeSettlementOpacity = 1
        }
    }

    private func cancelEpisodeSwipe() {
        guard episodeSwipeTransitioning || episodeSwipeHoldActive || episodeSwipeGesture.isVerticalLocked else { return }
        let gestureIsActive = episodeSwipeGesture.isVerticalLocked
        invalidateEpisodeSwipe()
        if gestureIsActive {
            episodeSwipeAwaitingGestureReset = true
        }
        if gestureIsActive || episodeSwipeHoldActive {
            episodeSwipeTransitioning = true
        }
        let token = episodeSwipeToken
        Task { @MainActor in
            await releaseEpisodeSwipeHold()
            guard episodeSwipeToken == token, !isLeavingPage else { return }
            if !episodeSwipeAwaitingGestureReset {
                episodeSwipeTransitioning = false
            }
        }
    }

    private func invalidateEpisodeSwipe() {
        episodeSwipeToken = UUID()
        episodeSwipeSelecting = false
        episodeSwipeAwaitingGestureReset = false
        episodeSwipeTransitioning = false
        withTransaction(Transaction(animation: nil)) {
            episodeSwipeSettlementOffset = 0
            episodeSwipeSettlementOpacity = 1
        }
    }

    private func handlePlaybackReady(_ playbackID: UUID) {
        guard model.playback?.id == playbackID,
              playerController.playbackID == playbackID else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            readyPlaybackID = playbackID
        }
    }

    private func handlePlayingChanged(_ playbackID: UUID, isPlaying: Bool) {
        guard model.playback?.id == playbackID,
              playerController.playbackID == playbackID else { return }
        self.isPlaying = isPlaying
    }

    @ViewBuilder
    private var loadState: some View {
        if model.isLoading {
            VStack(spacing: 14) {
                ProgressView().tint(.white)
                Text(model.selectedEpisode.map { "正在准备第 \($0.number) 集" } ?? "正在加载剧集")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在加载短剧")
        } else if let error = model.errorMessage {
            stateMessage(
                symbol: "exclamationmark.triangle",
                title: "暂时无法播放",
                message: error,
                buttonTitle: "重试",
                action: retry
            )
        } else {
            stateMessage(
                symbol: "film",
                title: "暂无可播放剧集",
                message: "请稍后重试，或返回剧目列表。",
                buttonTitle: "重新加载",
                action: { Task { await model.load() } }
            )
        }
    }

    private func stateMessage(
        symbol: String,
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(.white, in: Capsule())
                .buttonStyle(.plain)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func topControls(metrics: ShortDramaPanelMetrics) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background { controlGlassCircle }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Spacer()

            Button {
                present(.settings, metrics: metrics)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background { controlGlassCircle }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放设置")
            .accessibilityFocused($accessibilityFocus, equals: .settingsTrigger)
        }
    }

    private func bottomControls(metrics: ShortDramaPanelMetrics, safeInsets: EdgeInsets) -> some View {
        VStack(spacing: 5) {
            progressControl
            episodeMetadata
            HStack(spacing: 8) {
                episodeDock(metrics: metrics)
                quickRateButton
            }
        }
        .padding(.leading, 16 + safeInsets.leading)
        .padding(.trailing, 16 + safeInsets.trailing)
        .padding(.bottom, max(metrics.safeBottom, 8))
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .accessibilityElement(children: .contain)
    }

    private var progressControl: some View {
        ZStack(alignment: .bottom) {
            ShortDramaProgressSlider(
                value: $seekValue,
                range: 0...max(duration, 1),
                isEnabled: canSeek,
                accessibilityLabel: "播放进度",
                accessibilityValue: "\(formatTime(isSeeking ? seekValue : currentTime)) / \(formatTime(duration))",
                onEditingChanged: { editing in
                    isSeeking = editing
                },
                onCommit: { value in
                    guard canSeek else { return }
                    playerController.seek(to: min(max(value, 0), duration), autoPlay: isPlaying)
                }
            )
            .frame(height: 44)

            if !isPlaying || isSeeking {
                HStack(spacing: 8) {
                    Text(formatTime(isSeeking ? seekValue : currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(minWidth: 34, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Text(formatTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(minWidth: 34, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .onChange(of: currentTime) { _, newValue in
            if !isSeeking { seekValue = min(max(newValue, 0), max(duration, 1)) }
        }
    }

    private var episodeMetadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(room.roomTitle.isEmpty ? room.userName : room.roomTitle)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let episode = model.selectedEpisode {
                Text("第 \(episode.number) 集 / 可播 \(model.episodes.count) 集")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .accessibilityLabel("第 \(episode.number) 集，可播 \(model.episodes.count) 集")
            }
        }
        .frame(minHeight: 30)
    }

    private func episodeDock(metrics: ShortDramaPanelMetrics) -> some View {
        Button {
            present(.episodes, metrics: metrics)
        } label: {
            HStack(spacing: 8) {
                Label("选集", systemImage: "list.bullet")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let episode = model.selectedEpisode {
                    Text("第 \(episode.number) 集")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { controlGlassCapsule }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(episodeDockAccessibilityLabel)
        .accessibilityHint("打开分集列表")
        .accessibilityFocused($accessibilityFocus, equals: .episodesTrigger)
    }

    private var quickRateButton: some View {
        let rateText = ShortDramaRateLabel.text(for: playbackRate)
        let nextRateText = ShortDramaRateLabel.text(for: ShortDramaRateLabel.nextCycleRate(after: playbackRate))
        let diameter = min(60, max(44, quickRateDiameter))
        let labelSize = min(quickRateLabelSize, 13 * diameter / 44)

        return Button {
            playbackRate = ShortDramaRateLabel.nextCycleRate(after: playbackRate)
        } label: {
            Text(rateText)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: playbackRate)
                .padding(.horizontal, 4)
                .frame(width: diameter, height: diameter)
                .background { controlGlassCircle }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("倍速，当前\(rateText)")
        .accessibilityHint("点按切换倍速至\(nextRateText)")
        .accessibilityFocused($accessibilityFocus, equals: .speedTrigger)
    }

    private var episodeDockAccessibilityLabel: String {
        guard let episode = model.selectedEpisode else { return "选择剧集" }
        return "选集，第 \(episode.number) 集，可播 \(model.episodes.count) 集"
    }

    private var canSeek: Bool {
        duration.isFinite && duration > 0 && playerController.isSeekable(for: model.playback?.id)
    }

    @ViewBuilder
    private func panelContent(metrics: ShortDramaPanelMetrics) -> some View {
        if let selectedPanel = panel {
            switch selectedPanel {
            case .episodes:
                ShortDramaEpisodesPanelContent(
                    room: room,
                    model: model,
                    onSelect: chooseEpisode,
                    onHeaderDragChanged: { updatePanelDetentDrag($0, metrics: metrics) },
                    onHeaderDragEnded: { finishPanelDetentDrag($0, metrics: metrics) },
                    onHeaderDragCancelled: { cancelActivePanelDetentDrag(using: metrics) },
                    availableWidth: metrics.panelWidth,
                    animateCurrentEpisode: resumeAfterPanel
                        && !model.hasFinished
                        && scenePhase == .active
                        && !reduceMotion,
                    accessibilityFocus: $accessibilityFocus
                )
                .padding(.bottom, max(metrics.safeBottom, 12) + 12)
            case .settings:
                ShortDramaSettingsPanelContent(
                    playbackRate: $playbackRate,
                    autoplay: Binding(get: { model.autoplay }, set: { model.autoplay = $0 }),
                    availableWidth: metrics.panelWidth,
                    onHeaderDragChanged: { updatePanelDetentDrag($0, metrics: metrics) },
                    onHeaderDragEnded: { finishPanelDetentDrag($0, metrics: metrics) },
                    onHeaderDragCancelled: { cancelActivePanelDetentDrag(using: metrics) },
                    accessibilityFocus: $accessibilityFocus
                )
                .padding(.bottom, max(metrics.safeBottom, 12) + 12)
            }
        }
    }

    private func panelOverlay(metrics: ShortDramaPanelMetrics) -> some View {
        let dimOpacity = panel == nil ? 0 : 0.28 * panelPresentationOpacity

        return ShortDramaDetentPanel(
            isPresented: panel != nil,
            isInteractive: !panelTransitioning,
            visibleHeight: panelVisibleHeight,
            presentationOpacity: panelPresentationOpacity,
            width: metrics.panelWidth,
            dimOpacity: dimOpacity,
            closeAccessibilityLabel: panel?.closeAccessibilityLabel ?? "关闭面板",
            onDismiss: dismissPanel,
            onToggleDetent: { togglePanelDetent(using: metrics) },
            onDragChanged: { updatePanelDetentDrag($0, metrics: metrics) },
            onDragEnded: { finishPanelDetentDrag($0, metrics: metrics) },
            onDragCancelled: { cancelActivePanelDetentDrag(using: metrics) }
        ) {
            panelContent(metrics: metrics)
        }
    }

    private func updatePanelDetentDrag(_ value: DragGesture.Value, metrics: ShortDramaPanelMetrics) {
        guard panel != nil,
              !panelTransitioning,
              !isLeavingPage else { return }

        if panelDragStartHeight == nil {
            guard abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
            panelDragStartHeight = panelVisibleHeight
            panelDragStartDetent = panelTargetDetent
        }
        guard let startHeight = panelDragStartHeight,
              let startDetent = panelDragStartDetent else { return }
        let minimumHeight = startDetent == .large && metrics.hasDistinctDetents ? metrics.mediumHeight : 0
        let maximumHeight = metrics.largeHeight
        withTransaction(Transaction(animation: nil)) {
            panelVisibleHeight = min(maximumHeight, max(minimumHeight, startHeight - value.translation.height))
        }
    }

    private func finishPanelDetentDrag(_ value: DragGesture.Value, metrics: ShortDramaPanelMetrics) {
        guard let startingDetent = panelDragStartDetent,
              panel != nil,
              !panelTransitioning,
              !isLeavingPage else {
            panelDragStartHeight = nil
            panelDragStartDetent = nil
            return
        }

        panelDragStartHeight = nil
        panelDragStartDetent = nil
        let translation = value.translation.height
        let downwardFling = translation >= 24 && value.velocity.height >= 650
        let upwardFling = translation <= -24 && value.velocity.height <= -650
        let detentThreshold = min(100, max(1, (metrics.largeHeight - metrics.mediumHeight) * 0.35))

        switch startingDetent {
        case .medium:
            if metrics.hasDistinctDetents && (translation <= -detentThreshold || upwardFling) {
                settlePanel(at: .large, metrics: metrics)
            } else if translation >= 80 || downwardFling {
                dismissPanel()
            } else {
                settlePanel(at: .medium, metrics: metrics)
            }
        case .large:
            if metrics.hasDistinctDetents && (translation >= detentThreshold || downwardFling) {
                settlePanel(at: .medium, metrics: metrics)
            } else if !metrics.hasDistinctDetents && (translation >= 80 || downwardFling) {
                dismissPanel()
            } else {
                settlePanel(at: metrics.hasDistinctDetents ? .large : .medium, metrics: metrics)
            }
        case .closed:
            panelVisibleHeight = 0
        }
    }

    private func cancelPanelDetentDrag(using metrics: ShortDramaPanelMetrics) {
        panelDragStartHeight = nil
        panelDragStartDetent = nil
        guard panel != nil, panelTargetDetent != .closed else { return }
        withTransaction(Transaction(animation: nil)) {
            panelVisibleHeight = panelTargetDetent.height(using: metrics)
        }
    }

    private func cancelActivePanelDetentDrag(using metrics: ShortDramaPanelMetrics) {
        guard let startingDetent = panelDragStartDetent,
              panel != nil,
              !panelTransitioning,
              !isLeavingPage else { return }
        panelDragStartHeight = nil
        panelDragStartDetent = nil
        settlePanel(at: startingDetent, metrics: metrics)
    }

    private func togglePanelDetent(using metrics: ShortDramaPanelMetrics) {
        guard !panelTransitioning, metrics.hasDistinctDetents else { return }
        settlePanel(at: panelTargetDetent == .large ? .medium : .large, metrics: metrics)
    }

    private func settlePanel(at detent: ShortDramaPanelDetent, metrics: ShortDramaPanelMetrics) {
        guard panel != nil else { return }
        panelTransitioning = true
        panelTargetDetent = detent
        panelAnimationToken = UUID()
        let token = panelAnimationToken
        withAnimation(panelDetentAnimation, completionCriteria: .logicallyComplete) {
            panelVisibleHeight = detent.height(using: metrics)
        } completion: {
            guard panelAnimationToken == token, !isLeavingPage else { return }
            panelTransitioning = false
        }
    }

    private func present(_ selectedPanel: ShortDramaPanel, metrics: ShortDramaPanelMetrics) {
        guard panel == nil,
              !panelTransitioning,
              !episodeSwipeHoldActive,
              !episodeSwipeTransitioning else { return }
        panelAnimationToken = UUID()
        panelDragStartHeight = nil
        panelDragStartDetent = nil
        panelTransitioning = true
        resumeAfterPanel = playerController.wantsPlayback && scenePhase == .active
        panelPlaybackID = model.playback?.id
        playerController.pause()
        let token = panelAnimationToken
        Task { @MainActor in
            await model.setEpisodesPresented(true)
            guard !isLeavingPage, panelAnimationToken == token else { return }
            let currentMetrics = latestPanelMetrics ?? metrics
            panel = selectedPanel
            panelTargetDetent = dynamicTypeSize.isAccessibilitySize && currentMetrics.hasDistinctDetents ? .large : .medium
            if reduceMotion {
                withTransaction(Transaction(animation: nil)) {
                    panelVisibleHeight = panelTargetDetent.height(using: currentMetrics)
                }
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28), completionCriteria: .logicallyComplete) {
                if !reduceMotion {
                    panelVisibleHeight = panelTargetDetent.height(using: currentMetrics)
                }
                panelPresentationOpacity = 1
            } completion: {
                guard panelAnimationToken == token, !isLeavingPage else { return }
                panelTransitioning = false
            }
        }
    }

    private func dismissPanel() {
        guard let closingPanel = panel, !panelTransitioning else { return }
        panelTransitioning = true
        panelTargetDetent = .closed
        panelDragStartHeight = nil
        panelDragStartDetent = nil
        panelAnimationToken = UUID()
        let token = panelAnimationToken
        let animation = reduceMotion ? Animation.easeOut(duration: 0.15) : .smooth(duration: 0.28)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            panelPresentationOpacity = 0
            if !reduceMotion {
                panelVisibleHeight = 0
            }
        } completion: {
            guard panelAnimationToken == token, !isLeavingPage else { return }
            withTransaction(Transaction(animation: nil)) {
                panelVisibleHeight = 0
                panel = nil
            }
            Task { @MainActor in
                await handlePanelDismissal(closedPanel: closingPanel)
            }
        }
    }

    private func handlePanelDismissal(closedPanel: ShortDramaPanel) async {
        guard !isLeavingPage else { return }
        await model.setEpisodesPresented(false)
        panelVisibleHeight = 0
        panelTargetDetent = .closed
        panelDragStartHeight = nil
        panelDragStartDetent = nil
        panelTransitioning = false
        guard !isLeavingPage else { return }
        if resumeSelectedEpisodeAfterPanel {
            resumeSelectedEpisodeAfterPanel = false
            resumeAfterPanel = false
            panelPlaybackID = nil
            if scenePhase == .active {
                playerController.setDesiredPlayback(true)
                wasPlayingBeforeBackground = false
            } else {
                wasPlayingBeforeBackground = true
            }
            restoreAccessibilityFocus(for: closedPanel)
            return
        }
        let canResumeSameEpisode = resumeAfterPanel
            && panelPlaybackID == model.playback?.id
            && !model.hasFinished
            && (panelPlaybackID != nil || model.isLoading)
        let canResumeFollowingEpisode = resumeAfterPanel
            && panelPlaybackID != model.playback?.id
            && !model.hasFinished
            && model.selectedEpisodeID != nil
            && (model.playback != nil || model.isLoading)
        resumeAfterPanel = false
        panelPlaybackID = nil
        let shouldResume = canResumeSameEpisode || canResumeFollowingEpisode
        if shouldResume {
            if scenePhase == .active {
                playerController.play()
                wasPlayingBeforeBackground = false
            } else {
                wasPlayingBeforeBackground = true
            }
        } else {
            wasPlayingBeforeBackground = false
        }
        restoreAccessibilityFocus(for: closedPanel)
    }

    private func restoreAccessibilityFocus(for closedPanel: ShortDramaPanel) {
        switch closedPanel {
        case .episodes: accessibilityFocus = .episodesTrigger
        case .settings: accessibilityFocus = .settingsTrigger
        }
    }

    private func chooseEpisode(_ id: String) {
        let isSameActiveEpisode = id == model.selectedEpisodeID
            && (model.playback != nil || model.isLoading)
            && !model.hasFinished
        guard !isSameActiveEpisode else {
            dismissPanel()
            return
        }

        resumeAfterPanel = false
        resumeSelectedEpisodeAfterPanel = scenePhase == .active
        playerController.setDesiredPlayback(false, applyImmediately: false)
        dismissPanel()
        Task { @MainActor in
            await model.selectEpisode(id: id)
        }
    }

    private var panelDetentAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28)
    }

    private func togglePlayback() {
        guard !episodeSwipeHoldActive, !episodeSwipeTransitioning else { return }
        if model.hasFinished, let id = model.selectedEpisodeID {
            playerController.setDesiredPlayback(true, applyImmediately: false)
            Task { await model.selectEpisode(id: id) }
        } else if model.playback == nil, let id = model.selectedEpisodeID {
            playerController.setDesiredPlayback(true, applyImmediately: false)
            Task { await model.selectEpisode(id: id) }
        } else if isPlaying {
            playerController.pause()
        } else {
            playerController.play()
        }
    }

    private func retry() {
        playerController.setDesiredPlayback(scenePhase == .active, applyImmediately: false)
        if let id = model.selectedEpisodeID {
            Task { await model.selectEpisode(id: id) }
        } else {
            Task { await model.load() }
        }
    }

    private func changeEpisode(by offset: Int) {
        guard !episodeSwipeHoldActive, !episodeSwipeTransitioning else { return }
        guard let id = model.selectedEpisodeID,
              let index = model.episodes.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard model.episodes.indices.contains(target) else {
            showBoundary(offset < 0 ? "已经是第一集" : "已经是最后一集")
            return
        }
        let next = model.episodes[target]
        guard next.id != id else { return }
        playerController.setDesiredPlayback(scenePhase == .active, applyImmediately: false)
        Task { await model.selectEpisode(id: next.id) }
    }

    private func showBoundary(_ message: String) {
        let token = UUID()
        boundaryMessageToken = token
        boundaryMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard boundaryMessageToken == token else { return }
            boundaryMessage = nil
        }
    }

    private func observePlaybackTime(isActive: Bool) async {
        guard isActive, model.playback != nil else {
            currentTime = 0
            duration = 0
            seekValue = 0
            isPlaying = false
            return
        }
        while !Task.isCancelled {
            if let sample = playerController.timeSample(for: model.playback?.id) {
                let validDuration = sample.duration.isFinite && sample.duration > 0 ? sample.duration : 0
                let validCurrent = model.hasFinished ? validDuration
                    : (sample.current.isFinite ? max(sample.current, 0) : 0)
                duration = validDuration
                currentTime = validDuration > 0 ? min(validCurrent, validDuration) : validCurrent
                if !isSeeking { seekValue = min(currentTime, max(validDuration, 1)) }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wasPlayingBeforeBackground = (panel != nil || panelTransitioning)
                ? resumeAfterPanel || resumeSelectedEpisodeAfterPanel
                : playerController.wantsPlayback
            cancelEpisodeSwipe()
            playerController.pause()
        case .active:
            guard wasPlayingBeforeBackground else { return }
            wasPlayingBeforeBackground = false
            guard panel == nil, !model.hasFinished else { return }
            playerController.play()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time > 0 else { return "00:00" }
        let totalSeconds = Int(time.rounded(.down))
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3_600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", totalSeconds / 60, seconds)
    }

    private var controlGlassCircle: some View {
        Group {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .circle)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
    }

    private var controlGlassCapsule: some View {
        Group {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
    }
}

enum ShortDramaAccessibilityFocus: Hashable {
    case episodesTrigger
    case settingsTrigger
    case speedTrigger
    case episodesTitle
    case settingsTitle
}

enum ShortDramaPanel: String, Identifiable, Equatable {
    case episodes
    case settings

    var id: String { rawValue }

    var closeAccessibilityLabel: String {
        switch self {
        case .episodes: "关闭选集"
        case .settings: "关闭播放设置"
        }
    }
}

private struct PlaybackObservationKey: Equatable {
    let playbackID: UUID?
    let isActive: Bool
}

private struct ShortDramaEpisodeSwipeGestureState: Equatable {
    var isVerticalLocked = false
    var rawVerticalTranslation: CGFloat = 0
    var verticalOffset: CGFloat = 0

    static let zero = Self()
}

@MainActor
@Observable
private final class ShortDramaPlayerController {
    private(set) var coordinator: KSVideoPlayer.Coordinator?
    private(set) var playbackID: UUID?

    func attach(_ coordinator: KSVideoPlayer.Coordinator, playbackID: UUID) {
        self.coordinator = coordinator
        self.playbackID = playbackID
    }

    private(set) var wantsPlayback = true

    func setDesiredPlayback(_ wantsPlayback: Bool, applyImmediately: Bool = true) {
        self.wantsPlayback = wantsPlayback
        guard applyImmediately else { return }
        if wantsPlayback { play() } else { pause() }
    }

    func detach(playbackID: UUID) {
        guard self.playbackID == playbackID else { return }
        coordinator = nil
        self.playbackID = nil
    }

    func pause() {
        wantsPlayback = false
        coordinator?.playerLayer?.pause()
    }

    func play() {
        wantsPlayback = true
        coordinator?.playerLayer?.play()
    }

    func stop() {
        // resetPlayer releases its layer and stops it once; KSPlayer stop is not idempotent.
        coordinator?.resetPlayer()
        coordinator = nil
        playbackID = nil
        wantsPlayback = false
    }

    func setRate(_ rate: Float) {
        coordinator?.playbackRate = rate
    }

    func seek(to time: Double, autoPlay: Bool) {
        guard let layer = coordinator?.playerLayer,
              layer.player.duration.isFinite,
              layer.player.duration > 0,
              layer.player.seekable else { return }
        layer.seek(
            time: min(max(time, 0), layer.player.duration),
            autoPlay: autoPlay
        )
    }

    func isSeekable(for playbackID: UUID?) -> Bool {
        guard let playbackID,
              playbackID == self.playbackID,
              let player = coordinator?.playerLayer?.player else { return false }
        return player.seekable && player.duration.isFinite && player.duration > 0
    }

    func synchronize(layer: KSPlayerLayer, state: KSPlayerState) {
        if wantsPlayback {
            if (state == .readyToPlay || state == .paused), !layer.player.isPlaying {
                layer.play()
            }
        } else if layer.player.isPlaying {
            layer.pause()
        }
    }

    func timeSample(for playbackID: UUID?) -> (current: Double, duration: Double)? {
        guard let playbackID,
              playbackID == self.playbackID,
              let player = coordinator?.playerLayer?.player else { return nil }
        return (player.currentPlaybackTime, player.duration)
    }
}

private struct ShortDramaPlayerSurface: View {
    let playback: ShortDramaPlayback
    let playbackRate: Float
    let desiredPlayback: Bool
    let model: ShortDramaPlaybackModel
    let controller: ShortDramaPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let onReady: (UUID) -> Void
    let onPlayingChanged: (UUID, Bool) -> Void
    let onVideoSize: (UUID, CGSize) -> Void

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var title = ""
    @State private var options: KSOptions
    @State private var didReportReady = false

    init(
        playback: ShortDramaPlayback,
        playbackRate: Float,
        desiredPlayback: Bool,
        model: ShortDramaPlaybackModel,
        controller: ShortDramaPlayerController,
        playbackSession: KSPlayerPlaybackSession,
        onReady: @escaping (UUID) -> Void,
        onPlayingChanged: @escaping (UUID, Bool) -> Void,
        onVideoSize: @escaping (UUID, CGSize) -> Void
    ) {
        self.playback = playback
        self.playbackRate = playbackRate
        self.desiredPlayback = desiredPlayback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.onReady = onReady
        self.onPlayingChanged = onPlayingChanged
        self.onVideoSize = onVideoSize

        let options = KSOptions()
        options.isAutoPlay = desiredPlayback
        options.isLoopPlay = false
        options.registerRemoteControll = false
        options.startPlayRate = playbackRate
        _options = State(initialValue: options)
        _ = KSPlayerSessionConfigurator.apply(
            quality: playback.quality,
            to: options,
            fallbackUserAgent: "libmpv",
            liveReconnectPolicy: .applicationManaged
        )
    }

    var body: some View {
        KSCorePlayerView(
            config: coordinator,
            url: playback.url,
            options: options,
            title: $title,
            subtitleDataSource: nil,
            onPlaybackStateChanged: handlePlayerState,
            onPlaybackFinished: handlePlaybackFinished
        )
        .background(Color.black)
        .onAppear {
            coordinator.playbackRate = playbackRate
            controller.attach(coordinator, playbackID: playback.id)
        }
        .onChange(of: playbackRate) { _, newValue in
            coordinator.playbackRate = newValue
        }
        .onDisappear {
            coordinator.resetPlayer()
            controller.detach(playbackID: playback.id)
        }
    }

    private func handlePlayerState(_ layer: KSPlayerLayer, _ state: KSPlayerState) {
        guard model.playback?.id == playback.id,
              controller.playbackID == playback.id,
              layer === coordinator.playerLayer else { return }
        layer.player.contentMode = .scaleAspectFit
        playbackSession.attach(playerLayer: layer)
        playbackSession.activate()
        layer.player.playbackRate = playbackRate
        controller.synchronize(layer: layer, state: state)
        reportVideoSizeIfReady(from: layer)
        if !didReportReady && (
            state == .bufferFinished
                || (state == .paused && layer.player.loadState == .playable)
        ) {
            didReportReady = true
            onReady(playback.id)
        }
        onPlayingChanged(playback.id, layer.player.isPlaying)
    }

    private func reportVideoSizeIfReady(from layer: KSPlayerLayer) {
        guard let naturalSize = PlayerVideoGeometry.readyNaturalSize(of: layer) else { return }
        onVideoSize(playback.id, naturalSize)
    }

    private func handlePlaybackFinished(_ layer: KSPlayerLayer, _ error: Error?) {
        guard model.playback?.id == playback.id,
              controller.playbackID == playback.id,
              layer === coordinator.playerLayer else { return }
        onPlayingChanged(playback.id, false)
        Task { @MainActor in
            await model.playbackFinished(id: playback.id, error: error)
        }
    }
}

#else
struct ShortDramaPlayerView: View {
    let room: LiveModel

    var body: some View {
        LiveDetailPlayerView(viewModel: RoomInfoViewModel(room: room))
    }
}
#endif
