import AVFoundation
import AngelLiveCore
import Foundation
import Observation
import Speech

#if canImport(KSPlayer)
import KSPlayer
import Synchronization
#endif

public enum LiveSubtitleResourceStatus: Equatable, Sendable {
    case unsupported
    case unavailable
    case needsDownload
    case downloading
    case ready
}

public enum LiveSubtitleUnavailableReason: Equatable, Sendable {
    case playerBackend
    case systemVersion
    case simulator
    case speechUnavailable
    case sourceLanguage

    public var shortDescription: String {
        switch self {
        case .playerBackend: "播放器不支持字幕"
        case .systemVersion: "需要系统 26 或更高版本"
        case .simulator: "模拟器不支持字幕识别"
        case .speechUnavailable: "设备不支持字幕识别"
        case .sourceLanguage: "不支持此语言"
        }
    }

    public var message: String {
        switch self {
        case .playerBackend:
            "当前播放器不支持字幕识别。"
        case .systemVersion:
            "字幕需要系统 26 或更高版本。"
        case .simulator:
            "模拟器不支持语音识别，请在真机上使用字幕。"
        case .speechUnavailable:
            "这台设备不支持语音识别，无法生成直播字幕。"
        case .sourceLanguage:
            "系统不支持识别这种语言。"
        }
    }
}

public struct LiveSubtitleAvailability: Equatable, Sendable {
    public let status: LiveSubtitleResourceStatus
    public let unavailableReason: LiveSubtitleUnavailableReason?

    init(status: LiveSubtitleResourceStatus, unavailableReason: LiveSubtitleUnavailableReason? = nil) {
        self.status = status
        self.unavailableReason = unavailableReason
    }
}

@MainActor
@Observable
public final class LiveSubtitleSession {
    public private(set) var text = ""
    public private(set) var segmentID: String?
    public private(set) var statusMessage: String?

    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var updateHandler: (@MainActor @Sendable (LiveSubtitleUpdate) -> Void)?
    @ObservationIgnored private var currentSourceLanguage: String?
    @ObservationIgnored private let languageDetectionResources: LiveLanguageDetectionResources
    #if canImport(KSPlayer)
    @ObservationIgnored private weak var attachedLayer: KSPlayerLayer?
    @ObservationIgnored private var recognizer: (any LiveAudioRecognizing)?
    #endif
    @ObservationIgnored private var lastResultInstant: ContinuousClock.Instant?

    public init() {
        languageDetectionResources = .shared
    }

    init(languageDetectionResources: LiveLanguageDetectionResources) {
        self.languageDetectionResources = languageDetectionResources
    }

