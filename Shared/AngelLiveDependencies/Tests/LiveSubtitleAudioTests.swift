import AVFoundation
import Foundation
import Speech
import Testing
@testable import AngelLiveDependencies
#if canImport(KSPlayer)
import KSPlayer

@Suite("Live subtitle audio")
struct LiveSubtitleAudioTests {
    #if os(macOS)
    @available(macOS 26, *)
    @Test("Native speech from a synthetic player fixture stops cleanly", .enabled(if: ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_AUDIO_FIXTURE"] != nil))
    @MainActor
    func nativePlayerSpeech() async throws {
        let fixturePath = try #require(ProcessInfo.processInfo.environment["ANGELLIVE_SUBTITLE_AUDIO_FIXTURE"])
        _ = try await AssetInventory.reserve(locale: Locale(identifier: "en-US"))
        let status = await LiveSubtitleSession.resourceStatus(sourceLanguage: "en-US")
        guard case .ready = status else {
            Issue.record("Install the English Speech model explicitly before running this opt-in check.")
            return
        }
        let options = KSOptions()
        options.playerTypes = [KSMEPlayer.self]
        options.isAutoPlay = true
        let layer = KSPlayerLayer(url: URL(fileURLWithPath: fixturePath), options: options)
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
        #expect(layer.player.isReadyToPlay)
        let task = Task { await session.run(layer: layer, sourceLanguage: "en-US") }
        defer { task.cancel() }
        var recognizedText = ""
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if !session.text.isEmpty {
                recognizedText = session.text
                if recognizedText.lowercased().contains("subtitle") { break }
            }
            if session.statusMessage != nil { break }
        }
        print("Synthetic fixture transcription: \(recognizedText)")
        #expect(recognizedText.lowercased().contains("subtitle"))
        #expect(session.statusMessage == nil)
        layer.pause()
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(session.text.isEmpty)
        session.stop()
        await task.value
        #expect(session.text.isEmpty)
        #expect(!layer.options.audioRecognizes.contains { $0.subtitleID == "host.live-subtitle" })
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
#endif
