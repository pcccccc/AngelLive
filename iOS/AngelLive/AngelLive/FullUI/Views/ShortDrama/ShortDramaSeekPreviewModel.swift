#if canImport(KSPlayer)
internal import AVFoundation
import Observation
import UIKit
import AngelLiveCore
import AngelLiveDependencies
#if canImport(KSPlayer)
import KSPlayer
#endif

enum ShortDramaSeekPreviewState {
    case idle
    case loading
    case frame(UIImage, actualTime: Double)
    case unavailable
}

/// Owns an independent, bounded image generator. It never seeks or captures the active player.
@MainActor
@Observable
final class ShortDramaSeekPreviewModel {
    private(set) var state: ShortDramaSeekPreviewState = .idle

    @ObservationIgnored private var playbackID: UUID?
    @ObservationIgnored private var lifecycleID = UUID()
    @ObservationIgnored private var generator: AVAssetImageGenerator?
    @ObservationIgnored private var thumbnailOptions: KSOptions?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var thumbnailRequest: Task<Void, Never>?
    @ObservationIgnored private var latestTarget: Double?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var lastRequestTime: ContinuousClock.Instant?
    @ObservationIgnored private var isUnavailable = false
    @ObservationIgnored private var usesThumbnailCache = false
    @ObservationIgnored private var thumbnails: [ShortDramaPreviewFrame] = []
    @ObservationIgnored private var isDisplaying = false

    func update(playback: ShortDramaPlayback, targetTime: Double) {
        guard targetTime.isFinite, targetTime >= 0 else { return }
        if playbackID != playback.id {
            cancel()
            playbackID = playback.id
            // A loader supplied by the playback engine cannot be recreated by this provider.
            guard playback.quality.playbackHints?.requiresCustomSegmentLoader != true else {
                isUnavailable = true
                state = .unavailable
                return
            }
            let options = KSOptions()
            let configuration = KSPlayerSessionConfigurator.apply(
                quality: playback.quality,
                to: options,
                fallbackUserAgent: "libmpv",
                liveReconnectPolicy: .applicationManaged
            )
            // Bound preview-only network waits and avoid competing reconnect loops. These
            // options belong solely to the thumbnail worker, never to the active player.
            options.formatContextOptions["rw_timeout"] = 2_500_000
            options.formatContextOptions["reconnect"] = 0
            options.formatContextOptions["reconnect_on_network_error"] = 0
            thumbnailOptions = options
            // HLS without an image rendition can leave AVFoundation waiting throughout
            // a drag. Use the independent streaming thumbnail batch for that format.
            if playback.quality.decryption == nil && !configuration.plan.isHLS {
                let asset = AVURLAsset(url: playback.url, options: options.avOptions)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 320, height: 320)
                // A nearby decoded frame is suitable for scrubbing; the UI receives its real time.
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
                self.generator = generator
            }
        }
        isDisplaying = true
        guard !isUnavailable else {
            state = .unavailable
            return
        }
        guard latestTarget != targetTime else { return }
        latestTarget = targetTime
        revision += 1
        // Keep the last decoded frame visible while pursuing the next target. Its actualTime
        // tells the viewer where this approximate preview came from during continuous dragging.
        switch state {
        case .frame: break
        default: state = .loading
        }
        if usesThumbnailCache {
            showNearestThumbnail()
            return
        }
        guard request == nil else { return }
        let id = playback.id
        let lifecycle = lifecycleID
        if let generator {
            request = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                await self.generateLatest(using: generator, playbackID: id, lifecycle: lifecycle, url: playback.url)
            }
        } else {
            // HLS and explicit FFmpeg input decryption use the bounded batch directly.
            // Its headers/key belong to these independent preview-only options.
            startThumbnailBatch(playbackID: id, lifecycle: lifecycle, url: playback.url)
        }
    }

    /// Hide this gesture's preview while retaining the episode's single bounded batch/cache.
    func endScrubbing() {
        isDisplaying = false
        request?.cancel()
        request = nil
        generator?.cancelAllCGImageGeneration()
        latestTarget = nil
        revision += 1
        state = .idle
    }

    func cancel() {
        request?.cancel()
        request = nil
        thumbnailRequest?.cancel()
        thumbnailRequest = nil
        generator?.cancelAllCGImageGeneration()
        generator = nil
        thumbnailOptions = nil
        playbackID = nil
        lifecycleID = UUID()
        latestTarget = nil
        lastRequestTime = nil
        revision += 1
        isUnavailable = false
        usesThumbnailCache = false
        thumbnails = []
        isDisplaying = false
        state = .idle
    }

    private func generateLatest(
        using generator: AVAssetImageGenerator, playbackID id: UUID, lifecycle: UUID, url: URL
    ) async {
        while isCurrent(id: id, lifecycle: lifecycle), self.generator === generator {
            if let lastRequestTime {
                do {
                    try await Task.sleep(until: lastRequestTime.advanced(by: .milliseconds(100)), clock: .continuous)
                } catch { return }
            }
            guard isCurrent(id: id, lifecycle: lifecycle), self.generator === generator,
                  let target = latestTarget else { return }
            let expectedRevision = revision
            lastRequestTime = .now
            do {
                let result = try await generator.image(at: CMTime(seconds: target, preferredTimescale: 600))
                guard isCurrent(id: id, lifecycle: lifecycle), isDisplaying,
                      self.generator === generator else { return }
                // A completed frame remains useful even if the finger has already moved.
                // Publish its real timestamp, then immediately pursue the newest target.
                let actualTime = result.actualTime.seconds
                state = actualTime.isFinite
                    ? .frame(UIImage(cgImage: result.image), actualTime: actualTime)
                    : .unavailable
                if revision == expectedRevision {
                    request = nil
                    return
                }
            } catch {
                guard isCurrent(id: id, lifecycle: lifecycle), self.generator === generator else { return }
                // Ordinary HLS may have no I-frame rendition usable by AVFoundation. Fall
                // back once per lifecycle, rather than repeatedly reopening it as targets move.
                self.generator = nil
                generator.cancelAllCGImageGeneration()
                request = nil
                startThumbnailBatch(playbackID: id, lifecycle: lifecycle, url: url)
                return
            }
        }
    }

    private func isCurrent(id: UUID, lifecycle: UUID) -> Bool {
        !Task.isCancelled && playbackID == id && lifecycleID == lifecycle
    }

    private func startThumbnailBatch(playbackID id: UUID, lifecycle: UUID, url: URL) {
        guard !usesThumbnailCache, isCurrent(id: id, lifecycle: lifecycle) else { return }
        usesThumbnailCache = true
        thumbnailRequest = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.generateThumbnails(playbackID: id, lifecycle: lifecycle, url: url)
        }
    }

    private func generateThumbnails(playbackID id: UUID, lifecycle: UUID, url: URL) async {
        guard isCurrent(id: id, lifecycle: lifecycle), let options = thumbnailOptions else { return }
        #if canImport(KSPlayer)
        // The worker is shared across model instances, so a cancelled network read must
        // leave its single batch before any newly selected episode starts another one.
        let frames = await ShortDramaThumbnailWorker.shared.generate(url: url, options: options) { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == id, self.lifecycleID == lifecycle,
                      self.thumbnails.count < 24,
                      !self.thumbnails.contains(where: { $0.time == frame.time }) else { return }
                self.thumbnails.append(frame)
                self.showNearestThumbnail()
            }
        }
        guard isCurrent(id: id, lifecycle: lifecycle) else { return }
        // Commit the complete result as well: queued progress callbacks need not have reached
        // MainActor before the worker returns. Timestamp deduplication keeps late callbacks bounded.
        thumbnails = frames
        #endif
        guard isCurrent(id: id, lifecycle: lifecycle) else { return }
        thumbnailOptions = nil
        thumbnailRequest = nil
        if thumbnails.isEmpty {
            isUnavailable = true
            if isDisplaying { state = .unavailable }
        } else {
            showNearestThumbnail()
        }
    }

    private func showNearestThumbnail() {
        guard isDisplaying, let target = latestTarget,
              let frame = thumbnails.min(by: { abs($0.time - target) < abs($1.time - target) }) else { return }
        state = .frame(frame.image, actualTime: frame.time)
    }
}

