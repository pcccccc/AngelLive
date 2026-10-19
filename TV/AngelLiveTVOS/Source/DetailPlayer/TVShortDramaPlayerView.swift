import SwiftUI
import SharedAssets
import Observation
import AngelLiveCore
import AngelLiveDependencies

/// FullUI opts in only when the selected installed plugin declares both fields.
@MainActor
enum TVShortDramaRoute {
    static func matches(room: LiveModel, appViewModel: AppState) -> Bool {
        #if canImport(KSPlayer)
        guard appViewModel.pluginAvailability.hasAvailablePlugins,
              let platform = SandboxPluginCatalog.platform(for: room.liveType),
              let behavior = try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId).manifest.hostBehavior else {
            return false
        }
        return behavior.contentKind == "shortDrama" && behavior.episodeSelection == "qualityList"
        #else
        return false
        #endif
    }
}

#if canImport(KSPlayer)

/// Television playback uses the existing control capsules and right-hand selection panel.
struct TVShortDramaPlayerView: View {
    let room: LiveModel
    let onExit: () -> Void

    @State private var model: ShortDramaPlaybackModel
    @State private var controller = KSShortDramaPlayerController()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary, supportedGlobalCapabilities: [.audioFocus]
    )
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedControl: Control?
    @State private var panel: TVShortDramaPanelKind?
    @State private var showsEpisodeGroups = false
    @State private var panelGeneration = UUID()
    @State private var isClosingPanel = false
    @State private var showsControls = true
    @State private var playbackRate: Float = 1
    @State private var didLoadInitialCatalog = false
    @State private var isPreparing = true
    @State private var wantsPreparedPlayback = true
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var isSeeking = false
    @State private var resumeAfterSeek = false
    @State private var seekTask: Task<Void, Never>?
    @State private var showsFeedback = false
    @State private var feedbackMessage = ""
    @State private var resumeAfterPanel = false
    @State private var resumeAfterBackground = false
    @State private var isSuspended = false
    @State private var didCleanup = false
    @State private var operation: Task<Void, Never>?
    @State private var panelOperation: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    private enum Control: Hashable {
        case reveal, playPause, previous, next, backward, forward, episodes, settings, retry, exit
    }

    init(room: LiveModel, onExit: @escaping () -> Void) {
        self.room = room
        self.onExit = onExit
        _model = State(initialValue: ShortDramaPlaybackModel(room: room))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let playback = model.playback {
                    TVShortDramaPlayerSurface(
                        playback: playback, rate: playbackRate, desiredPlayback: shouldPlayPreparedMedia, model: model,
                        controller: controller, playbackSession: playbackSession,
                        onReady: playbackReady,
                        onCompleted: { wantsPreparedPlayback = true }
                    )
                    .id(playback.id)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                if !didLoadInitialCatalog || model.isLoading || (model.playback != nil && isPreparing) {
                    VStack(spacing: 22) {
                        ProgressView()
                            .fullUIArcLoadingStyle(size: 64, lineWidth: 2.5)
                            .tint(.white)
                        Text(model.selectedEpisode?.title ?? "正在获取剧集")
                            .font(.title3).foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
                }

                if panel == nil, !isClosingPanel {
                    if let message = model.errorMessage {
                        statusView(title: "播放失败", message: message)
                    } else if showsStatus {
                        statusView(title: "暂无可播放剧集", message: "插件尚未提供分集内容")
                    } else if showsControls {
                        controls
                    } else {
                        Button { revealControls() } label: {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(TVFullUIHiddenControlButtonStyle())
                        .focused($focusedControl, equals: .reveal)
                        .accessibilityLabel("显示播放控制")
                        .onMoveCommand { _ in revealControls() }
                    }
                }

                if let panel {
                    HStack {
                        Spacer()
                        TVShortDramaSelectionPanel(
                            kind: panel, model: model, rate: $playbackRate,
                            showsEpisodeGroups: $showsEpisodeGroups,
                            onSelect: selectEpisode, onClose: closePanel
                        )
                        .frame(width: min(geometry.size.width * 0.4, 640), height: max(0, geometry.size.height - 80))
                        .padding(.vertical, 40)
                        .padding(.trailing, 48)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }
                    .zIndex(2)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            await model.load()
            guard !Task.isCancelled, !didCleanup else { return }
            didLoadInitialCatalog = true
        }
        .task(id: model.playback?.id) { await observeTime() }
        .onAppear {
            playbackSession.register()
            focusedControl = defaultControl
            scheduleHide()
        }
        .onChange(of: model.playback?.id) { _, _ in
            seekTask?.cancel()
            seekTask = nil
            isSeeking = false
            currentTime = 0
            duration = 0
            isPreparing = true
            if model.playback != nil {
                controller.setDesiredPlayback(shouldPlayPreparedMedia,
                                              applyImmediately: controller.playbackID == model.playback?.id)
                if panel == nil, !isClosingPanel, showsControls {
                    focusedControl = .playPause
                }
                scheduleHide()
            }
        }
        .onChange(of: controller.wantsPlayback) { _, wantsPlayback in
            if !wantsPlayback { persistCurrentProgress() }
        }
        .onChange(of: model.progressWarning) { _, message in
            if let message { showFeedback(message) }
        }
        .simpleToast(isPresented: $showsFeedback,
                     options: SimpleToastOptions(alignment: .topLeading, hideAfter: 1.5)) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: "xmark.circle").font(.headline.bold())
                Text(feedbackMessage)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .onChange(of: model.hasFinished) { _, finished in
            if finished { revealControls() }
        }
        .onChange(of: model.errorMessage) { _, message in
            if message != nil { revealControls() }
        }
        .onChange(of: showsStatus) { _, visible in
            if visible { revealControls() }
            else if panel == nil, !isClosingPanel, showsControls { focusedControl = defaultControl }
        }
        .onChange(of: playbackRate) { _, rate in controller.setRate(rate) }
        .onChange(of: focusedControl) { _, control in
            if control != .reveal { scheduleHide() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persistCurrentProgress()
                if !isSuspended {
                    resumeAfterBackground = isSeeking ? resumeAfterSeek : (panel == nil ? controller.wantsPlayback : resumeAfterPanel)
                    isSuspended = true
                }
                controller.setDesiredPlayback(false)
                hideTask?.cancel()
            } else {
                isSuspended = false
                if panel == nil, !isClosingPanel, !isSeeking, !model.hasFinished {
                    controller.setDesiredPlayback(resumeAfterBackground)
                }
                scheduleHide()
            }
        }
        .onExitCommand(perform: handleBackCommand)
        .onKeyPress(.escape, phases: .all) { press in
            // Consume down/repeat as well, so one native key cannot return twice.
            if press.phase == .up { handleBackCommand() }
            return .handled
        }
        .onPlayPauseCommand {
            guard panel == nil, !isClosingPanel else { return }
            togglePlayback()
        }
        .onDisappear { cleanup() }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(room.roomTitle.isEmpty ? room.userName : room.roomTitle)
                        .font(.title3).lineLimit(2)
                    if let episode = model.selectedEpisode {
                        Text(episode.title).font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 70).padding(.top, 40).padding(.bottom, 60)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            VStack(spacing: 24) {
                if let note = model.selectionNote {
                    Text(note).font(.title3).foregroundStyle(.white.opacity(0.8))
                }
                HStack(spacing: 20) {
                    Text(timeLabel(currentTime)).monospacedDigit()
                    ProgressView(value: min(max(currentTime, 0), max(duration, 1)), total: max(duration, 1))
                        .tint(.white)
                        .accessibilityLabel("播放进度")
                        .accessibilityValue("\(timeLabel(currentTime))，总时长\(timeLabel(duration))")
                    Text(timeLabel(duration)).monospacedDigit()
                }
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 24) {
                    HStack(spacing: TVFullUIPlayerControlMetrics.spacing) {
                        controlButton("上一集", symbol: "backward.end.fill", control: .previous) { moveEpisode(-1) }
                            .disabled(adjacentEpisode(-1) == nil)
                        controlButton("后退15秒", symbol: "gobackward.15", control: .backward) { seek(-15) }
                            .disabled(!canSeek)
                        controlButton(model.hasFinished ? "重播本集" : controller.wantsPlayback ? "暂停" : "继续播放",
                                      symbol: controller.wantsPlayback && !model.hasFinished ? "pause.fill" : "play.fill",
                                      control: .playPause, action: togglePlayback)
                            .disabled(model.playback == nil)
                        controlButton("前进15秒", symbol: "goforward.15", control: .forward) { seek(15) }
                            .disabled(!canSeek)
                        controlButton("下一集", symbol: "forward.end.fill", control: .next) { moveEpisode(1) }
                            .disabled(adjacentEpisode(1) == nil)
                    }
                    .modifier(TVFullUIPlayerControlGroupModifier(enabled: true, legacyInsets: EdgeInsets()))
                    .focusSection()

                    Spacer()

                    HStack(spacing: TVFullUIPlayerControlMetrics.spacing) {
                        Button { presentPanel(.episodes) } label: {
                            Label("选集", systemImage: "list.bullet")
                                .font(.system(size: 28, weight: .semibold))
                                .lineLimit(1)
                        }
                        .modifier(TVFullUIPlayerControlButtonModifier(enabled: true,
                                                                     isFocused: focusedControl == .episodes, shape: .capsule))
                        .focused($focusedControl, equals: .episodes)
                        .disabled(model.episodes.isEmpty)
                        Button { presentPanel(.settings) } label: {
                            Text("\(rateLabel(playbackRate)) · 设置")
                                .font(.system(size: 28, weight: .semibold))
                                .lineLimit(1)
                        }
                        .modifier(TVFullUIPlayerControlButtonModifier(enabled: true,
                                                                     isFocused: focusedControl == .settings, shape: .capsule))
                        .focused($focusedControl, equals: .settings)
                    }
                    .modifier(TVFullUIPlayerControlGroupModifier(enabled: true, legacyInsets: EdgeInsets()))
                    .focusSection()
                }
            }
            .padding(.horizontal, TVFullUIPlayerControlMetrics.screenInset)
            .padding(.bottom, TVFullUIPlayerControlMetrics.screenInset).padding(.top, 60)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private func controlButton(_ title: String, symbol: String, control: Control, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 30, weight: .bold))
                .frame(width: 40, height: 40)
        }
        .modifier(TVFullUIPlayerControlButtonModifier(enabled: true,
                                                     isFocused: focusedControl == control, shape: .circle))
        .focused($focusedControl, equals: control)
        .accessibilityLabel(title)
    }

    private var showsStatus: Bool {
        model.errorMessage != nil || (didLoadInitialCatalog && !model.isLoading && model.episodes.isEmpty)
    }

    private var shouldPlayPreparedMedia: Bool {
        wantsPreparedPlayback && scenePhase == .active && panel == nil && !isClosingPanel
    }

    private var defaultControl: Control {
        if showsStatus { return .retry }
        return model.playback == nil ? .settings : .playPause
    }

    private func statusView(title: String, message: String) -> some View {
        VStack(spacing: 30) {
            Image(systemName: "tv.slash").font(.system(size: 80)).foregroundStyle(.gray)
            Text(title).font(.title).foregroundStyle(.white)
            Text(message).font(.headline).foregroundStyle(.gray)
                .multilineTextAlignment(.center).frame(maxWidth: 900)
            HStack(spacing: 30) {
                Button("重试", action: retryPlayback)
                    .focused($focusedControl, equals: .retry)
                if !model.episodes.isEmpty {
                    Button("选集") { presentPanel(.episodes) }
                        .focused($focusedControl, equals: .episodes)
                }
                Button("返回", action: exit)
                    .focused($focusedControl, equals: .exit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private var canSeek: Bool {
        !isSeeking && controller.isSeekable(for: model.playback?.id)
    }

    private func seek(_ delta: Double) {
        guard canSeek, let id = model.playback?.id,
              model.beginScrubbing(playbackID: id) else { return }
        let target = min(max(0, currentTime + delta), duration)
        let sampledDuration = duration
        resumeAfterSeek = controller.wantsPlayback && !model.hasFinished
        let shouldResume = resumeAfterSeek
        isSeeking = true
        controller.pause()
        seekTask = Task { @MainActor in
            let succeeded = await controller.seek(to: target, playbackID: id)
            guard !Task.isCancelled, !didCleanup, model.playback?.id == id else { return }
            let canResume = shouldResume && !controller.playbackHasFailed(for: id)
            controller.setDesiredPlayback(canResume && shouldPlayPreparedMedia, applyImmediately: false)
            // Core owns any next-episode request started by settlement. A playback-ID
            // change must no longer cancel the task that is awaiting that request.
            seekTask = nil
            await model.completeScrubbing(
                playbackID: id, targetTime: target, duration: sampledDuration,
                seekSucceeded: succeeded, resumePlayback: canResume
            )
            guard !Task.isCancelled, !didCleanup, model.playback?.id == id else { return }
            if model.hasFinished { controller.pause() }
            isSeeking = false
            seekTask = nil
            if succeeded { currentTime = target }
            else { showFeedback("未能调整播放进度，请重试") }
            if canResume, shouldPlayPreparedMedia, !model.hasFinished { controller.play() }
            scheduleHide()
        }
        scheduleHide()
    }

    private func adjacentEpisode(_ offset: Int) -> ShortDramaEpisode? {
        guard let index = model.episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }),
              model.episodes.indices.contains(index + offset) else { return nil }
        return model.episodes[index + offset]
    }

    private func moveEpisode(_ offset: Int) {
        guard let target = adjacentEpisode(offset) else { return }
        selectEpisode(target.id)
    }

    private func selectEpisode(_ id: String) {
        // The model deliberately keeps the existing request for the loading target.
        // Do not cancel its parent task before taking that same-target no-op path.
        guard !didCleanup, !isClosingPanel,
              !(model.isLoading && model.selectedEpisodeID == id) else { return }
        persistCurrentProgress()
        let changesPlayback = id != model.selectedEpisodeID || model.hasFinished || model.playback == nil
        let selectedPanel = panel
        let presentationToken = panelGeneration
        operation?.cancel()
        operation = Task { @MainActor in
            guard !Task.isCancelled, !didCleanup else { return }
            if changesPlayback {
                wantsPreparedPlayback = true
                controller.setDesiredPlayback(scenePhase == .active && panel == nil, applyImmediately: false)
                await model.selectEpisode(id: id)
            }
            guard !Task.isCancelled, !didCleanup else { return }
            if selectedPanel != nil, presentationToken == panelGeneration {
                await dismissPanel(resuming: changesPlayback ? scenePhase == .active : resumeAfterPanel,
                                   generation: presentationToken)
            }
        }
    }

    private func togglePlayback() {
        guard !isSeeking else { return }
        if model.hasFinished, let id = model.selectedEpisodeID { selectEpisode(id); return }
        guard model.playback != nil || model.isLoading else { return }
        wantsPreparedPlayback = model.isLoading ? !wantsPreparedPlayback : !controller.wantsPlayback
        controller.setDesiredPlayback(wantsPreparedPlayback)
        revealControls()
    }

    private func retryPlayback() {
        guard !didCleanup, !model.isLoading else { return }
        operation?.cancel()
        operation = Task { @MainActor in
            guard !Task.isCancelled, !didCleanup else { return }
            wantsPreparedPlayback = true
            controller.setDesiredPlayback(scenePhase == .active, applyImmediately: false)
            if let id = model.selectedEpisodeID { await model.selectEpisode(id: id) }
            else { await model.load() }
            guard !Task.isCancelled, !didCleanup else { return }
            revealControls()
        }
    }

    private func presentPanel(_ kind: TVShortDramaPanelKind) {
        guard !didCleanup, panel == nil, !isClosingPanel, !isSeeking else { return }
        showsEpisodeGroups = false
        hideTask?.cancel()
        panelOperation?.cancel()
        panelGeneration = UUID()
        let token = panelGeneration
        panelOperation = Task { @MainActor in
            await model.setEpisodesPresented(true)
            guard !Task.isCancelled, !didCleanup, token == panelGeneration else { return }
            resumeAfterPanel = controller.wantsPlayback
            controller.setDesiredPlayback(false)
            focusedControl = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { panel = kind }
        }
    }

    private func closePanel() {
        guard panel != nil, !isClosingPanel else { return }
        panelOperation?.cancel()
        panelGeneration = UUID()
        let token = panelGeneration
        panelOperation = Task { @MainActor in
            await dismissPanel(resuming: resumeAfterPanel, generation: token)
        }
    }

    private func dismissPanel(resuming: Bool, generation: UUID) async {
        guard !Task.isCancelled, !didCleanup, generation == panelGeneration else { return }
        let closedPanel = panel
        isClosingPanel = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            panel = nil
            showsControls = true
        }
        // Keep the EOF hold until the outgoing panel is no longer covering the controls.
        if closedPanel != nil, !reduceMotion {
            try? await Task.sleep(for: .milliseconds(280))
        }
        guard !Task.isCancelled, !didCleanup, generation == panelGeneration, panel == nil else { return }
        controller.setDesiredPlayback(resuming && scenePhase == .active && !model.hasFinished)
        isClosingPanel = false
        focusedControl = showsStatus ? .retry : closedPanel == .settings ? .settings : .episodes
        scheduleHide()
        // Releasing a held EOF may await the next episode's network request. Restore
        // controls first, and don't let a later panel opening cancel that request.
        panelOperation = nil
        await model.setEpisodesPresented(false)
    }

    private func handleBackCommand() {
        guard !isClosingPanel, !didCleanup else { return }
        if panel == .episodes, showsEpisodeGroups { showsEpisodeGroups = false }
        else if panel != nil { closePanel() }
        else if showsControls, !showsStatus, model.playback != nil { hideControls() }
        else { exit() }
    }

    private func revealControls() {
        guard panel == nil, !isClosingPanel, !didCleanup else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsControls = true }
        focusedControl = defaultControl
        scheduleHide()
    }

    private func hideControls() {
        hideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsControls = false }
        focusedControl = .reveal
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard panel == nil, !isClosingPanel, !isPreparing, controller.wantsPlayback, !model.hasFinished,
              model.errorMessage == nil, model.playback != nil, scenePhase == .active else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !didCleanup, panel == nil else { return }
            hideControls()
        }
    }

    private func observeTime() async {
        let id = model.playback?.id
        while !Task.isCancelled, !didCleanup, id == model.playback?.id {
            controller.restoreIfPossible(model: model, onReady: playbackReady)
            if let sample = controller.timeSample(for: id) {
                currentTime = sample.current.isFinite ? max(0, sample.current) : 0
                duration = sample.duration.isFinite ? max(0, sample.duration) : 0
                if !isSeeking, let id {
                    model.playbackReady(id: id, duration: sample.duration)
                    model.recordProgress(id: id, position: sample.current, duration: sample.duration)
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func playbackReady(_ id: UUID) {
        guard model.playback?.id == id, !didCleanup else { return }
        model.playbackReady(id: id, duration: controller.timeSample(for: id)?.duration ?? 0)
        isPreparing = false
        scheduleHide()
    }

    private func persistCurrentProgress() {
        if !isSeeking, let id = model.playback?.id, let sample = controller.timeSample(for: id) {
            model.recordProgress(id: id, position: sample.current, duration: sample.duration)
        }
        model.flushProgress()
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        showsFeedback = true
    }

    private func cleanup() {
        guard !didCleanup else { return }
        persistCurrentProgress()
        didCleanup = true
        seekTask?.cancel()
        seekTask = nil
        hideTask?.cancel()
        operation?.cancel()
        panelOperation?.cancel()
        model.cancel()
        controller.stop()
        playbackSession.invalidate(releasingResources: false)
    }

    private func exit() { cleanup(); onExit() }
}

private enum TVShortDramaPanelKind { case episodes, settings }

private struct TVShortDramaSelectionPanel: View {
    let kind: TVShortDramaPanelKind
    let model: ShortDramaPlaybackModel
    @Binding var rate: Float
    @Binding var showsEpisodeGroups: Bool
    let onSelect: (String) -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Item?
    @State private var browseGroupID: String?
    @State private var didChooseGroup = false
    @State private var requestedFocus: Item?
    @State private var focusRequest = UUID()
    private enum Item: Hashable { case close, groupPicker, group(String), episode(String), rate(Float), autoplay }
    private let rates: [Float] = [0.75, 1, 1.25, 1.5, 2, 3]

    init(kind: TVShortDramaPanelKind, model: ShortDramaPlaybackModel, rate: Binding<Float>,
         showsEpisodeGroups: Binding<Bool>, onSelect: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.kind = kind
        self.model = model
        _rate = rate
        _showsEpisodeGroups = showsEpisodeGroups
        self.onSelect = onSelect
        self.onClose = onClose
        let groups = ShortDramaEpisodeGroup.make(from: model.episodes)
        _browseGroupID = State(initialValue: groups.first { $0.contains(episodeID: model.selectedEpisodeID) }?.id
            ?? groups.first?.id)
    }

    private var groups: [ShortDramaEpisodeGroup] { ShortDramaEpisodeGroup.make(from: model.episodes) }
    private var selectedGroup: ShortDramaEpisodeGroup? {
        groups.first { $0.id == browseGroupID }
            ?? groups.first { $0.contains(episodeID: model.selectedEpisodeID) }
            ?? groups.first
    }
    private var visibleEpisodes: [ShortDramaEpisode] { selectedGroup?.episodes ?? [] }
    private var initialFocus: Item {
        guard kind == .episodes else { return .rate(rate) }
        if selectedGroup?.contains(episodeID: model.selectedEpisodeID) == true,
           let id = model.selectedEpisodeID { return .episode(id) }
        return visibleEpisodes.first.map { .episode($0.id) } ?? .close
    }

    private func requestFocus(_ item: Item) {
        requestedFocus = item
        focusRequest = UUID()
    }

    private func chooseGroup(_ group: ShortDramaEpisodeGroup) {
        browseGroupID = group.id
        didChooseGroup = true
        showsEpisodeGroups = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind == .episodes ? "选集" : "播放设置")
                        .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white).frame(width: 50, height: 50)
                }
                .buttonStyle(TVPanelCloseButtonStyle(isFocused: focus == .close, reduceMotion: reduceMotion))
                .focused($focus, equals: .close)
                .accessibilityLabel("关闭\(kind == .episodes ? "选集" : "播放设置")")
            }
            if kind == .episodes, groups.count > 1, !showsEpisodeGroups, let group = selectedGroup {
                option("区间：\(group.title)", item: .groupPicker, selected: false) {
                    didChooseGroup = false
                    showsEpisodeGroups = true
                }
                .padding(.horizontal, 10)
                .accessibilityLabel("选择剧集区间")
                .accessibilityValue("当前浏览\(group.title)")
            }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        if kind == .episodes {
                            if showsEpisodeGroups {
                                ForEach(groups) { group in
                                    let selected = group.id == selectedGroup?.id
                                    option(group.title, item: .group(group.id), selected: selected) {
                                        chooseGroup(group)
                                    }
                                    .id("group:\(group.id)")
                                    .accessibilityValue(selected ? "当前浏览区间" : group.title)
                                }
                            } else {
                                ForEach(visibleEpisodes) { episode in
                                    let selected = model.selectedEpisodeID == episode.id
                                    let item = Item.episode(episode.id)
                                    option(episode.title, item: item, selected: selected,
                                           lockTitle: RoomPlaybackResolver.lockBadgeTitle(for: episode.quality)) {
                                        onSelect(episode.id)
                                    }
                                    .id(episode.id)
                                    .accessibilityValue(selected ? "当前集" : "第\(episode.number)集")
                                }
                            }
                        } else {
                            ForEach(rates, id: \.self) { value in
                                option(rateLabel(value), item: .rate(value), selected: rate == value) { rate = value }
                            }
                            option("自动连播", item: .autoplay, selected: model.autoplay) { model.autoplay.toggle() }
                                .accessibilityValue(model.autoplay ? "已开启" : "已关闭")
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .task(id: focusRequest) {
                    let target = requestedFocus ?? initialFocus
                    switch target {
                    case .episode(let id): proxy.scrollTo(id, anchor: .center)
                    case .group(let id): proxy.scrollTo("group:\(id)", anchor: .center)
                    default: break
                    }
                    // Preserve the existing scroll -> layout yield -> focus ordering.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    focus = target
                }
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .focusSection()
        .onChange(of: showsEpisodeGroups) { _, presented in
            if presented, let id = selectedGroup?.id { requestFocus(.group(id)) }
            else {
                requestFocus(didChooseGroup || groups.count <= 1 ? initialFocus : .groupPicker)
                didChooseGroup = false
            }
        }
        .onChange(of: model.episodes.map(\.id)) { _, _ in
            if !groups.contains(where: { $0.id == browseGroupID }) {
                browseGroupID = groups.first { $0.contains(episodeID: model.selectedEpisodeID) }?.id
                    ?? groups.first?.id
                if showsEpisodeGroups, let id = selectedGroup?.id { requestFocus(.group(id)) }
                else { requestFocus(initialFocus) }
            }
            if groups.count <= 1 { showsEpisodeGroups = false }
        }
    }

    private var subtitle: String {
        guard kind == .episodes else { return "当前：\(rateLabel(rate))" }
        var parts = ["\(model.episodes.count) 集", model.selectedEpisode?.title ?? "尚未选择"]
        if let scope = model.selectedEpisode?.cdn.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !scope.isEmpty {
            parts.append(scope)
        } else if let note = model.selectionNote {
            parts.append(note)
        }
        return parts.joined(separator: " · ")
    }

    private func option(_ title: String, item: Item, selected: Bool, lockTitle: String? = nil, action: @escaping () -> Void) -> some View {
        let focused = focus == item
        return Button(action: action) {
            HStack(spacing: 14) {
                Text(title).font(.system(size: 28, weight: selected || focused ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(focused ? 0.95 : 0.8))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let lockTitle { RequiresLoginTag(lockTitle, size: .regular).lineLimit(1) }
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.2) : focused ? .white.opacity(0.25) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TVQualityItemButtonStyle(isFocused: focused, reduceMotion: reduceMotion))
        .focused($focus, equals: item)
    }
}

private struct TVShortDramaPlayerSurface: View {
    let playback: ShortDramaPlayback
    let rate: Float
    let desiredPlayback: Bool
    let model: ShortDramaPlaybackModel
    let controller: KSShortDramaPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let onReady: (UUID) -> Void
    let onCompleted: () -> Void
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions

    init(playback: ShortDramaPlayback, rate: Float, desiredPlayback: Bool, model: ShortDramaPlaybackModel,
         controller: KSShortDramaPlayerController, playbackSession: KSPlayerPlaybackSession,
         onReady: @escaping (UUID) -> Void, onCompleted: @escaping () -> Void) {
        self.playback = playback
        self.rate = rate
        self.desiredPlayback = desiredPlayback
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.onReady = onReady
        self.onCompleted = onCompleted
        let options = PlayerOptions()
        options.isAutoPlay = desiredPlayback && playback.resumePosition == nil
        options.isLoopPlay = false
        options.registerRemoteControll = false
        options.startPlayRate = rate
        _ = KSPlayerSessionConfigurator.apply(quality: playback.quality, to: options,
                                             fallbackUserAgent: "libmpv", liveReconnectPolicy: .applicationManaged)
        _options = State(initialValue: options)
    }

    var body: some View {
        KSVideoPlayer(coordinator: coordinator, url: playback.url, options: options)
            .onStateChanged { layer, state in
                guard model.playback?.id == playback.id, controller.playbackID == playback.id,
                      layer === coordinator.playerLayer else { return }
                layer.player.contentMode = .scaleAspectFit
                playbackSession.attach(playerLayer: layer)
                playbackSession.activate()
                layer.player.playbackRate = rate
                controller.synchronize(layer: layer, state: state)
                controller.restoreIfPossible(model: model, onReady: onReady)
                if !controller.isRestoring(for: playback.id) && (
                    state == .bufferFinished || (state == .paused && layer.player.loadState == .playable)
                        || (state == .readyToPlay && layer.player.isReadyToPlay && !controller.wantsPlayback)
                ) {
                    onReady(playback.id)
                }
            }
            .onFinish { layer, error in
                guard model.playback?.id == playback.id, controller.playbackID == playback.id,
                      layer === coordinator.playerLayer else { return }
                switch controller.handlePlaybackFinished(layer: layer, playbackID: playback.id, error: error) {
                case .ignored:
                    return
                case .forward(let playbackError):
                    if let sample = controller.timeSample(for: playback.id) {
                        model.recordProgress(id: playback.id, position: sample.current, duration: sample.duration)
                    }
                    // Completion owns the next decision after restore-related EOF is consumed.
                    controller.setDesiredPlayback(false, applyImmediately: false)
                    if playbackError == nil { onCompleted() }
                    Task { @MainActor in await model.playbackFinished(id: playback.id, error: playbackError) }
                }
            }
            .onAppear {
                guard model.playback?.id == playback.id else { return }
                coordinator.playbackRate = rate
                controller.attach(
                    coordinator, playbackID: playback.id, url: playback.url,
                    resumePosition: playback.resumePosition, desiredPlayback: desiredPlayback
                )
            }
            .onChange(of: rate) { _, rate in coordinator.playbackRate = rate }
            .onDisappear { controller.release(coordinator, playbackID: playback.id) }
    }
}

private func timeLabel(_ seconds: Double) -> String {
    let value = seconds.isFinite ? Int(max(0, seconds)) : 0
    return String(format: "%02d:%02d", value / 60, value % 60)
}

private func rateLabel(_ rate: Float) -> String {
    "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
}

#else

struct TVShortDramaPlayerView: View {
    let room: LiveModel
    let onExit: () -> Void
    var body: some View {
        VStack(spacing: 30) {
            Text("当前播放器不支持短剧播放").font(.title)
            Button("返回", action: onExit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
    }
}

#endif
