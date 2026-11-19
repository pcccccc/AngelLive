#if canImport(KSPlayer)
import AngelLiveCore
import KSPlayer
import Observation

/// Publishes material changes while keeping probe state on the same actor as the player.
@MainActor
@Observable
public final class PlaybackGlassContrastState {
    private let sampler = PlaybackGlassContrastSampler()
    private var regularSource: PlaybackGlassContrastSource?

    public init() {}

    public func usesRegularGlass(for source: PlaybackGlassContrastSource?) -> Bool {
        guard let regularSource else { return false }
        return regularSource == source
    }

    public func select(_ source: PlaybackGlassContrastSource?) {
        if sampler.select(source) { regularSource = nil }
    }

    public func sample(
        for source: PlaybackGlassContrastSource,
        player: @MainActor () -> (any MediaPlayerProtocol)?
    ) async {
        guard !Task.isCancelled else { return }
        select(source)
        await sampler.run(for: source, player: player) { regular in
            regularSource = regular ? source : nil
        }
    }
}

@MainActor
private final class PlaybackGlassContrastSampler {
    private static let sampleInterval = Duration.milliseconds(400)
    private static let conversionInterval = Duration.milliseconds(1200)

    private var policy = PlaybackGlassContrastPolicy()

    func select(_ source: PlaybackGlassContrastSource?) -> Bool {
        policy.select(source, at: .now)
    }

    func run(
        for source: PlaybackGlassContrastSource,
        player: @MainActor () -> (any MediaPlayerProtocol)?,
        onChange: @MainActor (Bool) -> Void
    ) async {
        let probe = PlaybackLuminanceProbe()
        defer { probe.detach() }

        var samples = PlaybackGlassContrastPolicy.Samples()
        var nextConversion = ContinuousClock.now
        while !Task.isCancelled {
            let mediaPlayer = player()
            let frame = probe.frame(from: mediaPlayer)
            let now = ContinuousClock.now
            var brightCells = frame.flatMap { probe.brightCells(in: $0) }
            var attemptedSample = true
            if brightCells == nil, let frame {
                attemptedSample = now >= nextConversion
                if attemptedSample {
                    nextConversion = now + Self.conversionInterval
                    brightCells = probe.convertedBrightCells(in: frame)
                }
            }

            // Throttled conversions do not count as unreadable samples.
            if attemptedSample {
                let sample: PlaybackGlassContrastPolicy.Sample = if let brightCells {
                    .brightCells(brightCells)
                } else {
                    .unreadable(isDecoderReady: mediaPlayer?.isReadyToPlay == true)
                }
                if let regular = policy.record(sample, for: source, at: now, samples: &samples) {
                    onChange(regular)
                    #if DEBUG
                    if case .unreadable = sample {
                        Logger.debug("播放器玻璃使用深色回退，帧格式：\(probe.formatDescription(for: frame))", category: .ui)
                    }
                    #endif
                }
            }

            do { try await Task.sleep(for: Self.sampleInterval) } catch { return }
        }
    }
}
#endif
