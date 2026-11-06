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

    public static func enableDualStream() { registry.enableDualStream() }

    public static var dualStream: Bool { registry.dualStream }
}

/// A synchronous JS bridge reads while host startup may register on another thread.
/// All mutable state is inside this lock; registration only enables capabilities. Keeping
/// the registry independently constructible also isolates tests from global startup.
struct LiveParseHostPlaybackCapabilityRegistry: Sendable {
    private struct State {
        var mediaTransformVersion = 0
        var dualStream = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func enableMediaTransformV1() {
        state.withLock { $0.mediaTransformVersion = 1 }
    }

    var mediaTransformVersion: Int {
        state.withLock { $0.mediaTransformVersion }
    }

    func enableDualStream() { state.withLock { $0.dualStream = true } }

    var dualStream: Bool { state.withLock { $0.dualStream } }
}
