import AVFoundation
import Foundation
import Speech
import Testing
@testable import AngelLiveDependencies
#if canImport(Translation)
import Translation
@testable import AngelLiveCore
#endif
#if canImport(KSPlayer)
import KSPlayer

@Suite("Live subtitle audio", .serialized)
struct LiveSubtitleAudioTests {
    #if os(macOS) && canImport(Translation)
    @available(macOS 26.4, *)
    @Test(
        "Synthetic player audio reaches native speech and translation with lifecycle cleanup",
        .enabled(if: ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_AUDIO_FIXTURE"] != nil),
        .timeLimit(.minutes(2))
    )
    @MainActor
    func nativePlayerSpeechTranslationLifecycle() async throws {
        let fixturePath = try #require(ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_AUDIO_FIXTURE"])
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let fixtureDuration = try await AVURLAsset(url: fixtureURL).load(.duration).seconds
        guard fixtureDuration >= 30, fixtureDuration <= 60 else {
            throw LiveSubtitleIntegrationError.invalidFixtureDuration(fixtureDuration)
        }

        let status = await LiveSubtitleSession.resourceStatus(sourceLanguage: "en-US")
        guard case .ready = status else {
            throw LiveSubtitleIntegrationError.speechResourcesUnavailable
        }

        let sourceLanguage = "en"
        let targetLanguage = "zh-Hans"
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let translationStatus = await LanguageAvailability().status(from: source, to: target)
        guard translationStatus == .installed else {
            throw LiveSubtitleIntegrationError.translationResourcesUnavailable
        }

        let suiteName = "LiveSubtitleAudioIntegration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RoomTranslationSettings(
            defaults: defaults,
            secretStorage: LiveSubtitleMemorySecretStorage()
        )
        settings.engine = .apple
        settings.targetLanguage = targetLanguage

        let provider = AppleRoomTranslationProvider.shared
        let hostOwner = UUID()
        provider.setHostExpected(owner: hostOwner, expected: true)
        let installedOnlySession = TranslationSession(installedSource: source, target: target)
        #expect(!installedOnlySession.canRequestDownloads)
        let hostTask = Task {
            await runLiveSubtitleTranslationHost(
                owner: hostOwner,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer {
            pipeline.reset()
            provider.setHostExpected(owner: hostOwner, expected: false)
            hostTask.cancel()
        }

        let options = KSOptions()
        options.playerTypes = [KSMEPlayer.self]
        options.isAutoPlay = true
        let layer = KSPlayerLayer(url: fixtureURL, options: options)
        layer.player.isMuted = true
        let session = LiveSubtitleSession()
        defer {
            session.stop()
            layer.player.stop()
        }
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !layer.player.isReadyToPlay && ContinuousClock.now < readyDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard layer.player.isReadyToPlay else {
            throw LiveSubtitleIntegrationError.playerNotReady
        }
        let runStartedAt = ContinuousClock.now
        let task = Task { await session.run(layer: layer, sourceLanguage: "en-US") }
        defer { task.cancel() }

        var speechObservations: [LiveSubtitleSpeechObservation] = []
        var firstSourceText = ""
        var firstSourceMilliseconds: Double?
        var sourceTextForTranslation = ""
        var sourceSegmentForTranslation = ""
        let firstSpeechDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < firstSpeechDeadline {
            try await Task.sleep(for: .milliseconds(50))
            try checkSessionStatus(session)
            recordSpeechObservation(
                from: session,
                startedAt: runStartedAt,
                observations: &speechObservations
            )
            if firstSourceText.isEmpty, !session.text.isEmpty {
                firstSourceText = session.text
                firstSourceMilliseconds = durationMilliseconds(runStartedAt.duration(to: .now))
            }
            if session.text.localizedCaseInsensitiveContains("subtitle"),
               let segmentID = session.segmentID {
                sourceTextForTranslation = session.text
                sourceSegmentForTranslation = segmentID
                break
            }
        }
        guard !sourceTextForTranslation.isEmpty else {
            throw LiveSubtitleIntegrationError.speechTimedOut
        }

        pipeline.enqueue(
            sourceTextForTranslation,
            sourceLanguage: "en-US",
            segmentID: sourceSegmentForTranslation
        )
        let firstTranslationDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while pipeline.text.isEmpty,
              pipeline.errorMessage == nil,
              ContinuousClock.now < firstTranslationDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let firstTranslation = try requireChineseTranslation(
            pipeline,
            sourceText: sourceTextForTranslation
        )
        let firstTranslationMilliseconds = durationMilliseconds(runStartedAt.duration(to: .now))

        recordSpeechObservation(
            from: session,
            startedAt: runStartedAt,
            observations: &speechObservations
        )
        let pauseStartedAt = ContinuousClock.now
        layer.pause()
        let pauseDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !session.text.isEmpty, ContinuousClock.now < pauseDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.text.isEmpty)
        pipeline.reset()
        #expect(pipeline.text.isEmpty)
        let pauseClearMilliseconds = durationMilliseconds(pauseStartedAt.duration(to: .now))

        let observationsBeforeResume = Set(speechObservations)
        let resumeStartedAt = ContinuousClock.now
        layer.play()
        var resumedSource = ""
        var resumedSegment = ""
        let resumeDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < resumeDeadline {
            try await Task.sleep(for: .milliseconds(50))
            try checkSessionStatus(session)
            recordSpeechObservation(
                from: session,
                startedAt: runStartedAt,
                observations: &speechObservations
            )
            if session.text.localizedCaseInsensitiveContains("subtitle"),
               let segmentID = session.segmentID,
               !observationsBeforeResume.contains(
                   LiveSubtitleSpeechObservation(segmentID: segmentID, text: session.text, milliseconds: 0)
               ) {
                resumedSource = session.text
                resumedSegment = segmentID
                break
            }
        }
        guard !resumedSource.isEmpty else {
            throw LiveSubtitleIntegrationError.resumeTimedOut
        }
        let resumeSpeechMilliseconds = durationMilliseconds(resumeStartedAt.duration(to: .now))

        pipeline.enqueue(
            resumedSource,
            sourceLanguage: "en-US",
            segmentID: resumedSegment
        )
        let resumedTranslationDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while pipeline.text.isEmpty,
              pipeline.errorMessage == nil,
              ContinuousClock.now < resumedTranslationDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let resumedTranslation = try requireChineseTranslation(
            pipeline,
            sourceText: resumedSource
        )

        let sustainedDeadline = runStartedAt.advanced(by: .seconds(30))
        while ContinuousClock.now < sustainedDeadline {
            try await Task.sleep(for: .milliseconds(50))
            try checkSessionStatus(session)
            recordSpeechObservation(
                from: session,
                startedAt: runStartedAt,
                observations: &speechObservations
            )
        }
        let uniqueSpeechUpdates = Set(speechObservations).count
        let uniqueSegmentIDs = Set(speechObservations.map(\.segmentID)).count
        let sustainedRecognitionMilliseconds = durationMilliseconds(runStartedAt.duration(to: .now))
        #expect(uniqueSpeechUpdates >= 4)
        #expect(uniqueSegmentIDs >= 2)

        session.stop()
        await task.value
        #expect(session.text.isEmpty)
        #expect(!layer.options.audioRecognizes.contains { $0.subtitleID == "host.live-subtitle" })

        pipeline.reset()
        #expect(pipeline.text.isEmpty)
        let seekFinished = await withCheckedContinuation { continuation in
            layer.seek(time: 0, autoPlay: true) { finished in
                continuation.resume(returning: finished)
            }
        }
        guard seekFinished else {
            throw LiveSubtitleIntegrationError.seekFailed
        }

        let restartedSession = LiveSubtitleSession()
        let restartStartedAt = ContinuousClock.now
        let restartedTask = Task {
            await restartedSession.run(layer: layer, sourceLanguage: "en-US")
        }
        defer {
            restartedSession.stop()
            restartedTask.cancel()
        }
        var restartedSource = ""
        var restartedSegment = ""
        let restartDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < restartDeadline {
            try await Task.sleep(for: .milliseconds(50))
            try checkSessionStatus(restartedSession)
            if restartedSession.text.localizedCaseInsensitiveContains("subtitle"),
               let segmentID = restartedSession.segmentID {
                restartedSource = restartedSession.text
                restartedSegment = segmentID
                break
            }
        }
        guard !restartedSource.isEmpty else {
            throw LiveSubtitleIntegrationError.restartTimedOut
        }
        let restartSpeechMilliseconds = durationMilliseconds(restartStartedAt.duration(to: .now))

        pipeline.enqueue(
            restartedSource,
            sourceLanguage: "en-US",
            segmentID: restartedSegment
        )
        let restartedTranslationDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while pipeline.text.isEmpty,
              pipeline.errorMessage == nil,
              ContinuousClock.now < restartedTranslationDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let restartedTranslation = try requireChineseTranslation(
            pipeline,
            sourceText: restartedSource
        )

        restartedSession.stop()
        await restartedTask.value
        pipeline.reset()
        #expect(restartedSession.text.isEmpty)
        #expect(pipeline.text.isEmpty)
        #expect(!layer.options.audioRecognizes.contains { $0.subtitleID == "host.live-subtitle" })

        provider.setHostExpected(owner: hostOwner, expected: false)
        hostTask.cancel()
        await hostTask.value

        let evidence = LiveSubtitleIntegrationEvidence(
            fixtureDurationSeconds: fixtureDuration,
            firstSourceText: firstSourceText,
            firstSourceMilliseconds: firstSourceMilliseconds ?? 0,
            translatedSourceText: sourceTextForTranslation,
            firstTranslation: firstTranslation,
            firstTranslationMilliseconds: firstTranslationMilliseconds,
            pauseClearMilliseconds: pauseClearMilliseconds,
            resumeSpeechMilliseconds: resumeSpeechMilliseconds,
            resumedTranslation: resumedTranslation,
            sustainedRecognitionMilliseconds: sustainedRecognitionMilliseconds,
            uniqueSpeechUpdates: uniqueSpeechUpdates,
            uniqueSegmentIDs: uniqueSegmentIDs,
            restartSpeechMilliseconds: restartSpeechMilliseconds,
            restartedTranslation: restartedTranslation
        )
        let evidenceData = try JSONEncoder().encode(evidence)
        print("ANGELLIVE_LIVE_SUBTITLE_INTEGRATION \(String(decoding: evidenceData, as: UTF8.self))")
    }

    @MainActor
    private func checkSessionStatus(_ session: LiveSubtitleSession) throws {
        if let statusMessage = session.statusMessage {
            throw LiveSubtitleIntegrationError.sessionStopped(statusMessage)
        }
    }

    @MainActor
    private func recordSpeechObservation(
        from session: LiveSubtitleSession,
        startedAt: ContinuousClock.Instant,
        observations: inout [LiveSubtitleSpeechObservation]
    ) {
        guard !session.text.isEmpty, let segmentID = session.segmentID else { return }
        let observation = LiveSubtitleSpeechObservation(
            segmentID: segmentID,
            text: session.text,
            milliseconds: durationMilliseconds(startedAt.duration(to: .now))
        )
        guard observations.last?.segmentID != observation.segmentID
                || observations.last?.text != observation.text else { return }
        observations.append(observation)
    }

    @MainActor
    private func requireChineseTranslation(
        _ pipeline: LiveSubtitleTranslationPipeline,
        sourceText: String
    ) throws -> String {
        let translatedText = try #require(
            pipeline.text.isEmpty ? nil : pipeline.text,
            "Native pipeline error: \(pipeline.errorMessage ?? "timed out")"
        )
        #expect(translatedText != sourceText)
        #expect(translatedText.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        })
        return translatedText
    }

