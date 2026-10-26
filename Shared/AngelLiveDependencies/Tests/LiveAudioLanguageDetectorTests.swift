import CryptoKit
import Foundation
import Testing
@testable import AngelLiveDependencies

private struct LocalModelDownloader: LiveLanguageModelDownloading {
    let payloads: [String: Data]
    let cancelAfterWriting: Bool
    let temporaryDirectory: URL?

    init(payloads: [String: Data], cancelAfterWriting: Bool = false, temporaryDirectory: URL? = nil) {
        self.payloads = payloads
        self.cancelAfterWriting = cancelAfterWriting
        self.temporaryDirectory = temporaryDirectory
    }

    func download(
        artifact: LiveLanguageModelArtifact,
        progress: @escaping @MainActor @Sendable (Int64) -> Void
    ) async throws -> URL {
        let file = (temporaryDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        let data = payloads[artifact.filename] ?? Data()
        try data.write(to: file)
        await progress(Int64(data.count))
        if cancelAfterWriting {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return file
    }
}

private func modelArtifact(_ filename: String, _ data: Data) -> LiveLanguageModelArtifact {
    LiveLanguageModelArtifact(
        filename: filename,
        url: URL(string: "https://models.example.invalid/" + filename)!,
        bytes: Int64(data.count),
        sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    )
}

private actor RetainedModelProgressDownloader: LiveLanguageModelDownloading {
    enum Outcome: CaseIterable, Sendable { case success, failure, cancelled }

    let outcome: Outcome
    let payload: Data
    private var callbacks: [@MainActor @Sendable (Int64) -> Void] = []

    init(outcome: Outcome, payload: Data) {
        self.outcome = outcome
        self.payload = payload
    }

    func download(
        artifact: LiveLanguageModelArtifact,
        progress: @escaping @MainActor @Sendable (Int64) -> Void
    ) async throws -> URL {
        callbacks.append(progress)
        await progress(Int64(payload.count / 2))
        switch outcome {
        case .success:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try payload.write(to: file)
            return file
        case .failure:
            throw LiveLanguageDetectionResourceError.invalidResponse
        case .cancelled:
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        }
    }

    func emitLateProgress() async {
        for callback in callbacks { await callback(1) }
    }
}

@MainActor
private final class ModelProgressRecorder {
    var values: [Double] = []
}

@Suite("Local audio language detection")
struct LiveAudioLanguageDetectorTests {
    @Test(arguments: RetainedModelProgressDownloader.Outcome.allCases)
    private func completedResourceDownloadsIgnoreLateProgress(
        outcome: RetainedModelProgressDownloader.Outcome
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("local-model".utf8)
        let downloader = RetainedModelProgressDownloader(outcome: outcome, payload: payload)
        let resources = LiveLanguageDetectionResources(
            directory: directory, artifacts: [modelArtifact("model.bin", payload)], downloader: downloader
        )
        let recorder = ModelProgressRecorder()
        let operation = Task {
            try await resources.download { recorder.values.append($0) }
        }
        switch outcome {
        case .success:
            try await operation.value
        case .failure:
            await #expect(throws: LiveLanguageDetectionResourceError.invalidResponse) { try await operation.value }
        case .cancelled:
            await #expect(throws: CancellationError.self) { try await operation.value }
        }
        let completedProgress = await recorder.values
        #expect(completedProgress.contains { $0 > 0 && $0 < 1 })
        await downloader.emitLateProgress()
        #expect(await recorder.values == completedProgress)
    }

    @Test func rejectsWrongRateShortAndNonfiniteAudioBeforeResources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = LiveLanguageDetectionResources(directory: directory)
        let detector = LiveAudioLanguageDetector(resources: resources)
        for (samples, rate) in [([Float](repeating: 0, count: 64_000), 48_000), ([Float](repeating: 0, count: 12), 16_000), ([Float](repeating: .nan, count: 64_000), 16_000)] {
            await #expect(throws: LiveAudioLanguageDetectionError.invalidAudio) {
                try await detector.detect(samples: samples, sampleRate: rate)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func missingResourcesDoNotCreateFilesOrDownload() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = LiveLanguageDetectionResources(directory: directory)
        #expect(await resources.status() == .needsDownload)
        let detector = LiveAudioLanguageDetector(resources: resources)
        await #expect(throws: LiveAudioLanguageDetectionError.resourcesMissing) {
            try await detector.detect(samples: [Float](repeating: 0, count: 64_000))
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func explicitDownloadVerifiesDigestAndRejectsLaterCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Data("language-model".utf8), second = Data("vad-model".utf8)
        let artifacts = [modelArtifact("language.bin", first), modelArtifact("vad.bin", second)]
        let resources = LiveLanguageDetectionResources(
            directory: directory, artifacts: artifacts,
            downloader: LocalModelDownloader(payloads: ["language.bin": first, "vad.bin": second])
        )
        #expect(await resources.status() == .needsDownload)
        try await resources.download { value in #expect((0...1).contains(value)) }
        #expect(await resources.status() == .ready)
        try Data(repeating: 0, count: first.count).write(to: directory.appendingPathComponent("language.bin"))
        #expect(await resources.status() == .needsDownload)
        try await resources.download { _ in }
        #expect(await resources.status() == .ready)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".partial") })
    }

    @Test func badDigestDoesNotPublishModelOrDeleteInstalledSibling() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = Data("language-model".utf8), second = Data("vad-model".utf8)
        try first.write(to: directory.appendingPathComponent("language.bin"))
        let resources = LiveLanguageDetectionResources(
            directory: directory,
            artifacts: [modelArtifact("language.bin", first), modelArtifact("vad.bin", second)],
            downloader: LocalModelDownloader(payloads: ["vad.bin": Data(repeating: 0, count: second.count)], temporaryDirectory: directory)
        )
        await #expect(throws: LiveLanguageDetectionResourceError.invalidModel) {
            try await resources.download { _ in }
        }
        #expect(try Data(contentsOf: directory.appendingPathComponent("language.bin")) == first)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("vad.bin").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["language.bin"])
    }

    @Test func cancelledDownloadPreservesVerifiedModelAndClearsState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = Data("language-model".utf8), second = Data("vad-model".utf8)
        try first.write(to: directory.appendingPathComponent("language.bin"))
        let resources = LiveLanguageDetectionResources(
            directory: directory,
            artifacts: [modelArtifact("language.bin", first), modelArtifact("vad.bin", second)],
            downloader: LocalModelDownloader(payloads: ["vad.bin": second], cancelAfterWriting: true, temporaryDirectory: directory)
        )
        let download = Task { try await resources.download { _ in } }
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await resources.status() == .needsDownload)
        #expect(try Data(contentsOf: directory.appendingPathComponent("language.bin")) == first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["language.bin"])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANGELLIVE_LANGUAGE_MODEL_TEST_DIR"] != nil))
    func realLocalModelsDetectSyntheticSpeechAndRejectNonspeech() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["ANGELLIVE_LANGUAGE_MODEL_TEST_DIR"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let resources = LiveLanguageDetectionResources(directory: directory)
        #expect(await resources.status() == .ready)
        let detector = LiveAudioLanguageDetector(resources: resources)
        for code in ["en", "zh", "ja", "ko"] {
            let samples = try pcm(directory.appendingPathComponent(code + ".f32"), seconds: 4)
            let result = try await detector.detect(samples: samples)
            guard case let .detected(language, probability, margin) = result else {
                Issue.record("No language detected for synthetic speech: \(code)")
                continue
            }
            #expect(language == code)
            #expect(probability >= 0.8 && margin >= 0.2)
        }
        for name in ["silence", "tone", "music", "noise"] {
            let samples = try pcm(directory.appendingPathComponent(name + ".f32"), seconds: 4)
            #expect(try await detector.detect(samples: samples) == .noSpeech)
        }
        let shortNoisy = try pcm(directory.appendingPathComponent("ko-noise.f32"), seconds: 4)
        #expect(try await detector.detect(samples: shortNoisy) == .uncertain)
        let extendedNoisy = try pcm(directory.appendingPathComponent("ko-noise.f32"), seconds: 8)
        guard case let .detected(language, _, _) = try await detector.detect(samples: extendedNoisy) else {
            Issue.record("Extended noisy sample did not resolve a language")
            return
        }
        #expect(language == "ko")
    }

    private func pcm(_ file: URL, seconds: Int) throws -> [Float] {
        let bytes = try Data(contentsOf: file)
        return bytes.withUnsafeBytes { raw in
            (0..<min(seconds * 16_000, raw.count / 4)).map {
                raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self)
            }
        }
    }
}
