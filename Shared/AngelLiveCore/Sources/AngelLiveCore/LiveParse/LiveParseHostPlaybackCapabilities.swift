import os.lock

/// Registered by a host only after its matching playback adapter is available.
/// Core alone cannot promise the capability because a host may use another engine.
public enum LiveParseHostPlaybackCapabilities {
    private static let registry = LiveParseHostPlaybackCapabilityRegistry()

    public static func enableMediaTransformV1() {
        registry.enableMediaTransformV1()
    }

    public static var mediaTransformVersion: Int {
        registry.mediaTransformVersion
    }
}

/// A synchronous JS bridge reads while host startup may register on another thread.
/// All mutable state is inside this lock; version only moves from 0 to 1. Keeping
/// the registry independently constructible also isolates tests from global startup.
struct LiveParseHostPlaybackCapabilityRegistry: Sendable {
    private let version = OSAllocatedUnfairLock<Int>(initialState: 0)

    func enableMediaTransformV1() {
        version.withLock { $0 = 1 }
    }

    var mediaTransformVersion: Int {
        version.withLock { $0 }
    }
}
