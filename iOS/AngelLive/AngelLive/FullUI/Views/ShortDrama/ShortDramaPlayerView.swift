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
    @State private var seekValue = 0.0
    @State private var isSeeking = false
    @State private var playbackRate: Float = 1
    @State private var panel: ShortDramaPanel?
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
    @State private var panelHeaderDragOffset: CGFloat = 0
    @State private var panelHeaderDragActive = false
    @State private var panelHeaderDismissalAnimating = false
    @State private var panelAnimationToken = UUID()
    @ScaledMetric(relativeTo: .headline) private var titleFontSize: CGFloat = 17
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
            ZStack {
                Color.black.ignoresSafeArea()

                playbackSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: playbackSurfaceOffset)
                    .opacity(playbackSurfaceOpacity)
                    .accessibilityHidden(panel != nil || panelTransitioning)

                episodeInteractionLayer(availableHeight: geometry.size.height)
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
                   !episodeSwipeTransitioning {
                    if panel == nil && !panelTransitioning {
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
                        .accessibilityHidden(panel != nil || panelTransitioning)
                    }
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
                topControls
                    .padding(.top, max(8, geometry.safeAreaInsets.top + 4))
                    .padding(.horizontal, 16)
                    .allowsHitTesting(panel == nil && !panelTransitioning && !episodeSwipeHoldActive && !episodeSwipeTransitioning)
                    .accessibilityHidden(panel != nil || panelTransitioning || episodeSwipeHoldActive || episodeSwipeTransitioning)
            }
            .overlay(alignment: .bottom) {
                bottomControls(bottomInset: geometry.safeAreaInsets.bottom)
                    .opacity(panel != nil || panelTransitioning ? 0 : 1)
                    .allowsHitTesting(panel == nil && !panelTransitioning && !episodeSwipeHoldActive && !episodeSwipeTransitioning)
                    .accessibilityHidden(panel != nil || panelTransitioning || episodeSwipeHoldActive || episodeSwipeTransitioning)
            }
            .overlay {
                if let selectedPanel = panel {
                    panelOverlay(selectedPanel, geometry: geometry)
                        .zIndex(10)
                }
            }
            .ignoresSafeArea()
            .background(Color.black)
            .onChange(of: geometry.size) { _, _ in
                cancelEpisodeSwipe()
                cancelPanelHeaderDrag()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: panel?.id) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in
                await Task.yield()
                accessibilityFocus = newValue == ShortDramaPanel.episodes.id ? .episodesTitle : .settingsTitle
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
        .onChange(of: model.playback?.id) { _, newValue in
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
            panelHeaderDragOffset = 0
            panelHeaderDragActive = false
            invalidateEpisodeSwipe()
            model.cancel()
            playerController.stop()
            playbackSession.invalidate(releasingResources: false)
        }
    }

    private var playbackSurface: some View {
        ZStack {
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
                    onPlayingChanged: handlePlayingChanged
                )
                .id(playback.id)
                .opacity(readyPlaybackID == playback.id ? 1 : 0)
                .transition(.opacity)
            }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .animation(.easeOut(duration: 0.15), value: model.playback?.id)
        .animation(.easeOut(duration: 0.15), value: readyPlaybackID)
    }

    private var isPreparingPlayback: Bool {
        guard model.errorMessage == nil else { return false }
        if model.isLoading { return true }
        guard let playbackID = model.playback?.id else { return false }
        return readyPlaybackID != playbackID
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

    private var topControls: some View {
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
                present(.settings)
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

    private func bottomControls(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.56), location: 0.42),
                    .init(color: .black.opacity(0.92), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .overlay(alignment: .bottom) {
                VStack(spacing: 5) {
                    progressControl
                    episodeMetadata
                    episodeDock
                }
                .padding(.horizontal, 16)
                .padding(.bottom, max(bottomInset, 8))
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }

    private var progressControl: some View {
        HStack(spacing: 8) {
            if !isPlaying || isSeeking {
                Text(formatTime(isSeeking ? seekValue : currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(minWidth: 34, alignment: .leading)
                    .accessibilityHidden(true)
            }

            Slider(
                value: $seekValue,
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing, canSeek {
                        playerController.seek(to: min(max(seekValue, 0), duration), autoPlay: isPlaying)
                    }
                }
            )
            .tint(.white)
            .frame(height: 44)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(formatTime(currentTime)) / \(formatTime(duration))")
            .disabled(!canSeek)

            if !isPlaying || isSeeking {
                Text(formatTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(minWidth: 34, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
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

    private var episodeDock: some View {
        Button {
            present(.episodes)
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

    private var episodeDockAccessibilityLabel: String {
        guard let episode = model.selectedEpisode else { return "选择剧集" }
        return "选集，第 \(episode.number) 集，可播 \(model.episodes.count) 集"
    }

    private var canSeek: Bool {
        duration.isFinite && duration > 0 && playerController.isSeekable(for: model.playback?.id)
    }

    @ViewBuilder
    private func panelContent(
        _ selectedPanel: ShortDramaPanel,
        safeBottom: CGFloat,
        panelHeight: CGFloat,
        panelWidth: CGFloat
    ) -> some View {
        switch selectedPanel {
        case .episodes:
            ShortDramaEpisodesSheet(
                room: room,
                model: model,
                onClose: dismissPanel,
                onSelect: chooseEpisode,
                onHeaderDragChanged: { updatePanelHeaderDrag($0) },
                onHeaderDragEnded: { finishPanelHeaderDrag($0, panelHeight: panelHeight) },
                availableWidth: panelWidth,
                accessibilityFocus: $accessibilityFocus
            )
            .padding(.bottom, max(safeBottom, 12) + 12)
        case .settings:
            ShortDramaSettingsSheet(
                playbackRate: $playbackRate,
                autoplay: Binding(get: { model.autoplay }, set: { model.autoplay = $0 }),
                onClose: dismissPanel,
                onHeaderDragChanged: { updatePanelHeaderDrag($0) },
                onHeaderDragEnded: { finishPanelHeaderDrag($0, panelHeight: panelHeight) },
                accessibilityFocus: $accessibilityFocus
            )
            .padding(.bottom, max(safeBottom, 12) + 12)
        }
    }

    private func panelOverlay(_ selectedPanel: ShortDramaPanel, geometry: GeometryProxy) -> some View {
        let safeArea = geometry.safeAreaInsets
        let screenHeight = geometry.size.height + safeArea.top + safeArea.bottom
        let requestedHeight = dynamicTypeSize.isAccessibilitySize
            ? screenHeight * 0.82
            : max(420, screenHeight * 0.52)
        let panelHeight = min(requestedHeight, max(0, screenHeight - safeArea.top - 12))
        let panelWidth = UIDevice.current.userInterfaceIdiom == .pad
            ? min(geometry.size.width, 560)
            : geometry.size.width
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 28,
            style: .continuous
        )

        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.28 * max(0, 1 - panelHeaderDragOffset / max(panelHeight, 1)))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissPanel)
                .accessibilityHidden(true)
                .transition(.opacity)

            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.34))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .panelHeaderDrag(onChanged: updatePanelHeaderDrag) {
                        finishPanelHeaderDrag($0, panelHeight: panelHeight)
                    }
                    .accessibilityHidden(true)

                panelContent(
                    selectedPanel,
                    safeBottom: safeArea.bottom,
                    panelHeight: panelHeight,
                    panelWidth: panelWidth
                )
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: panelWidth, height: panelHeight, alignment: .top)
            .contentShape(shape)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .clipShape(shape)
            .offset(y: reduceMotion ? 0 : panelHeaderDragOffset)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                dismissPanel()
            }
            .onKeyPress(.escape) {
                dismissPanel()
                return .handled
            }
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }

    private func updatePanelHeaderDrag(_ value: DragGesture.Value) {
        guard panel != nil,
              !panelTransitioning,
              !isLeavingPage,
              value.translation.height > 0,
              abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
        panelHeaderDragActive = true
        panelHeaderDragOffset = max(0, value.translation.height)
    }

    private func finishPanelHeaderDrag(_ value: DragGesture.Value, panelHeight: CGFloat) {
        guard panelHeaderDragActive,
              panel != nil,
              !panelTransitioning,
              !isLeavingPage else { return }
        panelHeaderDragActive = false
        let velocityCloses = value.translation.height > 0 && value.velocity.height >= 650
        guard value.translation.height >= 80 || velocityCloses else {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.28, bounce: 0.08)) {
                panelHeaderDragOffset = 0
            }
            return
        }
        if reduceMotion {
            dismissPanel()
            return
        }
        dismissPanelFromHeaderDrag(
            panelHeight: panelHeight,
            startingOffset: max(panelHeaderDragOffset, value.translation.height)
        )
    }

    private func cancelPanelHeaderDrag() {
        if panelHeaderDismissalAnimating {
            panelAnimationToken = UUID()
            panelHeaderDismissalAnimating = false
            panelTransitioning = false
        }
        guard panelHeaderDragActive || panelHeaderDragOffset != 0 else { return }
        panelHeaderDragActive = false
        withTransaction(Transaction(animation: nil)) {
            panelHeaderDragOffset = 0
        }
    }

    private func present(_ selectedPanel: ShortDramaPanel) {
        guard panel == nil,
              !panelTransitioning,
              !episodeSwipeHoldActive,
              !episodeSwipeTransitioning else { return }
        panelAnimationToken = UUID()
        panelHeaderDragOffset = 0
        panelTransitioning = true
        resumeAfterPanel = playerController.wantsPlayback && scenePhase == .active
        panelPlaybackID = model.playback?.id
        playerController.pause()
        let token = panelAnimationToken
        Task { @MainActor in
            await model.setEpisodesPresented(true)
            guard !isLeavingPage, panelAnimationToken == token else { return }
            withAnimation(panelOpenAnimation) {
                panel = selectedPanel
                panelTransitioning = false
            }
        }
    }

    private func dismissPanel() {
        guard let closingPanel = panel, !panelTransitioning else { return }
        panelTransitioning = true
        panelAnimationToken = UUID()
        let token = panelAnimationToken
        withAnimation(
            panelCloseAnimation,
            completionCriteria: .removed
        ) {
            panel = nil
        } completion: {
            guard panelAnimationToken == token else { return }
            Task { @MainActor in
                await handlePanelDismissal(closedPanel: closingPanel)
            }
        }
    }

    private func dismissPanelFromHeaderDrag(panelHeight: CGFloat, startingOffset: CGFloat) {
        guard let closingPanel = panel, !panelTransitioning else { return }
        panelTransitioning = true
        panelHeaderDismissalAnimating = true
        panelAnimationToken = UUID()
        let token = panelAnimationToken
        withTransaction(Transaction(animation: nil)) {
            panelHeaderDragOffset = startingOffset
        }
        withAnimation(panelCloseAnimation, completionCriteria: .logicallyComplete) {
            panelHeaderDragOffset = max(panelHeight, startingOffset)
        } completion: {
            guard panelAnimationToken == token else { return }
            panelHeaderDismissalAnimating = false
            withTransaction(Transaction(animation: nil)) {
                panel = nil
                panelHeaderDragOffset = 0
            }
            Task { @MainActor in
                await handlePanelDismissal(closedPanel: closingPanel)
            }
        }
    }

    private func handlePanelDismissal(closedPanel: ShortDramaPanel) async {
        guard !isLeavingPage else { return }
        await model.setEpisodesPresented(false)
        panelHeaderDragOffset = 0
        panelHeaderDragActive = false
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
        accessibilityFocus = closedPanel == .episodes ? .episodesTrigger : .settingsTrigger
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

    private var panelOpenAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28)
    }

    private var panelCloseAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.24)
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
            cancelPanelHeaderDrag()
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

