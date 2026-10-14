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
    @State private var controller = TVShortDramaPlayerController()
    @StateObject private var playbackSession = KSPlayerPlaybackSession(
        role: .primary, supportedGlobalCapabilities: [.audioFocus]
    )
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedControl: Control?
    @State private var panel: TVShortDramaPanelKind?
    @State private var panelGeneration = UUID()
    @State private var showsControls = true
    @State private var playbackRate: Float = 1
    @State private var isPreparing = true
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var resumeAfterPanel = false
    @State private var resumeAfterBackground = false
    @State private var isSuspended = false
    @State private var didCleanup = false
    @State private var operation: Task<Void, Never>?
    @State private var panelOperation: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    private enum Control: Hashable {
        case reveal, playPause, previous, next, backward, forward, episodes, settings
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
                        playback: playback, rate: playbackRate, model: model,
                        controller: controller, playbackSession: playbackSession,
                        onReady: { id in
                            guard model.playback?.id == id else { return }
                            isPreparing = false
                        }
                    )
                    .id(playback.id)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                if model.isLoading || (model.playback != nil && isPreparing) {
                    VStack(spacing: 22) {
                        ProgressView()
                            .fullUIArcLoadingStyle(size: 64, lineWidth: 2.5)
                            .tint(.white)
                        Text(model.selectedEpisode?.title ?? "正在获取剧集")
                            .font(.title3).foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
                }

                if let message = model.errorMessage {
                    statusView(title: "播放失败", message: message, retry: true)
                        .disabled(panel != nil).accessibilityHidden(panel != nil)
                } else if !model.isLoading, model.episodes.isEmpty {
                    statusView(title: "暂无可播放剧集", message: "插件尚未提供分集内容", retry: true)
                        .disabled(panel != nil).accessibilityHidden(panel != nil)
                }

                if panel == nil {
                    if showsControls {
                        controls
                    } else {
                        Button { revealControls() } label: {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        .task { await model.load() }
        .task(id: model.playback?.id) { await observeTime() }
        .onAppear {
            playbackSession.register()
            focusedControl = .playPause
            scheduleHide()
        }
        .onChange(of: model.playback?.id) { _, _ in
            currentTime = 0
            duration = 0
            isPreparing = true
            if model.playback != nil {
                controller.setDesiredPlayback(scenePhase == .active && panel == nil)
                scheduleHide()
            }
        }
        .onChange(of: model.hasFinished) { _, finished in
            if finished { revealControls() }
        }
        .onChange(of: model.errorMessage) { _, message in
            if message != nil { revealControls() }
        }
        .onChange(of: playbackRate) { _, rate in controller.setRate(rate) }
        .onChange(of: focusedControl) { _, control in
            if control != .reveal { scheduleHide() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                if !isSuspended {
                    resumeAfterBackground = panel == nil ? controller.wantsPlayback : resumeAfterPanel
                    isSuspended = true
                }
                controller.setDesiredPlayback(false)
                hideTask?.cancel()
            } else {
                isSuspended = false
                if panel == nil, !model.hasFinished {
                    controller.setDesiredPlayback(resumeAfterBackground)
                }
                scheduleHide()
            }
        }
        .onExitCommand {
            if panel != nil { closePanel() }
            else if showsControls, model.errorMessage == nil, !model.episodes.isEmpty {
                hideControls()
            } else { exit() }
        }
        .onPlayPauseCommand {
            guard panel == nil else { return }
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
                    HStack(spacing: 0) {
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
                    .padding(.horizontal, 5).padding(.vertical, 10)
                    .adaptiveGlassEffectCapsule()
                    .focusSection()

                    Spacer()

                    HStack(spacing: 15) {
                        Button { presentPanel(.episodes) } label: {
                            Label("选集", systemImage: "list.bullet")
                                .font(.system(size: 28, weight: .semibold))
                                .frame(height: 40).padding(.horizontal, 15)
                        }
                        .focused($focusedControl, equals: .episodes)
                        Button { presentPanel(.settings) } label: {
                            Text("\(rateLabel(playbackRate)) · 设置")
                                .font(.system(size: 28, weight: .semibold))
                                .frame(height: 40).padding(.horizontal, 15)
                        }
                        .focused($focusedControl, equals: .settings)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 10)
                    .adaptiveGlassEffectCapsule()
                    .focusSection()
                }
            }
            .padding(.horizontal, 70).padding(.bottom, 70).padding(.top, 60)
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
        .clipShape(.circle)
        .focused($focusedControl, equals: control)
        .accessibilityLabel(title)
    }

    private func statusView(title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 30) {
            Image(systemName: "tv.slash").font(.system(size: 80)).foregroundStyle(.gray)
            Text(title).font(.title).foregroundStyle(.white)
            Text(message).font(.headline).foregroundStyle(.gray)
                .multilineTextAlignment(.center).frame(maxWidth: 900)
            HStack(spacing: 30) {
                if retry { Button("重试", action: retryPlayback) }
                Button("返回", action: exit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private var canSeek: Bool {
        controller.isSeekable(playbackID: model.playback?.id) && !model.hasFinished
    }

    private func seek(_ delta: Double) {
        guard canSeek else { return }
        controller.seek(to: currentTime + delta)
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
        let changesPlayback = id != model.selectedEpisodeID || model.hasFinished || model.playback == nil
        let selectedPanel = panel
        let presentationToken = panelGeneration
        operation?.cancel()
        operation = Task { @MainActor in
            guard !didCleanup else { return }
            if changesPlayback {
                controller.setDesiredPlayback(scenePhase == .active, applyImmediately: false)
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
        if model.hasFinished, let id = model.selectedEpisodeID { selectEpisode(id); return }
        guard model.playback != nil else { return }
        controller.setDesiredPlayback(!controller.wantsPlayback)
        scheduleHide()
    }

    private func retryPlayback() {
        operation?.cancel()
        operation = Task { @MainActor in
            controller.setDesiredPlayback(scenePhase == .active, applyImmediately: false)
            if let id = model.selectedEpisodeID { await model.selectEpisode(id: id) }
            else { await model.load() }
        }
    }

    private func presentPanel(_ kind: TVShortDramaPanelKind) {
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            panel = nil
            showsControls = true
        }
        // Keep the EOF hold until the outgoing panel is no longer covering the controls.
        if closedPanel != nil, !reduceMotion {
            try? await Task.sleep(for: .milliseconds(280))
        }
        guard !Task.isCancelled, !didCleanup, generation == panelGeneration, panel == nil else { return }
        await model.setEpisodesPresented(false)
        guard !Task.isCancelled, !didCleanup, generation == panelGeneration, panel == nil else { return }
        controller.setDesiredPlayback(resuming && scenePhase == .active && !model.hasFinished)
        focusedControl = closedPanel == .settings ? .settings : .episodes
        scheduleHide()
    }

    private func revealControls() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsControls = true }
        focusedControl = .playPause
        scheduleHide()
    }

    private func hideControls() {
        hideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsControls = false }
        focusedControl = .reveal
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard panel == nil, controller.wantsPlayback, !model.hasFinished,
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
            if let sample = controller.timeSample(playbackID: id) {
                currentTime = sample.current.isFinite ? max(0, sample.current) : 0
                duration = sample.duration.isFinite ? max(0, sample.duration) : 0
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true
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
    let onSelect: (String) -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Item?
    private enum Item: Hashable { case close, episode(String), rate(Float), autoplay }
    private let rates: [Float] = [0.75, 1, 1.25, 1.5, 2, 3]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind == .episodes ? "选集" : "播放设置")
                        .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white).frame(width: 50, height: 50)
                        .background(.white.opacity(focus == .close ? 0.3 : 0.1), in: Circle())
                }
                .buttonStyle(.plain).focused($focus, equals: .close)
                .scaleEffect(!reduceMotion && focus == .close ? 1.1 : 1)
                .accessibilityLabel("关闭\(kind == .episodes ? "选集" : "播放设置")")
            }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        if kind == .episodes {
                            ForEach(model.episodes) { episode in
                                let selected = model.selectedEpisodeID == episode.id
                                let item = Item.episode(episode.id)
                                option(episode.title, item: item, selected: selected,
                                       lockTitle: RoomPlaybackResolver.lockBadgeTitle(for: episode.quality)) {
                                    onSelect(episode.id)
                                }
                                .id(episode.id)
                                .accessibilityValue(selected ? "当前集" : "第\(episode.number)集")
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
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }
                .onAppear {
                    if kind == .episodes, let id = model.selectedEpisodeID {
                        proxy.scrollTo(id, anchor: .center)
                        focus = .episode(id)
                    } else { focus = kind == .settings ? .rate(rate) : .close }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .focusSection()
        .onExitCommand(perform: onClose)
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
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).focused($focus, equals: item)
        .scaleEffect(!reduceMotion && focused ? 1.03 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: focused)
    }
}

@MainActor
@Observable
private final class TVShortDramaPlayerController {
    private(set) var coordinator: KSVideoPlayer.Coordinator?
    private(set) var playbackID: UUID?
    private(set) var wantsPlayback = true

    func attach(_ coordinator: KSVideoPlayer.Coordinator, id: UUID) {
        self.coordinator = coordinator
        playbackID = id
    }
    func setDesiredPlayback(_ desired: Bool, applyImmediately: Bool = true) {
        wantsPlayback = desired
        guard applyImmediately else { return }
        if desired { coordinator?.playerLayer?.play() } else { coordinator?.playerLayer?.pause() }
    }
    func synchronize(layer: KSPlayerLayer, state: KSPlayerState) {
        if wantsPlayback {
            if (state == .readyToPlay || state == .paused), !layer.player.isPlaying { layer.play() }
        } else if layer.player.isPlaying { layer.pause() }
    }
    func setRate(_ rate: Float) { coordinator?.playbackRate = rate }
    func timeSample(playbackID: UUID?) -> (current: Double, duration: Double)? {
        guard playbackID == self.playbackID, let player = coordinator?.playerLayer?.player else { return nil }
        return (player.currentPlaybackTime, player.duration)
    }
    func isSeekable(playbackID: UUID?) -> Bool {
        guard playbackID == self.playbackID, let player = coordinator?.playerLayer?.player else { return false }
        return player.seekable && player.duration.isFinite && player.duration > 0
    }
    func seek(to time: Double) {
        guard let layer = coordinator?.playerLayer, isSeekable(playbackID: playbackID) else { return }
        layer.seek(time: min(max(0, time), layer.player.duration), autoPlay: wantsPlayback)
    }
    func release(_ coordinator: KSVideoPlayer.Coordinator, id: UUID) {
        // An outgoing surface can disappear after the next coordinator has attached.
        // Reset its own layer without clearing the new surface's controller identity.
        if coordinator.playerLayer != nil { coordinator.resetPlayer() }
        guard self.coordinator === coordinator, playbackID == id else { return }
        self.coordinator = nil
        playbackID = nil
    }
    func stop() {
        // Surface disappearance and page cleanup share one reset owner.
        coordinator?.resetPlayer()
        coordinator = nil
        playbackID = nil
    }
}

private struct TVShortDramaPlayerSurface: View {
    let playback: ShortDramaPlayback
    let rate: Float
    let model: ShortDramaPlaybackModel
    let controller: TVShortDramaPlayerController
    let playbackSession: KSPlayerPlaybackSession
    let onReady: (UUID) -> Void
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions

    init(playback: ShortDramaPlayback, rate: Float, model: ShortDramaPlaybackModel,
         controller: TVShortDramaPlayerController, playbackSession: KSPlayerPlaybackSession,
         onReady: @escaping (UUID) -> Void) {
        self.playback = playback
        self.rate = rate
        self.model = model
        self.controller = controller
        self.playbackSession = playbackSession
        self.onReady = onReady
        let options = PlayerOptions()
        options.isAutoPlay = controller.wantsPlayback
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
                if state == .bufferFinished || (state == .paused && layer.player.loadState == .playable) {
                    onReady(playback.id)
                }
            }
            .onFinish { layer, error in
                guard model.playback?.id == playback.id, controller.playbackID == playback.id,
                      layer === coordinator.playerLayer else { return }
                // Completion owns the next decision; a later paused callback must not restart this layer.
                controller.setDesiredPlayback(false, applyImmediately: false)
                Task { @MainActor in await model.playbackFinished(id: playback.id, error: error) }
            }
            .onAppear {
                controller.attach(coordinator, id: playback.id)
                coordinator.playbackRate = rate
            }
            .onChange(of: rate) { _, rate in coordinator.playbackRate = rate }
            .onDisappear { controller.release(coordinator, id: playback.id) }
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