    #if canImport(KSPlayer)
    public func run(
        layer: KSPlayerLayer,
        sourceLanguage: String? = nil,
        resourcePreparation: LiveSubtitleResourcePreparation? = nil,
        onUpdate: @escaping @MainActor @Sendable (LiveSubtitleUpdate) -> Void = { _ in }
    ) async {
        stop()
        let currentGeneration = generation
        updateHandler = onUpdate
        currentSourceLanguage = sourceLanguage
        publish(.preparing, message: "正在开启字幕…", generation: currentGeneration)

        #if canImport(KSPlayer)
        guard layer.player is KSMEPlayer else {
            publish(.unavailable, message: LiveSubtitleUnavailableReason.playerBackend.message, generation: currentGeneration)
            return
        }
        #else
        statusMessage = "当前播放器不支持字幕识别。"
        return
        #endif

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRun(
                layer: layer,
                sourceLanguage: sourceLanguage,
                resourcePreparation: resourcePreparation,
                generation: currentGeneration
            )
        }
        runTask = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        if generation == currentGeneration {
            runTask = nil
            detachRecognizer()
        }
    }

    /// Reinstalls the callback after KSPlayer rebuilds its subtitle list at ready-to-play.
    public func attach(layer: KSPlayerLayer) {
        #if canImport(KSPlayer)
        guard let recognizer else {
            attachedLayer = layer
            return
        }
        guard layer.player is KSMEPlayer else {
            generation &+= 1
            runTask?.cancel()
            runTask = nil
            recognizer.finish()
            detachRecognizer()
            attachedLayer = layer
            text = ""
            segmentID = nil
            lastResultInstant = nil
            statusMessage = "当前播放器不支持字幕识别。"
            updateHandler?(LiveSubtitleUpdate(
                phase: .unavailable,
                sourceLanguage: currentSourceLanguage,
                message: statusMessage
            ))
            return
        }

        if let attachedLayer, attachedLayer !== layer {
            remove(recognizer: recognizer, from: attachedLayer)
        }
        attachedLayer = layer
        remove(recognizer: recognizer, from: layer)
        recognizer.isSelected = true
        // KSPlayer dispatches audio to the first selected recognizer.
        layer.options.audioRecognizes.insert(recognizer, at: 0)
        #else
        attachedLayer = layer
        statusMessage = "当前播放器不支持字幕识别。"
        #endif
    }

    #endif

    public func stop() {
        generation &+= 1
        runTask?.cancel()
        runTask = nil
        #if canImport(KSPlayer)
        recognizer?.finish()
        detachRecognizer()
        #endif
        text = ""
        segmentID = nil
        statusMessage = nil
        lastResultInstant = nil
        currentSourceLanguage = nil
        updateHandler = nil
    }

    public nonisolated static func resourceStatus(
        sourceLanguage: String
    ) async -> LiveSubtitleResourceStatus {
        await availability(sourceLanguage: sourceLanguage).status
    }

    public nonisolated static func availability(
        sourceLanguage: String
    ) async -> LiveSubtitleAvailability {
        #if !canImport(KSPlayer)
        return .init(status: .unsupported, unavailableReason: .playerBackend)
        #else
        guard #available(iOS 26, macOS 26, tvOS 26, *) else {
            return .init(status: .unsupported, unavailableReason: .systemVersion)
        }
        guard SpeechTranscriber.isAvailable else {
            #if targetEnvironment(simulator)
            return .init(status: .unsupported, unavailableReason: .simulator)
            #else
            return .init(status: .unsupported, unavailableReason: .speechUnavailable)
            #endif
        }
        guard let locale = await supportedLocale(for: sourceLanguage) else {
            return .init(status: .unsupported, unavailableReason: .sourceLanguage)
        }

        do {
            let status = try await LiveSubtitleReservations.shared.withLease(locale: locale) { _ in
                await reservedResourceStatus(locale: locale)
            }
            return .init(status: status, unavailableReason: status == .unsupported ? .sourceLanguage : nil)
        } catch {
            return .init(status: .unavailable)
        }
        #endif
    }

    public nonisolated static func supportedLanguages() async -> [Locale] {
        guard #available(iOS 26, macOS 26, tvOS 26, *),
              SpeechTranscriber.isAvailable else { return [] }
        return await SpeechTranscriber.supportedLocales.sorted {
            $0.identifier(.bcp47) < $1.identifier(.bcp47)
        }
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private nonisolated static func reservedResourceStatus(
        locale: Locale
    ) async -> LiveSubtitleResourceStatus {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .unsupported:
            return .unsupported
        case .downloading:
            return .downloading
        case .supported:
            return .needsDownload
        case .installed:
            let installedLocales = await SpeechTranscriber.installedLocales
            return installedLocales.contains(locale) ? .ready : .needsDownload
        @unknown default:
            return .unsupported
        }
    }

    public nonisolated static func downloadResources(
        sourceLanguage: String,
        progress: @MainActor @escaping @Sendable (Double) -> Void
    ) async throws {
        #if !canImport(KSPlayer)
        throw LiveSubtitleError.unsupported
        #else
        guard #available(iOS 26, macOS 26, tvOS 26, *) else {
            throw LiveSubtitleError.unsupported
        }
        guard SpeechTranscriber.isAvailable,
              let locale = await supportedLocale(for: sourceLanguage)
        else {
            throw LiveSubtitleError.unsupported
        }

        try await LiveSubtitleReservations.shared.withLease(locale: locale) { lease in
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let status = await reservedResourceStatus(locale: locale)
            guard status != .unsupported else {
                throw LiveSubtitleError.unsupported
            }
            if status != .ready {
                guard let request = try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                ) else {
                    throw LiveSubtitleError.downloadUnavailable
                }

                try await withThrowingTaskGroup(of: DownloadEvent.self) { group in
                    group.addTask {
                        try await request.downloadAndInstall()
                        return .finished
                    }
                    group.addTask {
                        while !Task.isCancelled {
                            let fraction = min(max(request.progress.fractionCompleted, 0), 1)
                            await progress(fraction)
                            try await Task.sleep(for: .milliseconds(250))
                        }
                        return .progressObserverStopped
                    }

                    while let event = try await group.next() {
                        if event == .finished {
                            group.cancelAll()
                            break
                        }
                    }
                }
            }

            guard await reservedResourceStatus(locale: locale) == .ready else {
                throw LiveSubtitleError.downloadDidNotInstall
            }
            try Task.checkCancellation()
            LiveSubtitleReservations.shared.retain(lease)
            progress(1)
        }
        #endif
    }

    #if canImport(KSPlayer)
    private func performRun(
        layer: KSPlayerLayer,
        sourceLanguage: String?,
        resourcePreparation: LiveSubtitleResourcePreparation?,
        generation currentGeneration: UInt
    ) async {
        guard #available(iOS 26, macOS 26, tvOS 26, *) else {
            publish(.unavailable, message: LiveSubtitleUnavailableReason.systemVersion.message, generation: currentGeneration)
            return
        }
        guard SpeechTranscriber.isAvailable else {
            #if targetEnvironment(simulator)
            let reason = LiveSubtitleUnavailableReason.simulator
            #else
            let reason = LiveSubtitleUnavailableReason.speechUnavailable
            #endif
            publish(.unavailable, message: reason.message, generation: currentGeneration)
            return
        }

        if sourceLanguage == nil {
            guard await prepareLanguageDetection(
                resourcePreparation: resourcePreparation,
                generation: currentGeneration
            ) else { return }
        }
        guard !Task.isCancelled, generation == currentGeneration else { return }

        // Unknown language must not prevent capture. The single consumer below
        // owns conversion; language detection only receives immutable snapshots.
        let recognizer = LiveAudioRecognizer(languageCode: sourceLanguage)
        self.recognizer = recognizer
        attach(layer: layer)
        let detector = LiveAudioLanguageDetector(resources: languageDetectionResources)
        let audio = LiveSubtitleAudioCoordinator(languageIsKnown: sourceLanguage != nil) { samples in
            try await detector.detect(samples: samples, sampleRate: 16_000)
        }
        guard let detectionFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            recognizer.finish()
            publish(.failed, message: "无法读取直播声音，请重试。", generation: currentGeneration)
            return
        }
        if sourceLanguage == nil {
            publish(.waitingForSpeech, message: "正在等主播说话…", generation: currentGeneration)
        }

        do {
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        var converter = LiveAudioConverter(analyzerFormat: detectionFormat)
                        for await chunk in recognizer.audioChunks {
                            try Task.checkCancellation()
                            guard let buffer = try converter.convert(chunk),
                                  let channel = buffer.floatChannelData?[0] else { continue }
                            let samples = Array(UnsafeBufferPointer(
                                start: channel,
                                count: Int(buffer.frameLength)
                            ))
                            try await audio.append(samples)
                        }
                    }
                    group.addTask {
                        if let sourceLanguage {
                            await self.prepareAndTranscribe(
                                sourceLanguage: sourceLanguage,
                                resourcePreparation: resourcePreparation,
                                audio: audio,
                                generation: currentGeneration
                            )
                            return
                        }
                        for await event in audio.events {
                            try Task.checkCancellation()
                            switch event {
                            case .waitingForSpeech:
                                await self.publish(.waitingForSpeech, message: "正在等主播说话…", generation: currentGeneration)
                            case .detecting:
                                await self.publish(.detecting, message: "正在识别主播语言…", generation: currentGeneration)
                            case let .detected(language):
                                await self.prepareAndTranscribe(
                                    sourceLanguage: language,
                                    resourcePreparation: resourcePreparation,
                                    audio: audio,
                                    generation: currentGeneration
                                )
                                return
                            case .uncertain:
                                await self.publish(.manualSelectionRequired, message: "没能识别主播语言，请手动选择。", generation: currentGeneration)
                                return
                            case let .failed(message):
                                await self.publish(.failed, message: message, generation: currentGeneration)
                                return
                            }
                        }
                    }
                    group.addTask {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(1))
                            await self.clearTextIfInactive(generation: currentGeneration)
                        }
                    }
                    do {
                        _ = try await group.next()
                        recognizer.finish()
                        await audio.finish()
                        group.cancelAll()
                    } catch {
                        recognizer.finish()
                        await audio.finish()
                        group.cancelAll()
                        throw error
                    }
                }
            } onCancel: {
                recognizer.finish()
                Task { await audio.finish() }
            }
        } catch is CancellationError {
            // Stopped or superseded sessions never publish a new room status.
        } catch {
            if !Task.isCancelled {
                publish(.failed, message: "无法读取直播声音，请重试。", generation: currentGeneration)
            }
        }
        await audio.finish()
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func prepareLanguageDetection(
        resourcePreparation: LiveSubtitleResourcePreparation?,
        generation currentGeneration: UInt
    ) async -> Bool {
        let resources = languageDetectionResources
        var status = await resources.status()
        guard !Task.isCancelled, generation == currentGeneration else { return false }
        do {
            status = try await waitForLanguageDownload(status, resources: resources, generation: currentGeneration)
        } catch { return false }
        if status == .needsDownload, resourcePreparation == .languageDetection {
            publish(.downloadingModel, message: "正在下载字幕识别文件…", progress: 0, generation: currentGeneration)
            do {
                try await resources.download { [weak self] fraction in
                    self?.publish(.downloadingModel, message: "正在下载字幕识别文件…", progress: fraction, generation: currentGeneration)
                }
                try Task.checkCancellation()
                status = await resources.status()
            } catch LiveLanguageDetectionResourceError.downloadInProgress {
                status = .downloading
            } catch is CancellationError {
                return false
            } catch {
                publish(.failed, message: "字幕识别文件下载失败，请检查网络后重试。", generation: currentGeneration)
                return false
            }
        }
        do {
            status = try await waitForLanguageDownload(status, resources: resources, generation: currentGeneration)
        } catch { return false }
        guard !Task.isCancelled, generation == currentGeneration else { return false }
        switch status {
        case .ready:
            return true
        case .needsDownload:
            publish(.modelDownloadRequired, message: "请先下载字幕识别文件，下载后继续开启字幕。", generation: currentGeneration)
        case .downloading:
            publish(.downloadingModel, message: "字幕识别文件正在下载。", generation: currentGeneration)
        case .unsupported:
            publish(.unavailable, message: "这台设备无法识别主播语言。", generation: currentGeneration)
        case .unavailable:
            publish(.failed, message: "字幕识别文件暂时无法使用，请重试。", generation: currentGeneration)
        }
        return false
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func waitForLanguageDownload(
        _ initialStatus: LiveSubtitleResourceStatus,
        resources: LiveLanguageDetectionResources,
        generation currentGeneration: UInt
    ) async throws -> LiveSubtitleResourceStatus {
        var status = initialStatus
        if status == .downloading {
            publish(.downloadingModel, message: "正在下载字幕识别文件…", generation: currentGeneration)
        }
        while status == .downloading {
            try await Task.sleep(for: .milliseconds(250))
            guard generation == currentGeneration else { throw CancellationError() }
            status = await resources.status()
            try Task.checkCancellation()
        }
        return status
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func prepareAndTranscribe(
        sourceLanguage: String,
        resourcePreparation: LiveSubtitleResourcePreparation?,
        audio: LiveSubtitleAudioCoordinator,
        generation currentGeneration: UInt
    ) async {
        guard !Task.isCancelled, generation == currentGeneration else { return }
        currentSourceLanguage = sourceLanguage
        publish(.preparing, message: "正在启动语音识别…", generation: currentGeneration)
        guard let locale = await Self.supportedLocale(for: sourceLanguage) else {
            publish(.unavailable, message: "系统不支持识别主播说的这种语言。", generation: currentGeneration)
            return
        }
        guard !Task.isCancelled, generation == currentGeneration else { return }
        currentSourceLanguage = locale.identifier(.bcp47)
        do {
            try await LiveSubtitleReservations.shared.withLease(locale: locale) { _ in
                var status = await Self.reservedResourceStatus(locale: locale)
                status = try await waitForSpeechDownload(status, locale: locale, generation: currentGeneration)
                try Task.checkCancellation()
                guard generation == currentGeneration else { return }
                // Authorization is limited to this exact language request. A
                // previous model download never authorizes a Speech download.
                if status == .needsDownload,
                   case let .speech(authorizedLanguage) = resourcePreparation,
                   authorizedLanguage == sourceLanguage {
                    publish(.downloadingSpeechResources, message: "正在下载系统语音包…", progress: 0, generation: currentGeneration)
                    try await Self.downloadResources(sourceLanguage: sourceLanguage) { [weak self] fraction in
                        self?.publish(.downloadingSpeechResources, message: "正在下载系统语音包…", progress: fraction, generation: currentGeneration)
                    }
                    try Task.checkCancellation()
                    status = await Self.reservedResourceStatus(locale: locale)
                    status = try await waitForSpeechDownload(status, locale: locale, generation: currentGeneration)
                }
                guard !Task.isCancelled, generation == currentGeneration else { return }
                switch status {
                case .ready:
                    await transcribe(locale: locale, audio: audio, generation: currentGeneration)
                case .needsDownload:
                    publish(.speechResourcesRequired, message: "请先下载对应语言的系统语音包。", generation: currentGeneration)
                case .downloading:
                    publish(.downloadingSpeechResources, message: "系统语音包正在下载。", generation: currentGeneration)
                case .unsupported:
                    publish(.unavailable, message: "这台设备不支持识别这种语言。", generation: currentGeneration)
                case .unavailable:
                    publish(.failed, message: "系统语音包暂时无法使用，请重试。", generation: currentGeneration)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            publish(.failed, message: "系统语音包暂时无法使用，请重试。", generation: currentGeneration)
        }
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func waitForSpeechDownload(
        _ initialStatus: LiveSubtitleResourceStatus,
        locale: Locale,
        generation currentGeneration: UInt
    ) async throws -> LiveSubtitleResourceStatus {
        var status = initialStatus
        if status == .downloading {
            publish(.downloadingSpeechResources, message: "正在下载系统语音包…", generation: currentGeneration)
        }
        while status == .downloading {
            try await Task.sleep(for: .milliseconds(250))
            guard generation == currentGeneration else { throw CancellationError() }
            status = await Self.reservedResourceStatus(locale: locale)
            try Task.checkCancellation()
        }
        return status
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func transcribe(
        locale: Locale,
        audio: LiveSubtitleAudioCoordinator,
        generation currentGeneration: UInt
    ) async {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            publish(.failed, message: "无法读取直播声音，请重试。", generation: currentGeneration)
            return
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Analyzer demand drains the same eight-second rolling window used for
        // pre-roll. No unbounded packet queue grows while Speech is suspended.
        let input = AsyncThrowingStream<AnalyzerInput, Error>(unfolding: {
            try await audio.nextSpeechInput()
        })
        do {
            try await withTaskCancellationHandler {
                try await analyzer.prepareToAnalyze(in: analyzerFormat)
                try Task.checkCancellation()
                guard generation == currentGeneration else { throw CancellationError() }
                try await audio.installSpeechInput(format: analyzerFormat)
                publish(.transcribing, generation: currentGeneration)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        _ = try await analyzer.analyzeSequence(input)
                    }
                    group.addTask {
                        for try await result in transcriber.results {
                            try Task.checkCancellation()
                            await self.setText(
                                String(result.text.characters),
                                segmentID: String(result.range.start.seconds),
                                generation: currentGeneration
                            )
                        }
                    }
                    do {
                        _ = try await group.next()
                        await audio.finish()
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                    } catch {
                        await audio.finish()
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                }
            } onCancel: {
                Task {
                    await audio.finish()
                    await analyzer.cancelAndFinishNow()
                }
            }
        } catch is CancellationError {
            // Cancellation is handled by the room's newer activation.
        } catch {
            if !Task.isCancelled {
                publish(.failed, message: "字幕识别已停止，请重新开启。", generation: currentGeneration)
            }
        }
        await audio.finish()
        await analyzer.cancelAndFinishNow()
    }

    private func publish(
        _ phase: LiveSubtitlePhase,
        message: String? = nil,
        progress: Double? = nil,
        generation expectedGeneration: UInt
    ) {
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        switch phase {
        case .unavailable, .failed, .manualSelectionRequired, .modelDownloadRequired, .speechResourcesRequired:
            statusMessage = message
        default:
            statusMessage = nil
        }
        updateHandler?(LiveSubtitleUpdate(
            phase: phase,
            sourceLanguage: currentSourceLanguage,
            message: message,
            downloadProgress: progress
        ))
    }

    private func setText(_ newText: String, segmentID newSegmentID: String, generation expectedGeneration: UInt) {
        guard generation == expectedGeneration else { return }
        segmentID = newSegmentID
        text = newText
        lastResultInstant = .now
    }

    private func clearTextIfInactive(generation expectedGeneration: UInt) {
        guard generation == expectedGeneration else { return }
        let isPaused = attachedLayer?.player.isPlaying == false
        let hasTimedOut = lastResultInstant.map {
            $0.duration(to: .now) >= .seconds(4.5)
        } ?? true
        if isPaused || hasTimedOut {
            text = ""
            segmentID = nil
        }
    }

    private func detachRecognizer() {
        #if canImport(KSPlayer)
        if let recognizer, let attachedLayer {
            remove(recognizer: recognizer, from: attachedLayer)
        }
        recognizer?.isSelected = false
        recognizer = nil
        #endif
        attachedLayer = nil
    }

    #if canImport(KSPlayer)
    private func remove(recognizer: any LiveAudioRecognizing, from layer: KSPlayerLayer) {
        layer.options.audioRecognizes.removeAll { candidate in
            candidate === recognizer
        }
    }

    #endif

    #endif

    @available(iOS 26, macOS 26, tvOS 26, *)
    private nonisolated static func supportedLocale(for identifier: String) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        return await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: identifier)
        )
    }
}

#if canImport(KSPlayer)
private protocol LiveAudioRecognizing: AudioRecognize {
    var audioChunks: AsyncStream<LiveAudioChunk> { get }
    func finish()
}

@available(iOS 18, macOS 15, tvOS 18, *)
private final class LiveAudioRecognizer: LiveAudioRecognizing {
    let subtitleID = "host.live-subtitle"
    let name = "Live Subtitles"
    let delay: TimeInterval = 0
    let languageCode: String?
    let isSrt = false
    let audioChunks: AsyncStream<LiveAudioChunk>

    // KSPlayer reads selection on its render callback while the UI actor binds and unbinds it.
    // This is the only mutable value shared across those isolation domains.
    private let selection = Mutex(false)
    private let continuation: AsyncStream<LiveAudioChunk>.Continuation

    var isSelected: Bool {
        get { selection.withLock { $0 } }
        set { selection.withLock { $0 = newValue } }
    }

    init(languageCode: String?) {
        self.languageCode = languageCode
        let pair = AsyncStream<LiveAudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(12)
        )
        audioChunks = pair.stream
        continuation = pair.continuation
    }

    func append(frame: AudioFrame) {
        guard isSelected, let chunk = LiveAudioChunk(frame: frame) else { return }
        continuation.yield(chunk)
    }

    func finish() {
        continuation.finish()
    }

    func search(with _: KSSubtitleQuery) async -> [SubtitlePart] {
        []
    }
}