    private func durationMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
    #endif

    @Test("Copied PCM survives render frame reuse", arguments: [false, true])
    func copiedPCM(interleaved: Bool) throws {
        let frame = try makeFrame(sampleRate: 48_000, channels: 2, interleaved: interleaved)
        let chunk = try #require(LiveAudioChunk(frame: frame))
        for plane in frame.data {
            plane?.update(repeating: 0, count: Int(frame.dataSize))
        }
        let buffer = try #require(chunk.makePCMBuffer())
        #expect(buffer.frameLength == frame.numberOfSamples)
        #expect(buffer.format == frame.audioFormat)
        let samples = try #require(buffer.floatChannelData)
        #expect(abs(samples[0][interleaved ? 2 : 1]) > 0.001)
    }

    @available(iOS 26, macOS 26, tvOS 26, *)
    @Test("Streaming PCM converts mono and stereo sample rates", arguments: [16_000.0, 44_100.0, 48_000.0], [1, 2])
    func resamples(sampleRate: Double, channels: Int) throws {
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        var converter = LiveAudioConverter(analyzerFormat: target)
        var totalFrames = 0
        for _ in 0..<8 {
            let frame = try makeFrame(sampleRate: sampleRate, channels: channels, interleaved: false)
            let chunk = try #require(LiveAudioChunk(frame: frame))
            if let output = try converter.convert(chunk) {
                #expect(output.format == target)
                let samples = try #require(output.floatChannelData)
                let values = UnsafeBufferPointer(start: samples[0], count: Int(output.frameLength))
                #expect(values.allSatisfy { $0.isFinite })
                #expect(values.contains { abs($0) > 0.001 })
                totalFrames += values.count
            }
        }
        let expected = Double(8 * 1_024) * 16_000 / sampleRate
        #expect(abs(Double(totalFrames) - expected) < 128)
    }

