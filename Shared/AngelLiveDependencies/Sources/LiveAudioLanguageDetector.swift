import Foundation
import whisper

public enum LiveAudioLanguageDetection: Equatable, Sendable {
    case noSpeech
    case uncertain
    case detected(languageCode: String, probability: Float, margin: Float)
}

public enum LiveAudioLanguageDetectionError: LocalizedError, Equatable, Sendable {
    case invalidAudio
    case resourcesMissing
    case modelUnavailable
    case inferenceFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAudio: "无法读取直播声音，请重试。"
        case .resourcesMissing: "请先下载字幕识别文件。"
        case .modelUnavailable: "字幕识别文件加载失败，请重试。"
        case .inferenceFailed: "没能识别主播语言，请重试。"
        }
    }
}

/// Receives copied, normalized PCM. Audio never leaves this device.
public actor LiveAudioLanguageDetector {
    private let resources: LiveLanguageDetectionResources

    public init() {
        resources = .shared
    }

    init(resources: LiveLanguageDetectionResources) {
        self.resources = resources
    }

    public func detect(samples: [Float], sampleRate: Int = 16_000) async throws -> LiveAudioLanguageDetection {
        try Task.checkCancellation()
        guard sampleRate == 16_000, (32_000...128_000).contains(samples.count),
              samples.allSatisfy(\.isFinite) else {
            throw LiveAudioLanguageDetectionError.invalidAudio
        }
        let files = try await resources.verifiedModelFiles()
        return try await LiveAudioLanguageRuntime.shared.detect(samples: samples, files: files)
    }
}

/// A single actor owns all C inference. No C context crosses an await or escapes
/// this actor; rooms serialize inference and release model memory after each call.
private actor LiveAudioLanguageRuntime {
    static let shared = LiveAudioLanguageRuntime()

    func detect(samples: [Float], files: LiveLanguageModelFiles) throws -> LiveAudioLanguageDetection {
        try Task.checkCancellation()
        var vadParameters = whisper_vad_default_context_params()
        vadParameters.use_gpu = false
        vadParameters.n_threads = 4
        guard let vad = whisper_vad_init_from_file_with_params(files.vad.path, vadParameters) else {
            throw LiveAudioLanguageDetectionError.modelUnavailable
        }
        defer { whisper_vad_free(vad) }
        let didProcess = samples.withUnsafeBufferPointer { buffer in
            whisper_vad_detect_speech(vad, buffer.baseAddress, Int32(buffer.count))
        }
        try Task.checkCancellation()
        guard didProcess, let probabilities = whisper_vad_probs(vad) else {
            throw LiveAudioLanguageDetectionError.inferenceFailed
        }
        let count = Int(whisper_vad_n_probs(vad))
        // Silero produces one probability per 512 samples at 16 kHz.
        // A sustained duration excludes isolated false positive music frames.
        let voicedFrames = (0..<count).filter { probabilities[$0] >= 0.5 }.count
        guard Double(voicedFrames) * 512 / 16_000 >= 0.5 else { return .noSpeech }

        var parameters = whisper_context_default_params()
        parameters.use_gpu = false
        guard let context = whisper_init_from_file_with_params(files.language.path, parameters) else {
            throw LiveAudioLanguageDetectionError.modelUnavailable
        }
        defer { whisper_free(context) }
        try Task.checkCancellation()
        let melResult = samples.withUnsafeBufferPointer { buffer in
            whisper_pcm_to_mel(context, buffer.baseAddress, Int32(buffer.count), 4)
        }
        guard melResult == 0 else { throw LiveAudioLanguageDetectionError.inferenceFailed }
        var languageProbabilities = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let languageID = languageProbabilities.withUnsafeMutableBufferPointer { buffer in
            whisper_lang_auto_detect(context, 0, 4, buffer.baseAddress)
        }
        // The fixed language-only C API has no abort callback. Cancellation
        // discards its result immediately after the bounded inference returns.
        try Task.checkCancellation()
        guard languageID >= 0, Int(languageID) < languageProbabilities.count,
              let code = whisper_lang_str(languageID) else {
            throw LiveAudioLanguageDetectionError.inferenceFailed
        }
        let probability = languageProbabilities[Int(languageID)]
        let runnerUp = languageProbabilities.enumerated()
            .filter { $0.offset != Int(languageID) }.map(\.element).max() ?? 0
        let margin = probability - runnerUp
        // Conservative initial thresholds from the offline PoC, not calibrated
        // accuracy guarantees. The session retries with a longer sample.
        guard probability.isFinite, margin.isFinite, probability >= 0.8, margin >= 0.2 else {
            return .uncertain
        }
        let languageCode = Locale.canonicalLanguageIdentifier(from: String(cString: code))
        return .detected(languageCode: languageCode, probability: probability, margin: margin)
    }
}