struct LiveAudioChunk: Sendable {
    private enum SampleFormat: Sendable {
        case float32
        case int16
        case int32

        var commonFormat: AVAudioCommonFormat {
            switch self {
            case .float32: .pcmFormatFloat32
            case .int16: .pcmFormatInt16
            case .int32: .pcmFormatInt32
            }
        }
    }

    private let sampleFormat: SampleFormat
    private let sampleRate: Double
    private let channelCount: AVAudioChannelCount
    private let isInterleaved: Bool
    private let frameLength: AVAudioFrameCount
    private let planes: [Data]

    init?(monoSamples: [Float]) {
        guard !monoSamples.isEmpty, monoSamples.count <= Int(UInt32.max) else { return nil }
        sampleFormat = .float32
        sampleRate = 16_000
        channelCount = 1
        isInterleaved = false
        frameLength = AVAudioFrameCount(monoSamples.count)
        planes = [monoSamples.withUnsafeBytes { Data($0) }]
    }

    init?(frame: AudioFrame) {
        guard frame.numberOfSamples > 0,
              frame.audioFormat.sampleRate > 0,
              frame.audioFormat.channelCount > 0,
              frame.dataSize > 0
        else {
            return nil
        }
        switch frame.audioFormat.commonFormat {
        case .pcmFormatFloat32:
            sampleFormat = .float32
        case .pcmFormatInt16:
            sampleFormat = .int16
        case .pcmFormatInt32:
            sampleFormat = .int32
        default:
            return nil
        }

        sampleRate = frame.audioFormat.sampleRate
        channelCount = frame.audioFormat.channelCount
        isInterleaved = frame.audioFormat.isInterleaved
        frameLength = AVAudioFrameCount(frame.numberOfSamples)
        let expectedPlaneCount = isInterleaved ? 1 : Int(channelCount)
        let bytesPerSample: Int
        switch sampleFormat {
        case .float32, .int32:
            bytesPerSample = 4
        case .int16:
            bytesPerSample = 2
        }
        let samplesPerPlane = Int(frameLength) * (isInterleaved ? Int(channelCount) : 1)
        let byteCount = samplesPerPlane * bytesPerSample
        guard frame.data.count == expectedPlaneCount,
              Int(frame.dataSize) >= byteCount
        else {
            return nil
        }
        planes = frame.data.compactMap { pointer in
            pointer.map { Data(bytes: $0, count: byteCount) }
        }
        guard planes.count == expectedPlaneCount else { return nil }
    }