    private func makeFrame(sampleRate: Double, channels: Int, interleaved: Bool) throws -> AudioFrame {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: interleaved))
        let samplesPerPlane = 1_024 * (interleaved ? channels : 1)
        let frame = AudioFrame(dataSize: UInt32(samplesPerPlane * MemoryLayout<Float>.size), audioFormat: format)
        frame.numberOfSamples = 1_024
        for plane in frame.data {
            let pointer = try #require(plane)
            pointer.withMemoryRebound(to: Float.self, capacity: samplesPerPlane) { samples in
                for index in 0..<samplesPerPlane {
                    let sampleIndex = interleaved ? index / channels : index
                    samples[index] = Float(sin(Double(sampleIndex) * 2 * .pi * 440 / sampleRate)) * 0.3
                }
            }
        }
        return frame
    }
}

#if os(macOS) && canImport(Translation)
private struct LiveSubtitleSpeechObservation: Hashable {
    let segmentID: String
    let text: String
    let milliseconds: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segmentID == rhs.segmentID && lhs.text == rhs.text
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(segmentID)
        hasher.combine(text)
    }
}

private struct LiveSubtitleIntegrationEvidence: Encodable {
    let fixtureDurationSeconds: Double
    let firstSourceText: String
    let firstSourceMilliseconds: Double
    let translatedSourceText: String
    let firstTranslation: String
    let firstTranslationMilliseconds: Double
    let pauseClearMilliseconds: Double
    let resumeSpeechMilliseconds: Double
    let resumedTranslation: String
    let sustainedRecognitionMilliseconds: Double
    let uniqueSpeechUpdates: Int
    let uniqueSegmentIDs: Int
    let restartSpeechMilliseconds: Double
    let restartedTranslation: String
}

