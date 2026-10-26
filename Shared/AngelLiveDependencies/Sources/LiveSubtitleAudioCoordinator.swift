import AVFoundation
import Foundation
import Speech

#if canImport(KSPlayer)
/// The PCM consumer and asynchronous detector meet here. Only this actor owns
/// the rolling window and the transition from pre-roll to live transcription.
@available(iOS 26, macOS 26, tvOS 26, *)
actor LiveSubtitleAudioCoordinator {
    enum Event: Equatable, Sendable {
        case waitingForSpeech
        case detecting
        case detected(String)
        case uncertain
        case failed(String)
    }

    typealias Detector = @Sendable ([Float]) async throws -> LiveAudioLanguageDetection

    nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation
    private let detector: Detector
    private var window = LiveSubtitlePCMWindow(capacity: 8 * 16_000)
    private var detectionTask: Task<Void, Never>?
    private var nextDetectionSample = 4 * 16_000
    private var detectionWindowSamples = 4 * 16_000
    private var totalSamples = 0
    private var isFinished = false
    private var languageIsKnown: Bool
    private var speechConverter: LiveAudioConverter?
    private var speechWaiter: CheckedContinuation<AnalyzerInput?, Error>?

    init(languageIsKnown: Bool = false, detector: @escaping Detector) {
        self.languageIsKnown = languageIsKnown
        self.detector = detector
        let pair = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func append(_ samples: [Float]) throws {
        guard !isFinished, !samples.isEmpty else { return }
        window.append(samples)
        if speechConverter != nil {
            if let waiter = speechWaiter {
                do {
                    if let input = try takeSpeechInput() {
                        speechWaiter = nil
                        waiter.resume(returning: input)
                    }
                } catch {
                    speechWaiter = nil
                    waiter.resume(throwing: error)
                    throw error
                }
            }
            return
        }
        totalSamples += samples.count
        startDetectionIfReady()
    }

    /// Runs without suspension. The same bounded window becomes Speech's input,
    /// so there is no second queue or overlapping pre-roll/live handoff.
    func installSpeechInput(format: AVAudioFormat) throws {
        guard !isFinished else {
            throw CancellationError()
        }
        detectionTask?.cancel()
        detectionTask = nil
        languageIsKnown = true
        speechConverter = LiveAudioConverter(analyzerFormat: format)
    }

    func nextSpeechInput() async throws -> AnalyzerInput? {
        try Task.checkCancellation()
        guard !isFinished else { return nil }
        if window.count > 0, let input = try takeSpeechInput() {
            return input
        }
        // SpeechAnalyzer is the sole iterator; concurrent readers would split
        // the sequence and violate the audio ownership contract.
        precondition(speechWaiter == nil)
        return try await withCheckedThrowingContinuation { speechWaiter = $0 }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        detectionTask?.cancel()
        detectionTask = nil
        speechWaiter?.resume(returning: nil)
        speechWaiter = nil
        speechConverter = nil
        window.removeAll()
        eventContinuation.finish()
    }

    private func takeSpeechInput() throws -> AnalyzerInput? {
        guard let chunk = LiveAudioChunk(monoSamples: window.samples()) else { return nil }
        let buffer = try speechConverter?.convert(chunk)
        window.removeAll()
        return buffer.map { AnalyzerInput(buffer: $0) }
    }

    private func startDetectionIfReady() {
        guard !languageIsKnown, !isFinished, detectionTask == nil,
              totalSamples >= nextDetectionSample else { return }
        let snapshot = window.samples(last: detectionWindowSamples)
        let snapshotEnd = totalSamples
        let windowSize = detectionWindowSamples
        eventContinuation.yield(.detecting)
        let detector = detector
        detectionTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let result = try await detector(snapshot)
                try Task.checkCancellation()
                await self?.complete(result, windowSize: windowSize, snapshotEnd: snapshotEnd)
            } catch is CancellationError {
                return
            } catch {
                await self?.fail()
            }
        }
    }

    private func complete(
        _ result: LiveAudioLanguageDetection,
        windowSize: Int,
        snapshotEnd: Int
    ) {
        guard !isFinished, !languageIsKnown else { return }
        detectionTask = nil
        switch result {
        case .noSpeech:
            // Silence never graduates into an uncertain-language prompt. Wait
            // for a fresh four-second window rather than retrying the same PCM.
            detectionWindowSamples = 4 * 16_000
            nextDetectionSample = snapshotEnd + detectionWindowSamples
            eventContinuation.yield(.waitingForSpeech)
            startDetectionIfReady()
        case .uncertain where windowSize < 8 * 16_000:
            detectionWindowSamples = 8 * 16_000
            nextDetectionSample = snapshotEnd + 4 * 16_000
            startDetectionIfReady()
        case .uncertain:
            languageIsKnown = true
            eventContinuation.yield(.uncertain)
        case let .detected(languageCode, _, _):
            languageIsKnown = true
            eventContinuation.yield(.detected(languageCode))
        }
    }

    private func fail() {
        guard !isFinished, !languageIsKnown else { return }
        languageIsKnown = true
        detectionTask = nil
        eventContinuation.yield(.failed("没能识别主播语言，请重试。"))
    }
}

/// Duration is expressed in samples rather than decoder packet count. Memory
/// stays bounded even while detection or Speech resource preparation suspends.
struct LiveSubtitlePCMWindow {
    let capacity: Int
    private var storage: [Float] = []
    private var start = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { storage.count }

    mutating func append(_ samples: [Float]) {
        if samples.count >= capacity {
            storage = Array(samples.suffix(capacity))
            start = 0
            return
        }
        for sample in samples {
            if storage.count < capacity {
                storage.append(sample)
            } else {
                storage[start] = sample
                start = (start + 1) % capacity
            }
        }
    }

    func samples(last requestedCount: Int? = nil) -> [Float] {
        let sampleCount = min(requestedCount ?? count, count)
        guard sampleCount > 0 else { return [] }
        let first = (start + count - sampleCount) % count
        let firstCount = min(sampleCount, count - first)
        var result = Array(storage[first..<(first + firstCount)])
        if firstCount < sampleCount {
            result.append(contentsOf: storage[0..<(sampleCount - firstCount)])
        }
        return result
    }

    mutating func removeAll() {
        storage = []
        start = 0
    }
}
#endif
