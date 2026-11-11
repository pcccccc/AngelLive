import AngelLiveCore

/// Register only when the selected dependency provides separate-audio playback.
public enum DualStreamSupport {
    public static func registerHostCapability() {
        #if canImport(KSPlayer)
        LiveParseHostPlaybackCapabilities.enableDualStream()
        #endif
    }
}

#if canImport(KSPlayer)
import Foundation
import KSPlayer
import QuartzCore

/// Resolved alongside the video. Credentials and keys live only in this session.
public struct DualStreamAudioConfiguration: Sendable {
    public let url: URL
    public let userAgent: String
    public let headers: [String: String]
    public let decryption: LivePlaybackDecryption?
    /// Audio uses exactly the video's request (UA and headers). Only then may both files be
    /// opened through one combined manifest, which has a single request context.
    public let sharesVideoRequest: Bool

    public init(
        url: URL,
        userAgent: String,
        headers: [String: String],
        decryption: LivePlaybackDecryption?,
        sharesVideoRequest: Bool = false
    ) {
        self.url = url
        self.userAgent = userAgent
        self.headers = headers
        self.decryption = decryption
        self.sharesVideoRequest = sharesVideoRequest
    }

    @MainActor func options(from source: PlayerOptions) -> PlayerOptions {
        let options = source.dualStreamAudioSessionSnapshot()
        options.dualStreamAudio = nil
        options.dualStreamClock = nil
        options.mediaTransform = nil
        options.videoDisable = true
        options.subtitleDisable = true
        options.audioRecognizes = []
        options.registerRemoteControll = false
        options.isAutoPlay = false
        options.isSeekedAutoPlay = false
        options.isLoopPlay = false
        options.isAccurateSeek = true
        options.outputURL = nil
        options.startPlayTime = 0
        options.startPlayTimePercentage = 0
        options.userAgent = userAgent
        options.avOptions["AVURLAssetHTTPHeaderFieldsKey"] = nil
        options.formatContextOptions["headers"] = nil
        options.formatContextOptions["decryption_key"] = decryption?.key
        if !headers.isEmpty { options.appendHeader(headers) }
        options.playerTypes = [KSMEPlayer.self]
        return options
    }
}

/// Kept alive by the logical player; both the options closure and child reference
/// are weak. A loading or paused audio child can never hold video presentation.
@MainActor
final class DualStreamRenderClock {
    weak var follower: (any MediaPlayerProtocol)? { didSet { previousAudioTime = nil } }
    var isAligned = false { didSet { if !isAligned { previousAudioTime = nil } } }
    private var previousAudioTime: TimeInterval?

    var time: TimeInterval? {
        guard isAligned, let follower, follower.isReadyToPlay,
              follower.isPlaying, follower.loadState == .playable else {
            previousAudioTime = nil
            return nil
        }
        let time = follower.currentPlaybackTime
        guard time.isFinite else { previousAudioTime = nil; return nil }
        defer { previousAudioTime = time }
        // A playable flag alone cannot prove audible progress. Frozen or reversed
        // audio timestamps return video to its own clock instead of holding a frame.
        guard let previousAudioTime, time > previousAudioTime else { return nil }
        return time
    }
}

/// Used only for the private primary snapshot. It adds no nonisolated mutable
/// state: the clock closure is MainActor-owned, and inherited decoding options
/// retain PlayerOptions' existing single-resource ownership/transfer contract.
final class DualStreamVideoOptions: PlayerOptions, @unchecked Sendable {
    override func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: UInt) -> ClockProcessType {
        // The pinned dependency's sole caller is MEPlayerItem's @MainActor
        // getVideoOutputRender. Ordinary PlayerOptions never enter this override.
        let externalTime = MainActor.assumeIsolated { dualStreamClock?() }
        guard let externalTime, externalTime.isFinite else {
            return super.videoClockSync(main: main, nextVideoTime: nextVideoTime, fps: fps, frameCount: frameCount)
        }
        // Exact public-field equivalent of the dependency's internal KSClock.getTime().
        let localTime = main.time.seconds + (CACurrentMediaTime() - main.lastMediaTime) * main.rate
        return super.videoClockSync(
            main: main, nextVideoTime: nextVideoTime + localTime - externalTime,
            fps: fps, frameCount: frameCount
        )
    }
}

public enum DualStreamPlayerError: Error, LocalizedError, Sendable {
    case missingAudioOptions
    case unsupportedInput

    public var errorDescription: String? {
        switch self {
        case .missingAudioOptions: "Separate audio requires resource-specific PlayerOptions."
        case .unsupportedInput: "Separate audio requires URL input."
        }
    }
}
#endif