private struct ShortDramaPreviewFrame: Sendable {
    let image: UIImage
    let time: Double
}

#if canImport(KSPlayer)
/// KSPlayer's batch API checks cancellation between frames. Opening/reading may finish only
/// after the preview timeout; actor serialization prevents overlapping batches during that wait.
private actor ShortDramaThumbnailWorker {
    static let shared = ShortDramaThumbnailWorker()

    func generate(
        url: URL, options: KSOptions, onFrame: @escaping @Sendable (ShortDramaPreviewFrame) -> Void
    ) -> [ShortDramaPreviewFrame] {
        guard !Task.isCancelled else { return [] }
        var frames: [ShortDramaPreviewFrame] = []
        do {
            try FFmpegUtility.streamThumbnail(for: url, options: options, thumbnailCount: 24) { image, time, _ in
                guard !Task.isCancelled, time.isFinite else { return }
                // streamThumbnail yields source-size CGImages; ThumbnailController's thumbWidth
                // is ignored in this dependency revision, so resize before retaining any image.
                autoreleasepool {
                    let scale = min(1, 320 / Double(max(image.width, image.height)))
                    let width = max(1, Int(Double(image.width) * scale))
                    let height = max(1, Int(Double(image.height) * scale))
                    guard let context = CGContext(
                        data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else { return }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    guard let scaled = context.makeImage() else { return }
                    let frame = ShortDramaPreviewFrame(image: UIImage(cgImage: scaled), time: time)
                    frames.append(frame)
                    onFrame(frame)
                }
            }
        } catch {
            // Retain any partial real frames; this batch is never retried for the same episode.
        }
        return frames
    }
}
#endif
#endif
