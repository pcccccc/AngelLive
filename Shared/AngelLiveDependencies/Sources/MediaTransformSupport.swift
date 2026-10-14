import AngelLiveCore

/// Register only capabilities provided by the selected playback dependency.
public enum MediaTransformSupport {
    public static func registerHostCapability() {
        #if canImport(KSPlayer)
        LiveParseHostPlaybackCapabilities.enableMediaTransformV1()
        #endif
    }
}
