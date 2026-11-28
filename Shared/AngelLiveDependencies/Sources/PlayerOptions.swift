import Foundation
import CoreMedia
import AngelLiveCore
#if os(macOS) && canImport(KSPlayer)
import KSPlayer
import QuartzCore
#endif

public class PlayerOptions: KSOptions, @unchecked Sendable {
    public var syncSystemRate: Bool = false
    public var enablesMacOSHighFrameRateClockTolerance: Bool = false

    /// Set per resolved resource by the FullUI session configurator.
    @MainActor public internal(set) var mediaTransform: LiveMediaTransform?

    #if canImport(KSPlayer)
    /// Present only for FullUI resources with a resolved separate VOD audio URL.
    @MainActor public internal(set) var dualStreamAudio: DualStreamAudioConfiguration?
    /// A weakly captured, per-resource rendering clock. Never installed on audio options.
    @MainActor var dualStreamClock: (@MainActor () -> TimeInterval?)?
    #endif

    nonisolated required public init() {
        super.init()
    }

    #if os(macOS) && canImport(KSPlayer)
    open override func preferredFrame(fps: Float) -> Bool {
        guard enablesMacOSHighFrameRateClockTolerance else {
            return super.preferredFrame(fps: fps)
        }
        return fps.isFinite && (15...240).contains(fps)
    }

    open override func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: UInt) -> ClockProcessType {
        var presentationTime = nextVideoTime
        if enablesMacOSHighFrameRateClockTolerance, fps >= 50 {
            let desire = main.time.seconds + (CACurrentMediaTime() - main.lastMediaTime) * main.rate - videoDelay
            let lead = nextVideoTime - desire
            if lead > 1 / (2 * fps), lead <= 1.0 / 60 {
                // Present on this display tick and let KSOptions reset its consecutive-delay count.
                presentationTime = desire
            }
        }
        return super.videoClockSync(main: main, nextVideoTime: presentationTime, fps: fps, frameCount: frameCount)
    }
    #endif

    override public func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
        guard syncSystemRate else { return }
        super.updateVideo(refreshRate: refreshRate, isDovi: isDovi, formatDescription: formatDescription)
    }

}

#if canImport(KSPlayer)
extension PlayerOptions {
    /// Freeze resource options before background opening. Public per-session values
    /// are copied; transient FFmpeg state, time logs and rendering buffers start fresh.
    @MainActor func mediaTransformSessionSnapshot() -> PlayerOptions {
        sessionSnapshot(into: self is DualStreamVideoOptions ? DualStreamVideoOptions() : PlayerOptions())
    }

    @MainActor func dualStreamVideoSessionSnapshot() -> PlayerOptions {
        let copy = sessionSnapshot(into: DualStreamVideoOptions())
        // Controller operation settings on the layer's original options cannot reach
        // an already-open private snapshot. Separate VOD always uses confirmed seeks.
        copy.isAccurateSeek = true
        copy.isSeekedAutoPlay = false
        return copy
    }

    @MainActor func dualStreamAudioSessionSnapshot() -> PlayerOptions {
        sessionSnapshot(into: PlayerOptions())
    }

    @MainActor private func sessionSnapshot(into copy: PlayerOptions) -> PlayerOptions {
        copy.syncSystemRate = syncSystemRate
        copy.enablesMacOSHighFrameRateClockTolerance = enablesMacOSHighFrameRateClockTolerance
        copy.mediaTransform = mediaTransform
        copy.dualStreamAudio = dualStreamAudio
        copy.dualStreamClock = dualStreamClock
        copy.context = context
        copy.avOptions = avOptions
        copy.startPlayTime = startPlayTime
        copy.startPlayTimePercentage = startPlayTimePercentage
        copy.startPlayRate = startPlayRate
        copy.registerRemoteControll = registerRemoteControll
        copy.isAutoPlay = isAutoPlay
        copy.isSecondOpen = isSecondOpen
        copy.playerTypes = playerTypes
        copy.isLoopPlay = isLoopPlay
        copy.loopRange = loopRange
        copy.playbackTimeInterval = playbackTimeInterval
        copy.isAccurateSeek = isAccurateSeek
        copy.isSeekedAutoPlay = isSeekedAutoPlay
        copy.seekFlags = seekFlags
        copy.seekInterruptIO = seekInterruptIO
        copy.outputURL = outputURL
        copy.outputMediaType = outputMediaType
        copy.outputFormatContextOptions = outputFormatContextOptions
        copy.decoderOptions = decoderOptions
        copy.lowres = lowres
        copy.seekUsePacketCache = seekUsePacketCache
        copy.preferredForwardBufferDuration = preferredForwardBufferDuration
        copy.maxBufferDuration = maxBufferDuration
        copy.audioOutputType = audioOutputType
        copy.audioFilters = audioFilters
        copy.syncDecodeAudio = syncDecodeAudio
        copy.subtitleDisable = subtitleDisable
        copy.subtitleStride = subtitleStride
        copy.audioRecognizes = audioRecognizes
        copy.autoSelectEmbedSubtitle = autoSelectEmbedSubtitle
        copy.isSeekImageSubtitle = isSeekImageSubtitle
        copy.dynamicRange = dynamicRange
        copy.display = display
        copy.videoPipeline = videoPipeline
        copy.vtFramePipeline = vtFramePipeline
        copy.videoDelay = videoDelay
        copy.isRotateByFilter = isRotateByFilter
        copy.destinationDynamicRange = destinationDynamicRange
        copy.videoAdaptable = videoAdaptable
        copy.videoFilters = videoFilters
        copy.syncDecodeVideo = syncDecodeVideo
        copy.videoDecodeType = videoDecodeType
        copy.videoDisable = videoDisable
        copy.canStartPictureInPictureAutomaticallyFromInline = canStartPictureInPictureAutomaticallyFromInline
        copy.automaticWindowResize = automaticWindowResize
        copy.videoSoftDecodeThreadCount = videoSoftDecodeThreadCount
        copy.isDoubleRefreshRate = isDoubleRefreshRate
        copy.renderUseDispatchSourceTimer = renderUseDispatchSourceTimer
        copy.brightness = brightness
        copy.contrast = contrast
        copy.saturation = saturation
        copy.userAgent = userAgent
        // Preserve the exact resolved header/input dictionary after userAgent didSet.
        copy.formatContextOptions = formatContextOptions
        copy.isLive = false
        return copy
    }
}
#endif
