import AVFoundation
import Foundation
import Observation
import Speech

#if canImport(KSPlayer)
import KSPlayer
import Synchronization
#endif

public enum LiveSubtitleResourceStatus: Sendable {
    case unsupported
    case needsDownload
    case downloading
    case ready
}

@MainActor
@Observable
public final class LiveSubtitleSession {
    public private(set) var text = ""
    public private(set) var segmentID: String?
    public private(set) var statusMessage: String?

    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var runTask: Task<Void, Never>?
    #if canImport(KSPlayer)
    @ObservationIgnored private weak var attachedLayer: KSPlayerLayer?
    @ObservationIgnored private var recognizer: (any LiveAudioRecognizing)?
    #endif
    @ObservationIgnored private var lastResultInstant: ContinuousClock.Instant?

    public init() {}

    #if canImport(KSPlayer)
    public func run(layer: KSPlayerLayer, sourceLanguage: String) async {
        stop()
        let currentGeneration = generation

        #if canImport(KSPlayer)
        guard layer.player is KSMEPlayer else {
            statusMessage = "当前播放内核不支持实时字幕。"
            return
        }
        #else
        statusMessage = "当前播放内核不支持实时字幕。"
        return
        #endif

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRun(
                layer: layer,
                sourceLanguage: sourceLanguage,
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
            statusMessage = "当前播放内核不支持实时字幕。"
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
        statusMessage = "当前播放内核不支持实时字幕。"
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
    }

    public nonisolated static func resourceStatus(
        sourceLanguage: String
    ) async -> LiveSubtitleResourceStatus {
        #if !canImport(KSPlayer)
        return .unsupported
        #else
        guard #available(iOS 26, macOS 26, tvOS 26, *) else {
            return .unsupported
        }
        guard SpeechTranscriber.isAvailable,
              let locale = await supportedLocale(for: sourceLanguage)
        else {
            return .unsupported
        }

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
        #endif
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

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .unsupported else {
            throw LiveSubtitleError.unsupported
        }
        if status == .installed {
            let installedLocales = await SpeechTranscriber.installedLocales
            if installedLocales.contains(locale) {
                _ = try await AssetInventory.reserve(locale: locale)
                await progress(1)
                return
            }
        }
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

        let installedStatus = await AssetInventory.status(forModules: [transcriber])
        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedStatus == .installed, installedLocales.contains(locale) else {
            throw LiveSubtitleError.downloadDidNotInstall
        }
        _ = try await AssetInventory.reserve(locale: locale)
        await progress(1)
        #endif
    }

    #if canImport(KSPlayer)
    private func performRun(
        layer: KSPlayerLayer,
        sourceLanguage: String,
        generation currentGeneration: UInt
    ) async {
        guard #available(iOS 26, macOS 26, tvOS 26, *) else {
            setStatus("此系统版本不支持实时字幕。", generation: currentGeneration)
            return
        }

        switch await Self.resourceStatus(sourceLanguage: sourceLanguage) {
        case .unsupported:
            setStatus("当前语言或设备不支持实时字幕。", generation: currentGeneration)
            return
        case .needsDownload:
            setStatus("请先在设置中下载该语言的语音识别资源。", generation: currentGeneration)
            return
        case .downloading:
            setStatus("该语言的语音识别资源正在下载。", generation: currentGeneration)
            return
        case .ready:
            break
        }
        guard !Task.isCancelled, generation == currentGeneration else { return }

        guard let locale = await Self.supportedLocale(for: sourceLanguage) else {
            setStatus("当前语言或设备不支持实时字幕。", generation: currentGeneration)
            return
        }
        guard !Task.isCancelled, generation == currentGeneration else { return }

        #if canImport(KSPlayer)
        let recognizer = LiveAudioRecognizer(languageCode: locale.identifier)
        guard generation == currentGeneration else { return }
        self.recognizer = recognizer
        statusMessage = nil
        lastResultInstant = nil
        attach(layer: layer)

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            setStatus("当前设备没有可用的语音识别音频格式。", generation: currentGeneration)
            recognizer.finish()
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let inputPair = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(12)
        )
        do {
            try await withTaskCancellationHandler {
                try await analyzer.prepareToAnalyze(in: analyzerFormat)
                try Task.checkCancellation()
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        defer { inputPair.continuation.finish() }
                        var converter = LiveAudioConverter(analyzerFormat: analyzerFormat)
                        for await chunk in recognizer.audioChunks {
                            try Task.checkCancellation()
                            if let buffer = try converter.convert(chunk) {
                                inputPair.continuation.yield(AnalyzerInput(buffer: buffer))
                            }
                        }
                    }
                    group.addTask {
                        _ = try await analyzer.analyzeSequence(inputPair.stream)
                    }
                    group.addTask {
                        for try await result in transcriber.results {
                            try Task.checkCancellation()
                            let latestSegment = String(result.text.characters)
                            await self.setText(
                                latestSegment,
                                segmentID: String(result.range.start.seconds),
                                generation: currentGeneration
                            )
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
                        inputPair.continuation.finish()
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                    } catch {
                        recognizer.finish()
                        inputPair.continuation.finish()
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                }
            } onCancel: {
                recognizer.finish()
                inputPair.continuation.finish()
                Task {
                    await analyzer.cancelAndFinishNow()
                }
            }
            await analyzer.cancelAndFinishNow()
        } catch is CancellationError {
            await analyzer.cancelAndFinishNow()
        } catch {
            await analyzer.cancelAndFinishNow()
            if !Task.isCancelled {
                setStatus("实时字幕识别已停止。", generation: currentGeneration)
            }
        }
        #else
        setStatus("当前播放内核不支持实时字幕。", generation: currentGeneration)
        #endif
    }

    private func setText(_ newText: String, segmentID newSegmentID: String, generation expectedGeneration: UInt) {
        guard generation == expectedGeneration else { return }
        segmentID = newSegmentID
        text = newText
        lastResultInstant = .now
    }

    private func setStatus(_ message: String, generation expectedGeneration: UInt) {
        guard generation == expectedGeneration else { return }
        statusMessage = message
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

    init(languageCode: String) {
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
            "当前设备不支持所选语言的实时字幕。"
        case .downloadUnavailable:
            "暂时无法下载语音识别模型，请稍后重试。"
        case .downloadDidNotInstall:
            "语音识别模型尚未完成安装。"
        case .invalidAudioFrame:
            "播放器提供的音频帧无效。"
        case .audioConversionUnavailable:
            "当前音频格式无法用于语音识别。"
        case .audioConversionFailed:
            "音频格式转换失败。"
        }
    }
}