private enum LiveSubtitleIntegrationError: Error, CustomStringConvertible {
    case invalidFixtureDuration(Double)
    case playerNotReady
    case speechResourcesUnavailable
    case translationResourcesUnavailable
    case speechTimedOut
    case resumeTimedOut
    case seekFailed
    case restartTimedOut
    case sessionStopped(String)

    var description: String {
        switch self {
        case let .invalidFixtureDuration(duration):
            "Expected a 30-60 second fixture, got \(duration) seconds."
        case .playerNotReady:
            "KSMEPlayer did not become ready for the synthetic fixture."
        case .speechResourcesUnavailable:
            "The installed English Speech resource is unavailable. This test never downloads it."
        case .translationResourcesUnavailable:
            "The installed default en to zh-Hans Translation resource is unavailable. This test never downloads it."
        case .speechTimedOut:
            "Production speech recognition did not produce the expected neutral fixture text."
        case .resumeTimedOut:
            "Production speech recognition did not resume after the player resumed."
        case .seekFailed:
            "KSMEPlayer could not seek the synthetic fixture to the beginning for restart."
        case .restartTimedOut:
            "Production speech recognition did not restart after stop and seek-to-start."
        case let .sessionStopped(message):
            "Production LiveSubtitleSession stopped: \(message)"
        }
    }
}

private final class LiveSubtitleMemorySecretStorage: RoomTranslationSecretStorage {
    private var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

@available(macOS 26.4, *)
private nonisolated func runLiveSubtitleTranslationHost(
    owner: UUID,
    sourceLanguage: String,
    targetLanguage: String
) async {
    let session = TranslationSession(
        installedSource: Locale.Language(identifier: sourceLanguage),
        target: Locale.Language(identifier: targetLanguage)
    )
    await AppleRoomTranslationProvider.hostAction(
        owner: owner,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage
    )(session)
}
#endif
#endif
