import SwiftUI
import AngelLiveCore

/// Compact controls for enabling live subtitles and selecting the spoken language.
@MainActor
public struct LiveSubtitleQuickControls: View {
    @Bindable private var settings = LiveSubtitleSettings.shared

    public init() {}

    public var body: some View {
        Group {
            Toggle("实时字幕", isOn: $settings.isEnabled)

            Picker("主播语音语言", selection: $settings.sourceLanguage) {
                ForEach(LiveSubtitleLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

/// Shared settings rows for on-device live speech subtitles.
@MainActor
public struct LiveSubtitleSettingsSection: View {
    @Bindable private var settings = LiveSubtitleSettings.shared
    @State private var resourceStatus: LiveSubtitleResourceStatus?
    @State private var isDownloading = false
    @State private var downloadProgress = 0.0
    @State private var downloadError: String?
    @State private var downloadGeneration = UUID()
    @State private var downloadTask: Task<Void, Never>?

    public init() {}

    private var isUnsupported: Bool {
        if case .unsupported? = resourceStatus { return true }
        return false
    }

    private var needsDownload: Bool {
        if case .needsDownload? = resourceStatus { return true }
        return false
    }

    private var unavailableResourceMessage: String? {
        if case .unavailable? = resourceStatus {
            return "暂时无法准备语音模型，请稍后重试。"
        }
        return nil
    }

    #if os(tvOS)
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("实时字幕")
                .font(.system(size: 30, weight: .semibold))

            Toggle(isOn: $settings.isEnabled) {
                Text("实时语音字幕")
                    .font(.system(size: 28, weight: .semibold))
            }
            .disabled(isUnsupported && !settings.isEnabled)
            .frame(minHeight: 55)

            Picker("主播语音语言", selection: $settings.sourceLanguage) {
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

            Text("由 Apple 在本机识别主播语音，识别语言需与主播一致。部分播放源或设备可能不支持。实时字幕翻译使用当前目标语言和翻译引擎。")
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
            Toggle(isOn: $settings.isEnabled) {
                Label("实时语音字幕", systemImage: "waveform")
            }
            .tint(.accentColor)
            .disabled(isUnsupported && !settings.isEnabled)

            Picker("主播语音语言", selection: $settings.sourceLanguage) {
                ForEach(LiveSubtitleLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language)
                }
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
            Text("实时字幕")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("由 Apple 在本机识别主播语音，识别语言需与主播一致。部分播放源或设备可能不支持。实时字幕翻译使用当前目标语言和翻译引擎。")
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
            Label("语音模型", systemImage: "waveform")

            Spacer(minLength: 8)

            if isDownloading {
                ProgressView(value: downloadProgress)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("语音模型下载进度")
                Text("\(Int(downloadProgress * 100))%")
                    .monospacedDigit()
                    .accessibilityLabel("\(Int(downloadProgress * 100))%")
            } else if let resourceStatus {
                switch resourceStatus {
                case .unsupported:
                    Text("当前设备不支持实时字幕")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("实时字幕当前系统不支持")
                case .unavailable:
                    Text("暂时无法准备语音模型")
                        .foregroundStyle(.secondary)
                case .needsDownload:
                    Text("尚未下载")
                        .foregroundStyle(.secondary)
                    Button("下载") {
                        beginDownload()
                    }
                    .accessibilityLabel("下载语音模型")
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("下载中")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                case .ready:
                    Text("已就绪")
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
        let nextStatus = await LiveSubtitleSession.resourceStatus(sourceLanguage: sourceLanguage)
        guard !Task.isCancelled, settings.sourceLanguage.rawValue == sourceLanguage else { return }
        resourceStatus = nextStatus
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
                resourceStatus = await LiveSubtitleSession.resourceStatus(sourceLanguage: sourceLanguage)
            } catch {
                guard !Task.isCancelled, downloadGeneration == generation else { return }
                resourceStatus = await LiveSubtitleSession.resourceStatus(sourceLanguage: sourceLanguage)
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
    private static let translationFailureStatusMessage = "翻译暂不可用，已保留原文。"
    private static let preparingStatusMessage = "正在准备字幕…"

    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    let playbackIdentity: String
    let bottomPadding: CGFloat

    @Bindable private var settings = LiveSubtitleSettings.shared
    @Bindable private var translationSettings = RoomTranslationSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: LiveSubtitleSession?
    @State private var translation = LiveSubtitleTranslationPipeline()
    @State private var transientStatusMessage: String?
    @State private var lastPresentedStatusMessage: String?
    @State private var hasPresentedTranslationFailureHint = false
    @State private var statusGeneration = UUID()
    @State private var statusTask: Task<Void, Never>?

    private var taskIdentity: String {
        let playerIdentity = coordinator.playerLayer.map {
            "\(ObjectIdentifier($0))|\(ObjectIdentifier($0.player))"
        } ?? "no-player"
        return "\(settings.isEnabled)|\(settings.sourceLanguage.rawValue)|\(playbackIdentity)|\(playerIdentity)|\(isPlayerReady)|\(scenePhase)"
    }

    private var isPlayerReady: Bool {
        coordinator.playerLayer?.player.isReadyToPlay ?? false
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    if let transientStatusMessage {
                        Text(transientStatusMessage)
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
                clearTransientStatus()
                lastPresentedStatusMessage = nil
                hasPresentedTranslationFailureHint = false
                guard
                    settings.isEnabled,
                    scenePhase == .active,
                    let layer = coordinator.playerLayer,
                    layer.player.isReadyToPlay
                else { return }

                showTransientStatus(Self.preparingStatusMessage)
                let activeSession = LiveSubtitleSession()
                session = activeSession
                await activeSession.run(
                    layer: layer,
                    sourceLanguage: settings.sourceLanguage.rawValue
                )
                if let message = activeSession.statusMessage {
                    showTransientStatus(message)
                }
            }
            .onChange(of: coordinator.state) { _, _ in
                if let layer = coordinator.playerLayer, layer.player.isReadyToPlay {
                    session?.attach(layer: layer)
                }
            }
            .onChange(of: session?.statusMessage) { _, message in
                showTransientStatus(message)
            }
            .onChange(of: session?.text) { _, text in
                synchronizeTranslationWithCurrentSpeech()
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    clearPreparationHint()
                }
            }
            .onChange(of: session?.segmentID) { _, _ in
                synchronizeTranslationWithCurrentSpeech()
            }
            .onChange(of: translationSettings.revision) { _, _ in
                clearTranslationFailureHint()
                translation.reset()
                synchronizeTranslationWithCurrentSpeech()
            }
            .onChange(of: translation.text) { _, text in
                guard
                    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    translation.errorMessage == nil
                else { return }
                clearTranslationFailureHint()
            }
            .onChange(of: translation.errorMessage) { _, message in
                guard message != nil else { return }
                showTranslationFailureHint()
            }
            .onDisappear {
                clearTransientStatus()
                lastPresentedStatusMessage = nil
                hasPresentedTranslationFailureHint = false
                session?.stop()
                session = nil
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
        let translatedText = translation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translatedText.isEmpty { return translatedText }

        let originalText = session?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return originalText.isEmpty ? nil : originalText
    }

    private func synchronizeTranslationWithCurrentSpeech() {
        guard
            let session,
            let segmentID = session.segmentID,
            !session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            translation.reset()
            return
        }

        translation.enqueue(
            session.text,
            sourceLanguage: settings.sourceLanguage.rawValue,
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

    private func showTranslationFailureHint() {
        guard !hasPresentedTranslationFailureHint else { return }
        hasPresentedTranslationFailureHint = true
        showTransientStatus(Self.translationFailureStatusMessage)
    }

    private func clearTranslationFailureHint() {
        hasPresentedTranslationFailureHint = false
        if transientStatusMessage == Self.translationFailureStatusMessage {
            clearTransientStatus()
        }
        if lastPresentedStatusMessage == Self.translationFailureStatusMessage {
            lastPresentedStatusMessage = nil
        }
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
        playbackIdentity: String,
        bottomPadding: CGFloat = 16
    ) -> some View {
        modifier(
            LiveSubtitleOverlayModifier(
                coordinator: coordinator,
                playbackIdentity: playbackIdentity,
                bottomPadding: bottomPadding
            )
        )
    }
}
#endif
