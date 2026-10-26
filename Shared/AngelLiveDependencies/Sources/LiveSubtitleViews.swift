import SwiftUI
import AngelLiveCore

/// Room controls expose a language choice only after audio detection was inconclusive.
@MainActor
public struct LiveSubtitleQuickControls: View {
    private let playback: LiveSubtitlePlaybackState
    private let onChooseLanguage: () -> Void

    public init(playback: LiveSubtitlePlaybackState, onChooseLanguage: @escaping () -> Void) {
        self.playback = playback
        self.onChooseLanguage = onChooseLanguage
    }

    public var body: some View {
        let activationID = playback.activationID
        return Group {
            if playback.isEnabled {
                Button("关闭实时字幕") { playback.stop() }
                switch playback.phase {
                case .manualSelectionRequired:
                    Button("选择主播语言…", action: onChooseLanguage)
                case .modelDownloadRequired:
                    Button("下载字幕识别文件并继续") {
                        playback.prepareResources(activationID: activationID)
                    }
                case .speechResourcesRequired:
                    Button("下载\(playback.sourceLanguageDisplayName ?? "系统")语音包并继续") {
                        playback.prepareResources(activationID: activationID)
                    }
                case .failed:
                    if let message = playback.statusMessage {
                        Text(message)
                    }
                    Button("重试实时字幕") {
                        playback.startAutomatically(activationID: activationID)
                    }
                default:
                    if let message = playback.statusMessage {
                        Text(message)
                    }
                }
            } else {
                Button("开启实时字幕") {
                    playback.startAutomatically(activationID: activationID)
                }
            }
        }
    }
}

/// The real Speech catalog is loaded only when a manual recovery is needed.
@MainActor
public struct LiveSubtitleLanguageOptions: View {
    private let playback: LiveSubtitlePlaybackState
    private let activationID: UUID
    private let onSelection: () -> Void
    @State private var languages: [Locale] = []
    @State private var isLoading = true

    public init(playback: LiveSubtitlePlaybackState, activationID: UUID, onSelection: @escaping () -> Void = {}) {
        self.playback = playback
        self.activationID = activationID
        self.onSelection = onSelection
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取可用语言…")
            } else if languages.isEmpty {
                Text("这台设备暂不支持字幕识别。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(languages, id: \.identifier) { language in
                    Button(Locale.current.localizedString(forIdentifier: language.identifier) ?? language.identifier) {
                        guard playback.chooseLanguage(language.identifier, activationID: activationID) else { return }
                        onSelection()
                    }
                }
            }
        }
        .task {
            let available = await LiveSubtitleSession.supportedLanguages()
            guard !Task.isCancelled else { return }
            languages = available
            isLoading = false
        }
    }
}

/// A scrollable system list keeps the complete language catalog reachable on every platform.
@MainActor
public struct LiveSubtitleLanguageSelectionSheet: View {
    private let playback: LiveSubtitlePlaybackState
    private let activationID: UUID
    @Environment(\.dismiss) private var dismiss

    public init(playback: LiveSubtitlePlaybackState, activationID: UUID) {
        self.playback = playback
        self.activationID = activationID
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSubtitleLanguageOptions(playback: playback, activationID: activationID) {
                        dismiss()
                    }
                } header: {
                    Text("主播语言")
                } footer: {
                    Text("没能自动识别，请选择主播正在说的语言。")
                }
                #if os(tvOS)
                Section {
                    Button("取消", role: .cancel) { dismiss() }
                }
                #endif
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("选择主播语言")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #elseif os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

/// Shared settings reuse each host's existing labels and row layout.
@MainActor
public struct LiveSubtitleSettingsSection<SubtitleLabel: View, SourceLanguageLabel: View, ResourceLabel: View>: View {
    private let subtitleLabel: SubtitleLabel
    private let sourceLanguageLabel: SourceLanguageLabel
    private let resourceLabel: ResourceLabel
    @State private var modelStatus: LiveSubtitleResourceStatus?
    @State private var downloadProgress = 0.0
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadGeneration = UUID()
    @State private var isDownloading = false
    @State private var showSpeechResources = false

