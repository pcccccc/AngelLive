import Foundation
import CoreMedia
import AngelLiveCore

public class PlayerOptions: KSOptions, @unchecked Sendable {
    public var syncSystemRate: Bool = false

    /// Set per resolved resource by the FullUI session configurator.
    @MainActor public internal(set) var mediaTransform: LiveMediaTransform?

    nonisolated required public init() {
        super.init()
    }

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
        let copy = PlayerOptions()
        copy.syncSystemRate = syncSystemRate
        copy.mediaTransform = mediaTransform
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
