import AVFoundation
import Foundation
import Speech
import Testing
@testable import AngelLiveDependencies
import AngelLiveCore

#if canImport(KSPlayer)
import KSPlayer
@Suite("Live subtitle audio coordination")
struct LiveSubtitleAudioCoordinatorTests {
    #if os(macOS)
    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test(
        "Player PCM automatically determines language and reaches native transcription",
        .enabled(if: ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_AUTOMATIC_AUDIO_FIXTURE"] != nil),
        .timeLimit(.minutes(2))
    )
    @MainActor
    func automaticPlayerSpeechLifecycle() async throws {
        let fixturePath = try #require(ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_AUTOMATIC_AUDIO_FIXTURE"])
        let modelDirectory = try #require(ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_LANGUAGE_MODEL_DIRECTORY"])
        let resources = LiveLanguageDetectionResources(directory: URL(fileURLWithPath: modelDirectory, isDirectory: true))
        #expect(await resources.status() == .ready)
        let speechStatus = await LiveSubtitleSession.resourceStatus(sourceLanguage: "en-US")
        guard speechStatus == .ready else {
            throw AutomaticSubtitleIntegrationError.preconditionUnavailable("Installed English Speech resources are required; the test never downloads them.")
        }
        let options = KSOptions()
        options.playerTypes = [KSMEPlayer.self]
        options.isAutoPlay = true
        let layer = KSPlayerLayer(url: URL(fileURLWithPath: fixturePath), options: options)
        layer.player.isMuted = true
        let session = LiveSubtitleSession(languageDetectionResources: resources)
        let observations = AutomaticSubtitleObservations()
        defer {
            session.stop()
            layer.player.stop()
        }
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !layer.player.isReadyToPlay, ContinuousClock.now < readyDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard layer.player.isReadyToPlay else {
            throw AutomaticSubtitleIntegrationError.preconditionUnavailable("KSMEPlayer did not become ready for the neutral fixture.")
        }
        let started = ContinuousClock.now
        // No source language is supplied: the production model determines it.
        let task = Task {
            await session.run(layer: layer) { observations.updates.append($0) }
        }
        defer { task.cancel() }
        let speechDeadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < speechDeadline {
            try await Task.sleep(for: .milliseconds(50))
            if let update = observations.updates.last,
               [LiveSubtitlePhase.failed, .unavailable, .modelDownloadRequired,
                .speechResourcesRequired, .manualSelectionRequired].contains(update.phase) {
                throw AutomaticSubtitleIntegrationError.sessionFailed(update.message ?? "The automatic subtitle attempt stopped.")
            }
            if session.text.localizedCaseInsensitiveContains("subtitle") {
                break
            }
        }
        let recognized = session.text
        let elapsed = started.duration(to: .now)
        #expect(recognized.localizedCaseInsensitiveContains("subtitle"))
        #expect(observations.updates.contains { $0.phase == .waitingForSpeech })
        #expect(observations.updates.contains { $0.phase == .detecting })
        #expect(observations.updates.contains { $0.phase == .transcribing && $0.sourceLanguage?.hasPrefix("en") == true })
        #expect(!observations.updates.contains { $0.phase == .manualSelectionRequired })
        session.stop()
        await task.value
        #expect(session.text.isEmpty)
        #expect(!layer.options.audioRecognizes.contains { $0.subtitleID == "host.live-subtitle" })
        let evidence = AutomaticSubtitleIntegrationEvidence(
            language: observations.updates.last?.sourceLanguage,
            phases: observations.updates.map { String(describing: $0.phase) },
            sourceText: recognized,
            firstSpeechSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            tapRemovedAfterStop: !layer.options.audioRecognizes.contains { $0.subtitleID == "host.live-subtitle" }
        )
        print("ANGELLIVE_AUTOMATIC_SUBTITLE_INTEGRATION " + String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self))
    }
    #endif

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("Silence always returns to waiting for fresh speech", .timeLimit(.minutes(1)))
    func silenceDoesNotAskForLanguage() async throws {
        let audio = LiveSubtitleAudioCoordinator { _ in .noSpeech }
        var events = audio.events.makeAsyncIterator()
        for _ in 0..<3 {
            try await audio.append([Float](repeating: 0, count: 4 * 16_000))
            #expect(await events.next() == .detecting)
            #expect(await events.next() == .waitingForSpeech)
        }
        await audio.finish()
        #expect(await events.next() == nil)
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("Speech arriving during a silent-window inference is included in the next window", .timeLimit(.minutes(1)))
    func silentInferenceDoesNotSkipIncomingSpeech() async throws {
        let detector = ControlledSubtitleDetector(subsequentResult: .detected(languageCode: "fr", probability: 1, margin: 1))
        let audio = LiveSubtitleAudioCoordinator { samples in await detector.detect(samples) }
        var events = audio.events.makeAsyncIterator()
        try await audio.append([Float](repeating: 0, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        await detector.waitForCall()
        try await audio.append([Float](repeating: 0.4, count: 16_000))
        try await audio.append([Float](repeating: 0, count: 3 * 16_000))
        await detector.resolve(.noSpeech)
        #expect(await events.next() == .waitingForSpeech)
        #expect(await events.next() == .detecting)
        #expect(await events.next() == .detected("fr"))
        let windows = await detector.windows
        #expect(windows.count == 2)
        let nextWindow = try #require(windows.last)
        #expect(nextWindow.count == 4 * 16_000)
        #expect(Array(nextWindow.prefix(16_000)) == [Float](repeating: 0.4, count: 16_000))
        await audio.finish()
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("Uncertain speech retries at eight seconds before manual selection", .timeLimit(.minutes(1)))
    func uncertainSpeechUsesLongerWindow() async throws {
        let detector = RecordingSubtitleDetector(results: [.uncertain, .uncertain])
        let audio = LiveSubtitleAudioCoordinator { samples in
            await detector.detect(samples)
        }
        var events = audio.events.makeAsyncIterator()
        try await audio.append([Float](repeating: 0.2, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        try await audio.append([Float](repeating: 0.3, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        #expect(await events.next() == .uncertain)
        #expect(await detector.windowSizes == [4 * 16_000, 8 * 16_000])
        await audio.finish()
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("A longer speech window can resolve a dynamic language", .timeLimit(.minutes(1)))
    func longerWindowDetectsLanguage() async throws {
        let detector = RecordingSubtitleDetector(results: [
            .uncertain,
            .detected(languageCode: "fr", probability: 0.95, margin: 0.85)
        ])
        let audio = LiveSubtitleAudioCoordinator { samples in await detector.detect(samples) }
        var events = audio.events.makeAsyncIterator()
        try await audio.append([Float](repeating: 0.1, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        try await audio.append([Float](repeating: 0.2, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        #expect(await events.next() == .detected("fr"))
        await audio.finish()
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("Inference errors are distinct from language uncertainty", .timeLimit(.minutes(1)))
    func modelFailureDoesNotAskForLanguage() async throws {
        let audio = LiveSubtitleAudioCoordinator { _ in
            throw LiveAudioLanguageDetectionError.modelUnavailable
        }
        var events = audio.events.makeAsyncIterator()
        try await audio.append([Float](repeating: 0.2, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        guard case .failed = await events.next() else {
            Issue.record("A model failure must produce a failed event.")
            await audio.finish()
            return
        }
        await audio.finish()
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("The PCM consumer continues during detection and hands off only the latest eight seconds", .timeLimit(.minutes(1)))
    func boundedHandoffWhileDetecting() async throws {
        let detector = ControlledSubtitleDetector()
        let audio = LiveSubtitleAudioCoordinator { samples in await detector.detect(samples) }
        var events = audio.events.makeAsyncIterator()
        try await audio.append([Float](repeating: 0.1, count: 4 * 16_000))
        #expect(await events.next() == .detecting)
        await detector.waitForCall()
        // Inference remains suspended while the sole PCM consumer appends.
        try await audio.append([Float](repeating: 0.2, count: 8 * 16_000))
        try await audio.append([Float](repeating: 0.3, count: 4 * 16_000))
        let format = try analyzerFormat()
        try await audio.installSpeechInput(format: format)
        let preRoll = try #require(try await audio.nextSpeechInput())
        let preRollSamples = try samples(in: preRoll)
        #expect(preRollSamples.count == 8 * 16_000)
        #expect(preRollSamples.prefix(4 * 16_000).allSatisfy { abs($0 - 0.2) < 0.0001 })
        #expect(preRollSamples.suffix(4 * 16_000).allSatisfy { abs($0 - 0.3) < 0.0001 })
        try await audio.append([Float](repeating: 0.4, count: 1_024))
        let live = try #require(try await audio.nextSpeechInput())
        #expect(live.buffer.frameLength == 1_024)
        #expect(try samples(in: live).allSatisfy { abs($0 - 0.4) < 0.0001 })
        // A canceled inference may return later, but cannot overwrite the
        // installed Speech input or emit a stale language event.
        await detector.resolve(.detected(languageCode: "ja", probability: 1, margin: 1))
        await audio.finish()
        #expect(await events.next() == nil)
        #expect(try await audio.nextSpeechInput() == nil)
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("Finish releases a suspended Speech pull", .timeLimit(.minutes(1)))
    func finishReleasesSpeechConsumer() async throws {
        let audio = LiveSubtitleAudioCoordinator(languageIsKnown: true) { _ in
            Issue.record("A known language must bypass detection.")
            return .uncertain
        }
        let format = try analyzerFormat()
        try await audio.append([Float](repeating: 0.2, count: 4 * 16_000))
        try await audio.installSpeechInput(format: format)
        let preRoll = try #require(try await audio.nextSpeechInput())
        #expect(preRoll.buffer.frameLength == 4 * 16_000)
        let pull = Task { try await audio.nextSpeechInput() }
        await audio.finish()
        #expect(try await pull.value == nil)
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("PCM ring preserves ordered suffixes across wrap and reset")
    func rollingWindowOrder() {
        var window = LiveSubtitlePCMWindow(capacity: 5)
        window.append([1, 2, 3])
        window.append([4, 5, 6, 7])
        #expect(window.count == 5)
        #expect(window.samples() == [3, 4, 5, 6, 7])
        #expect(window.samples(last: 3) == [5, 6, 7])
        window.append([8, 9, 10, 11, 12, 13])
        #expect(window.samples() == [9, 10, 11, 12, 13])
        window.removeAll()
        window.append([14, 15])
        #expect(window.samples() == [14, 15])
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func analyzerFormat() throws -> AVAudioFormat {
        // Exercise buffering and conversion without requiring installed Speech resources.
        try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    private func samples(in input: AnalyzerInput) throws -> [Float] {
        let buffer = input.buffer
        let count = Int(buffer.frameLength)
        if let channel = buffer.int16ChannelData?[0] {
            return UnsafeBufferPointer(start: channel, count: count).map { Float($0) / 32_768 }
        }
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }

}

private actor RecordingSubtitleDetector {
    private var results: [LiveAudioLanguageDetection]
    private(set) var windowSizes: [Int] = []

    init(results: [LiveAudioLanguageDetection]) { self.results = results }

    func detect(_ samples: [Float]) -> LiveAudioLanguageDetection {
        windowSizes.append(samples.count)
        return results.removeFirst()
    }
}

private actor ControlledSubtitleDetector {
    private let subsequentResult: LiveAudioLanguageDetection?
    private(set) var windows: [[Float]] = []
    private var hasBeenCalled = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<LiveAudioLanguageDetection, Never>?

    init(subsequentResult: LiveAudioLanguageDetection? = nil) {
        self.subsequentResult = subsequentResult
    }

    func detect(_ samples: [Float]) async -> LiveAudioLanguageDetection {
        windows.append(samples)
        if hasBeenCalled, let subsequentResult { return subsequentResult }
        hasBeenCalled = true
        arrival?.resume()
        arrival = nil
        return await withCheckedContinuation { result = $0 }
    }

    func waitForCall() async {
        if hasBeenCalled { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func resolve(_ detection: LiveAudioLanguageDetection) {
        result?.resume(returning: detection)
        result = nil
    }
}

#if os(macOS)
@MainActor
private final class AutomaticSubtitleObservations {
    var updates: [LiveSubtitleUpdate] = []
}

private struct AutomaticSubtitleIntegrationEvidence: Encodable {
    let language: String?
    let phases: [String]
    let sourceText: String
    let firstSpeechSeconds: Double
    let tapRemovedAfterStop: Bool
}

private enum AutomaticSubtitleIntegrationError: Error {
    case preconditionUnavailable(String)
    case sessionFailed(String)
}
#endif
#endif