    public init(
        @ViewBuilder subtitleLabel: () -> SubtitleLabel,
        @ViewBuilder sourceLanguageLabel: () -> SourceLanguageLabel,
        @ViewBuilder resourceLabel: () -> ResourceLabel
    ) {
        self.subtitleLabel = subtitleLabel()
        self.sourceLanguageLabel = sourceLanguageLabel()
        self.resourceLabel = resourceLabel()
    }

    public init() where SubtitleLabel == Label<Text, SwiftUI.Image>, SourceLanguageLabel == Text, ResourceLabel == Label<Text, SwiftUI.Image> {
        self.init {
            Label("实时字幕", systemImage: "waveform")
        } sourceLanguageLabel: {
            Text("系统语音包")
        } resourceLabel: {
            Label("字幕识别文件", systemImage: "waveform")
        }
    }

    private var explanation: String {
        #if os(tvOS)
        let entry = "看直播时，选中画面里的播放/暂停按钮，长按遥控器中键，在菜单里开启字幕。"
        #elseif os(macOS)
        let entry = "看直播时，点播放器的齿轮按钮开启字幕。"
        #else
        let entry = "看直播时，在播放器的设置或更多菜单里开启字幕。"
        #endif
        return entry + "每个房间需单独开启，主播语言会自动识别。首次下载约 79 MB 识别文件，再按提示下载系统语音包。音频不上传。"
    }

    public var body: some View {
        Group {
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 18) {
                Text("实时字幕")
                    .font(.system(size: 30, weight: .semibold))
                HStack {
                    Text("实时字幕")
                        .font(.system(size: 28, weight: .semibold))
                    Spacer()
                    Text("在播放器中开启")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 55)
                modelResourceRow
                    .frame(minHeight: 55)
                Button("系统语音包") { showSpeechResources = true }
                if let downloadError {
                    Text(downloadError)
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(explanation)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
            #else
            Section {
                HStack {
                    subtitleLabel
                    Spacer(minLength: 8)
                    Text("在播放器中开启")
                        .foregroundStyle(.secondary)
                }
                modelResourceRow
                NavigationLink {
                    Form { LiveSubtitleSpeechResourcesSection() }
                        #if os(macOS)
                        .formStyle(.grouped)
                        #endif
                        .navigationTitle("系统语音包")
                } label: {
                    sourceLanguageLabel
                }
                if let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("实时字幕")
            } footer: {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
        }
        .task { modelStatus = await LiveLanguageDetectionResources.shared.status() }
        .onDisappear {
            downloadGeneration = UUID()
            downloadTask?.cancel()
            downloadTask = nil
            isDownloading = false
        }
        .sheet(isPresented: $showSpeechResources) {
            NavigationStack {
                #if os(tvOS)
                ScrollView {
                    LiveSubtitleSpeechResourcesSection()
                        .padding(60)
                    Button("关闭") { showSpeechResources = false }
                }
                #else
                Form { LiveSubtitleSpeechResourcesSection() }
                    #if os(macOS)
                    .formStyle(.grouped)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showSpeechResources = false }
                        }
                    }
                #endif
            }
            .navigationTitle("系统语音包")
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 320)
            #endif
        }
    }

    private var modelResourceRow: some View {
        HStack(spacing: 12) {
            resourceLabel
            Spacer(minLength: 8)
            if isDownloading {
                ProgressView(value: downloadProgress)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("字幕识别文件下载进度")
                Text("\(Int(downloadProgress * 100))%")
                    .monospacedDigit()
            } else if let modelStatus {
                switch modelStatus {
                case .ready:
                    Text("已下载").foregroundStyle(.secondary)
                case .needsDownload:
                    Text("未下载").foregroundStyle(.secondary)
                    Button("下载") { beginModelDownload() }
                        .accessibilityLabel("下载字幕识别文件，约79 MB")
                case .downloading:
                    ProgressView().controlSize(.small)
                    Text("下载中").foregroundStyle(.secondary)
                case .unsupported:
                    Text("当前设备不支持").foregroundStyle(.secondary)
                case .unavailable:
                    Text("暂时无法使用").foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small)
                Text("检查中").foregroundStyle(.secondary)
            }
        }
    }

    private func beginModelDownload() {
        guard !isDownloading else { return }
        let generation = UUID()
        downloadGeneration = generation
        downloadProgress = 0
        downloadError = nil
        isDownloading = true
        downloadTask = Task { @MainActor in
            defer {
                if generation == downloadGeneration {
                    isDownloading = false
                    downloadTask = nil
                }
            }
            do {
                try await LiveLanguageDetectionResources.shared.download { fraction in
                    guard generation == downloadGeneration else { return }
                    downloadProgress = fraction.isFinite ? min(max(fraction, 0), 1) : 0
                }
            } catch {
                guard !Task.isCancelled, generation == downloadGeneration else { return }
                downloadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            guard !Task.isCancelled, generation == downloadGeneration else { return }
            modelStatus = await LiveLanguageDetectionResources.shared.status()
        }
    }
}

