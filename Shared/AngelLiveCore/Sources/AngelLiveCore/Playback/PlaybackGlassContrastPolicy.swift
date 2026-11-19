import Foundation

/// The playback identity whose material preference survives a controls reveal.
public struct PlaybackGlassContrastSource: Equatable, Sendable {
    public let roomID: String
    public let url: URL
    public let kernel: PlayerKernel
    public let episodeID: String?

    public init?(roomID: String, url: URL?, kernel: PlayerKernel, episodeID: String? = nil) {
        guard let url else { return nil }
        self.roomID = roomID
        self.url = url
        self.kernel = kernel
        self.episodeID = episodeID
    }
}

/// Retains the material and its dwell for the last selected playable source.
public struct PlaybackGlassContrastPolicy: Sendable {
    public enum Sample: Sendable {
        case brightCells(Int)
        case unreadable(isDecoderReady: Bool)
    }

    /// Evidence belongs to one sampling task. A reveal or scene activation starts a fresh window.
    public struct Samples: Sendable {
        fileprivate var consecutiveBrightSamples = 0
        fileprivate var darkSince: ContinuousClock.Instant?
        fileprivate var consecutiveUnreadableSamples = 0

        public init() {}
    }

    /// Five of the probe's 48 cells qualify as bright; two or fewer allow isolated highlights in a dark scene.
    private static let minimumBrightCells = 5
    private static let maximumDarkCells = 2
    /// Require repeated bright readings and sustained darkness to ride out brief cuts.
    private static let requiredBrightSamples = 2
    private static let requiredDarkDuration = Duration.milliseconds(2500)
    /// Enforce a dwell from source selection and from each subsequent material change.
    private static let minimumDwell = Duration.seconds(3)
    /// A ready decoder may miss a frame without needing the legibility fallback.
    private static let requiredUnreadableSamples = 3

    private var source: PlaybackGlassContrastSource?
    private var prefersRegularGlass = false
    private var lastChange: ContinuousClock.Instant?

    public init() {}

    public func usesRegularGlass(for source: PlaybackGlassContrastSource?) -> Bool {
        prefersRegularGlass && self.source == source
    }

    /// A temporarily unavailable URL leaves the last valid source and its dwell intact.
    @discardableResult
    public mutating func select(_ source: PlaybackGlassContrastSource?, at now: ContinuousClock.Instant) -> Bool {
        guard let source, self.source != source else { return false }
        self.source = source
        prefersRegularGlass = false
        lastChange = now
        return true
    }

    /// Returns the new material preference only when the selected source changes material.
    /// Keep a separate `Samples` value for each run of the probe.
    public mutating func record(
        _ sample: Sample,
        for source: PlaybackGlassContrastSource,
        at now: ContinuousClock.Instant,
        samples: inout Samples
    ) -> Bool? {
        guard self.source == source else { return nil }

        let wantsRegular: Bool
        switch sample {
        case .brightCells(let count):
            samples.consecutiveUnreadableSamples = 0
            samples.consecutiveBrightSamples = count >= Self.minimumBrightCells
                ? min(samples.consecutiveBrightSamples + 1, Self.requiredBrightSamples) : 0
            samples.darkSince = count <= Self.maximumDarkCells ? samples.darkSince ?? now : nil

            if samples.consecutiveBrightSamples == Self.requiredBrightSamples {
                wantsRegular = true
            } else if let darkSince = samples.darkSince, darkSince.duration(to: now) >= Self.requiredDarkDuration {
                wantsRegular = false
            } else {
                return nil
            }

        case .unreadable(let isDecoderReady):
            samples.consecutiveBrightSamples = 0
            samples.darkSince = nil
            samples.consecutiveUnreadableSamples = isDecoderReady
                ? min(samples.consecutiveUnreadableSamples + 1, Self.requiredUnreadableSamples) : 0
            guard samples.consecutiveUnreadableSamples == Self.requiredUnreadableSamples else { return nil }
            wantsRegular = true
        }

        guard wantsRegular != prefersRegularGlass, let lastChange,
              lastChange.duration(to: now) >= Self.minimumDwell else { return nil }
        prefersRegularGlass = wantsRegular
        self.lastChange = now
        return wantsRegular
    }
}