    func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: sampleFormat.commonFormat,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: isInterleaved
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        buffer.frameLength = frameLength

        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard audioBuffers.count == planes.count else { return nil }
        for index in audioBuffers.indices {
            guard let destination = audioBuffers[index].mData,
                  Int(audioBuffers[index].mDataByteSize) >= planes[index].count
            else {
                return nil
            }
            let byteCount = planes[index].count
            planes[index].withUnsafeBytes { source in
                guard let sourceAddress = source.baseAddress else { return }
                destination.copyMemory(from: sourceAddress, byteCount: byteCount)
            }
            audioBuffers[index].mDataByteSize = UInt32(byteCount)
        }
        return buffer
    }
}

@available(iOS 26, macOS 26, tvOS 26, *)
struct LiveAudioConverter {
    private let analyzerFormat: AVAudioFormat
    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
    }

    mutating func convert(_ chunk: LiveAudioChunk) throws -> AVAudioPCMBuffer? {
        guard let sourceBuffer = chunk.makePCMBuffer() else {
            throw LiveSubtitleError.invalidAudioFrame
        }
        if sourceBuffer.format == analyzerFormat {
            return sourceBuffer
        }
        if sourceFormat != sourceBuffer.format {
            sourceFormat = sourceBuffer.format
            converter = AVAudioConverter(from: sourceBuffer.format, to: analyzerFormat)
        }
        guard let converter else {
            throw LiveSubtitleError.audioConversionUnavailable
        }

        let rateRatio = analyzerFormat.sampleRate / sourceBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * rateRatio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: max(capacity, 1)
        ) else {
            throw LiveSubtitleError.audioConversionUnavailable
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        if status == .error || conversionError != nil {
            throw LiveSubtitleError.audioConversionFailed
        }
        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }
}
#endif

private enum DownloadEvent: Sendable {
    case finished
    case progressObserverStopped
}

private enum LiveSubtitleError: LocalizedError {
    case unsupported
    case downloadUnavailable
    case downloadDidNotInstall
    case invalidAudioFrame
    case audioConversionUnavailable
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "这台设备不支持识别这种语言。"
        case .downloadUnavailable:
            "系统语音包下载失败，请重试。"
        case .downloadDidNotInstall:
            "系统语音包还没下载完成，请稍后重试。"
        case .invalidAudioFrame:
            "无法读取直播声音，请重试。"
        case .audioConversionUnavailable:
            "无法读取直播声音，请重试。"
        case .audioConversionFailed:
            "无法读取直播声音，请重试。"
        }
    }
}