/// Shared settings rows for on-device live speech subtitles.
@MainActor
private struct LiveSubtitleSpeechResourcesSection: View {
    @Bindable private var settings = LiveSubtitleSettings.shared
    @State private var resourceStatus: LiveSubtitleResourceStatus?
    @State private var unavailableReason: LiveSubtitleUnavailableReason?
    @State private var isDownloading = false
    @State private var downloadProgress = 0.0
    @State private var downloadError: String?
    @State private var downloadGeneration = UUID()
    @State private var downloadTask: Task<Void, Never>?

    private var needsDownload: Bool {
        if case .needsDownload? = resourceStatus { return true }
        return false
    }

    private var unavailableResourceMessage: String? {
        if let unavailableReason { return unavailableReason.message }
        if case .unavailable? = resourceStatus {
            return "系统语音包暂时无法使用，请重试。"
        }
        return nil
    }

    private var subtitleExplanation: String {
        "可在这里提前下载语音包，开字幕时仍会自动识别语言。字幕需要系统 26 或更高版本。"
    }

    #if os(tvOS)
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("系统语音包")
                .font(.system(size: 30, weight: .semibold))

            Picker("语言", selection: $settings.sourceLanguage) {
                ForEach(LiveSubtitleLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .disabled(isDownloading)
            .frame(minHeight: 55)

            resourceStatusContent

            if let downloadError {
                Text(downloadError)
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(subtitleExplanation)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let unavailableResourceMessage {
                Text(unavailableResourceMessage)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .task(id: settings.sourceLanguage.rawValue) {
            await refreshResourceStatus()
        }
        .onChange(of: settings.sourceLanguage) { _, _ in
            downloadError = nil
        }
        .onDisappear(perform: cancelDownload)
    }
    #else
    public var body: some View {
        Section {
            Picker(selection: $settings.sourceLanguage) {
                ForEach(LiveSubtitleLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            } label: {
                Text("语言")
            }
            #if os(iOS)
            .pickerStyle(.navigationLink)
            #endif
            .disabled(isDownloading)

            resourceStatusContent

            if let downloadError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("系统语音包")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(subtitleExplanation)
                if let unavailableResourceMessage {
                    Text(unavailableResourceMessage)
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: settings.sourceLanguage.rawValue) {
            await refreshResourceStatus()
        }
        .onChange(of: settings.sourceLanguage) { _, _ in
            downloadError = nil
        }
        .onDisappear(perform: cancelDownload)
    }
    #endif

    @ViewBuilder
    private var resourceStatusContent: some View {
        HStack(spacing: 12) {
            Label("系统语音包", systemImage: "waveform")

            Spacer(minLength: 8)

            if isDownloading {
                ProgressView(value: downloadProgress)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("系统语音包下载进度")
                Text("\(Int(downloadProgress * 100))%")
                    .monospacedDigit()
                    .accessibilityLabel("\(Int(downloadProgress * 100))%")
            } else if let resourceStatus {
                switch resourceStatus {
                case .unsupported:
                    Text(unavailableReason?.shortDescription ?? "当前设备不支持")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(unavailableReason?.message ?? "当前设备不支持实时字幕")
                case .unavailable:
                    Text("暂时无法使用")
                        .foregroundStyle(.secondary)
                case .needsDownload:
                    Text("未下载")
                        .foregroundStyle(.secondary)
                    Button("下载") {
                        beginDownload()
                    }
                    .accessibilityLabel("下载系统语音包")
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("下载中")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                case .ready:
                    Text("已下载")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("检查中")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func refreshResourceStatus() async {
        let sourceLanguage = settings.sourceLanguage.rawValue
        let availability = await LiveSubtitleSession.availability(sourceLanguage: sourceLanguage)
        guard !Task.isCancelled, settings.sourceLanguage.rawValue == sourceLanguage else { return }
        resourceStatus = availability.status
        unavailableReason = availability.unavailableReason
    }

    private func beginDownload() {
        guard !isDownloading, needsDownload else { return }
        let sourceLanguage = settings.sourceLanguage.rawValue
        let generation = UUID()
        downloadGeneration = generation
        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        resourceStatus = .downloading

        downloadTask = Task { @MainActor in
            defer {
                if downloadGeneration == generation {
                    isDownloading = false
                    downloadTask = nil
                }
            }

            do {
                try await LiveSubtitleSession.downloadResources(sourceLanguage: sourceLanguage) { fraction in
                    guard downloadGeneration == generation else { return }
                    downloadProgress = fraction.isFinite ? min(max(fraction, 0), 1) : 0
                }
                guard !Task.isCancelled, downloadGeneration == generation else { return }
                await refreshResourceStatus()
            } catch {
                guard !Task.isCancelled, downloadGeneration == generation else { return }
                await refreshResourceStatus()
                downloadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func cancelDownload() {
        downloadGeneration = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }
}

#if canImport(KSPlayer)
import KSPlayer

@MainActor
private struct LiveSubtitleOverlayModifier: ViewModifier {
    private static let preparingStatusMessage = "正在开启字幕…"

    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    let playback: LiveSubtitlePlaybackState
    let playbackIdentity: String
    let bottomPadding: CGFloat

    @Bindable private var translationSettings = RoomTranslationSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: LiveSubtitleSession?
    @State private var sessionIdentity: String?
    @State private var translation = LiveSubtitleTranslationPipeline()
    @State private var transientStatusMessage: String?
    @State private var lastPresentedStatusMessage: String?
    @State private var hasPresentedTranslationFailureHint = false
    @State private var translationFailureStatusMessage: String?
    @State private var statusGeneration = UUID()
    @State private var statusTask: Task<Void, Never>?

    private var taskIdentity: String {
        let playerIdentity = coordinator.playerLayer.map {
            "\(ObjectIdentifier($0))|\(ObjectIdentifier($0.player))"
        } ?? "no-player"
        return "\(playback.activationID)|\(playbackIdentity)|\(playerIdentity)|\(isPlayerReady)|\(scenePhase)"
    }

    private var isPlayerReady: Bool {
        coordinator.playerLayer?.player.isReadyToPlay ?? false
    }

    private var isDownloadingResources: Bool {
        playback.isEnabled && (playback.phase == .downloadingModel || playback.phase == .downloadingSpeechResources)
    }

    private var visibleStatusMessage: String? {
        if isDownloadingResources {
            let message = playback.statusMessage ?? "正在下载字幕所需文件…"
            if let progress = playback.downloadProgress, progress.isFinite {
                return "\(message) \(Int(min(max(progress, 0), 1) * 100))%"
            }
            return message
        }
        return transientStatusMessage
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    if let visibleStatusMessage {
                        Text(visibleStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    }

                    subtitleBubble
                }
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, alignment: .center)
                .allowsHitTesting(false)
            }
            .task(id: taskIdentity) {
                translation.reset()
                session?.stop()
                session = nil
                sessionIdentity = nil
                clearTransientStatus()
                lastPresentedStatusMessage = nil
                hasPresentedTranslationFailureHint = false
                translationFailureStatusMessage = nil
                guard playback.isEnabled, scenePhase == .active else { return }
                let activationID = playback.activationID
                let sourceLanguage = playback.sourceLanguage
                let resourcePreparation = playback.resourcePreparation

                showKnownTranslationFailureIfNeeded()
                guard
                    let layer = coordinator.playerLayer,
                    layer.player.isReadyToPlay
                else { return }

                if !hasPresentedTranslationFailureHint {
                    showTransientStatus(Self.preparingStatusMessage)
                }
                let activeSession = LiveSubtitleSession()
                let activeIdentity = taskIdentity
                sessionIdentity = activeIdentity
                session = activeSession
                await activeSession.run(
                    layer: layer,
                    sourceLanguage: sourceLanguage,
                    resourcePreparation: resourcePreparation
                ) { update in
                    guard !Task.isCancelled,
                          session === activeSession,
                          sessionIdentity == activeIdentity,
                          taskIdentity == activeIdentity,
                          playback.apply(update, activationID: activationID)
                    else { return }
                    showTransientStatus(update.message)
                }
                guard !Task.isCancelled,
                      session === activeSession,
                      sessionIdentity == activeIdentity,
                      taskIdentity == activeIdentity
                else { return }
                if let message = activeSession.statusMessage {
                    showTransientStatus(message)
                }
            }
            .onChange(of: coordinator.state) { _, _ in
                guard sessionIdentity == taskIdentity else { return }
                if let layer = coordinator.playerLayer, layer.player.isReadyToPlay {
                    session?.attach(layer: layer)
                }
            }
            .onChange(of: session?.statusMessage) { _, message in
                guard sessionIdentity == taskIdentity else { return }
                showTransientStatus(message)
            }
            .onChange(of: session?.text) { _, text in
                synchronizeTranslationWithCurrentSpeech()
                guard sessionIdentity == taskIdentity else { return }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    clearPreparationHint()
                }
            }
            .onChange(of: session?.segmentID) { _, _ in
                synchronizeTranslationWithCurrentSpeech()
            }
            .onChange(of: playback.sourceLanguage) { _, _ in
                guard sessionIdentity == taskIdentity else { return }
                translation.reset()
                clearTranslationFailureHint()
                showKnownTranslationFailureIfNeeded()
                synchronizeTranslationWithCurrentSpeech()
            }
            .onChange(of: translationSettings.revision) { _, _ in
                clearTranslationFailureHint()
                translation.reset()
                showKnownTranslationFailureIfNeeded()
                synchronizeTranslationWithCurrentSpeech()
            }
            .onChange(of: translation.text) { _, text in
                guard
                    sessionIdentity == taskIdentity,
                    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    translation.errorMessage == nil
                else { return }
                clearTranslationFailureHint()
            }
            .onChange(of: translation.lastError) { _, error in
                guard sessionIdentity == taskIdentity, let error else { return }
                showTranslationFailureHint(error)
            }
            .onDisappear {
                clearTransientStatus()
                lastPresentedStatusMessage = nil
                hasPresentedTranslationFailureHint = false
                translationFailureStatusMessage = nil
                session?.stop()
                session = nil
                sessionIdentity = nil
                translation.reset()
            }
    }

    @ViewBuilder
    private var subtitleBubble: some View {
        if let text = subtitleText {
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private var subtitleText: String? {
        guard playback.isEnabled, sessionIdentity == taskIdentity else { return nil }
        let translatedText = translation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translatedText.isEmpty { return translatedText }

        let originalText = session?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return originalText.isEmpty ? nil : originalText
    }

    private func synchronizeTranslationWithCurrentSpeech() {
        guard
            sessionIdentity == taskIdentity,
            let sourceLanguage = playback.sourceLanguage,
            let session,
            let segmentID = session.segmentID,
            !session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            translation.reset()
            return
        }

        translation.enqueue(
            session.text,
            sourceLanguage: sourceLanguage,
            segmentID: segmentID
        )
    }

    private func showTransientStatus(_ message: String?) {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedMessage, !trimmedMessage.isEmpty else { return }
        guard lastPresentedStatusMessage != trimmedMessage else { return }
        statusTask?.cancel()

        let generation = UUID()
        statusGeneration = generation
        lastPresentedStatusMessage = trimmedMessage
        transientStatusMessage = trimmedMessage
        statusTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            guard statusGeneration == generation else { return }
            transientStatusMessage = nil
            statusTask = nil
        }
    }

    private func showKnownTranslationFailureIfNeeded() {
        guard let sourceLanguage = playback.sourceLanguage, scenePhase == .active,
              let error = translation.availabilityError(sourceLanguage: sourceLanguage)
        else { return }
        showTranslationFailureHint(error)
    }

    private func showTranslationFailureHint(_ error: RoomTranslationError) {
        guard playback.isEnabled else { return }
        guard !hasPresentedTranslationFailureHint else { return }
        hasPresentedTranslationFailureHint = true
        let engine = translationSettings.engine == .llm ? "大模型翻译" : "系统翻译"
        let reason: String
        switch error {
        case .cloudConfigurationRequired, .invalidBaseURL, .invalidModel:
            reason = "请检查大模型配置"
        case .apiKeyRequired:
            reason = "请先保存 API Key"
        case .authentication:
            reason = "API Key 无效"
        case .secureStorage:
            reason = "无法读取 API Key"
        case .rateLimited:
            reason = "请求过于频繁"
        case .languageResourcesRequired:
            reason = "请先下载翻译语言包"
        case .appleTranslationUnsupported:
            reason = "当前系统不支持"
        case .simulatorUnsupported:
            reason = "模拟器不支持"
        case .unsupportedSourceLanguage:
            reason = "暂不支持这种语言"
        case .invalidResponse:
            reason = "服务返回结果无效"
        case .busy:
            reason = "服务繁忙，请稍后重试"
        case .unavailable, .serviceUnavailable:
            reason = "服务暂不可用"
        }
        let recovery = error.recommendsLLMFallback(for: translationSettings.engine)
            ? "请在“翻译与字幕”配置大模型翻译。"
            : "暂时显示原文字幕。"
        let message = "\(engine)：\(reason)。\n\(recovery)"
        translationFailureStatusMessage = message
        showTransientStatus(message)
    }

    private func clearTranslationFailureHint() {
        hasPresentedTranslationFailureHint = false
        guard let message = translationFailureStatusMessage else { return }
        if transientStatusMessage == message {
            clearTransientStatus()
        }
        if lastPresentedStatusMessage == message {
            lastPresentedStatusMessage = nil
        }
        translationFailureStatusMessage = nil
    }

    private func clearPreparationHint() {
        guard transientStatusMessage == Self.preparingStatusMessage else { return }
        clearTransientStatus()
        if lastPresentedStatusMessage == Self.preparingStatusMessage {
            lastPresentedStatusMessage = nil
        }
    }

    private func clearTransientStatus() {
        statusGeneration = UUID()
        statusTask?.cancel()
        statusTask = nil
        transientStatusMessage = nil
    }
}

public extension View {
    /// Shows on-device speech text on the video surface without intercepting player controls.
    @MainActor
    func liveSubtitleOverlay(
        coordinator: KSVideoPlayer.Coordinator,
        playback: LiveSubtitlePlaybackState,
        playbackIdentity: String,
        bottomPadding: CGFloat = 16
    ) -> some View {
        modifier(
            LiveSubtitleOverlayModifier(
                coordinator: coordinator,
                playback: playback,
                playbackIdentity: playbackIdentity,
                bottomPadding: bottomPadding
            )
        )
    }
}
#endif