private enum ShortDramaAccessibilityFocus: Hashable {
    case episodesTrigger
    case settingsTrigger
    case episodesTitle
    case settingsTitle
}

private enum ShortDramaPanel: String, Identifiable, Equatable {
    case episodes
    case settings

    var id: String { rawValue }
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

private extension View {
    func panelHeaderDrag(
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping (DragGesture.Value) -> Void
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged(onChanged)
                .onEnded(onEnded)
        )
    }
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
        onPlayingChanged: @escaping (UUID, Bool) -> Void
    ) {
        self.playback = playback
        self.playbackRate = playbackRate
        self.desiredPlayback = desiredPlayback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.onReady = onReady
        self.onPlayingChanged = onPlayingChanged

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
        if !didReportReady && (
            state == .bufferFinished
                || (state == .paused && layer.player.loadState == .playable)
        ) {
            didReportReady = true
            onReady(playback.id)
        }
        onPlayingChanged(playback.id, layer.player.isPlaying)
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

private struct ShortDramaEpisodesSheet: View {
    let room: LiveModel
    let model: ShortDramaPlaybackModel
    let onClose: () -> Void
    let onSelect: (String) -> Void
    let onHeaderDragChanged: (DragGesture.Value) -> Void
    let onHeaderDragEnded: (DragGesture.Value) -> Void
    let availableWidth: CGFloat
    @AccessibilityFocusState.Binding var accessibilityFocus: ShortDramaAccessibilityFocus?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let interiorWidth = max(44, availableWidth - 40)
        let widthBasedCount = max(1, Int((interiorWidth + 8) / 52))
        let preferredCount = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        let count = min(preferredCount, widthBasedCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                poster
                    .frame(width: 60, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(room.roomTitle.isEmpty ? room.userName : room.roomTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($accessibilityFocus, equals: .episodesTitle)
                    Text("可播 \(model.episodes.count) 集")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    if let providerName = model.selectedEpisode?.cdn.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !providerName.isEmpty {
                        Text(providerName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    } else if let note = model.selectionNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭选集")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .panelHeaderDrag(onChanged: onHeaderDragChanged, onEnded: onHeaderDragEnded)

            HStack(spacing: 8) {
                Text("剧集列表")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("可播 \(model.episodes.count) 集")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.episodes) { episode in
                        episodeCell(episode)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = URL(string: room.roomCover), !room.roomCover.isEmpty {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }
        }
    }

    private func episodeCell(_ episode: ShortDramaEpisode) -> some View {
        let isSelected = episode.id == model.selectedEpisodeID
        return Button {
            onSelect(episode.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text("\(episode.number)")
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isSelected {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 48)
            .background(isSelected ? .white.opacity(0.12) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? .white : .white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "第 \(episode.number) 集，当前集" : "第 \(episode.number) 集")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
private struct ShortDramaSettingsSheet: View {
    @Binding var playbackRate: Float
    @Binding var autoplay: Bool
    let onClose: () -> Void
    let onHeaderDragChanged: (DragGesture.Value) -> Void
    let onHeaderDragEnded: (DragGesture.Value) -> Void
    @AccessibilityFocusState.Binding var accessibilityFocus: ShortDramaAccessibilityFocus?

    private let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("播放设置")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($accessibilityFocus, equals: .settingsTitle)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭播放设置")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .panelHeaderDrag(onChanged: onHeaderDragChanged, onEnded: onHeaderDragEnded)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("播放速度")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(rates, id: \.self) { rate in
                                Button {
                                    playbackRate = rate
                                } label: {
                                    Text(rateLabel(rate))
                                        .font(.body.weight(playbackRate == rate ? .semibold : .regular))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(playbackRate == rate ? .white.opacity(0.14) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(playbackRate == rate ? .white.opacity(0.9) : .white.opacity(0.08), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(rateLabel(rate)) 倍速")
                                .accessibilityAddTraits(playbackRate == rate ? .isSelected : [])
                            }
                        }
                    }

                    Toggle(isOn: $autoplay) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动连播")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                            Text("本集结束后播放下一集")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                    .frame(minHeight: 52)
                    .accessibilityHint("控制本集结束后是否自动播放下一集")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func rateLabel(_ rate: Float) -> String {
        if rate == 1 { return "1×" }
        return "\(rate)×"
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
