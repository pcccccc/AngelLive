import Foundation

/// User-visible playback status. Recovery is tracked separately by `RecoveryPhase`.
public enum PlaybackStatus: Sendable, Equatable {
    case idle
    case loading
    case buffering
    case paused
    case playing
    case ended
    case failed(message: String?)

    public var isLoading: Bool {
        self == .loading || self == .buffering
    }

    public var isPlaying: Bool {
        self == .playing
    }
}

public enum PlaybackStatusEvent: Sendable, Equatable {
    case loadRequested
    case engineStateChanged(PlaybackEngineState, isPlaying: Bool)
    case failed(message: String?)
    case stopped
}

/// Reduces engine facts into one stable status shared by all platform control layers.
public struct PlaybackStatusMachine: Sendable {
    public private(set) var status: PlaybackStatus = .idle
    public private(set) var engineState: PlaybackEngineState = .initialized

    private var hasActiveSession = false

    public init() {}

    public mutating func send(_ event: PlaybackStatusEvent) {
        switch event {
        case .loadRequested:
            hasActiveSession = true
            engineState = .initialized
            status = .loading

        case .engineStateChanged(let state, let isPlaying):
            engineState = state
            reduce(state, isPlaying: isPlaying)

        case .failed(let message):
            status = .failed(message: message)

        case .stopped:
            hasActiveSession = false
            engineState = .initialized
            status = .idle
        }
    }

    private mutating func reduce(_ state: PlaybackEngineState, isPlaying: Bool) {
        switch state {
        case .initialized:
            status = hasActiveSession ? .loading : .idle

        case .preparing, .readyToPlay:
            hasActiveSession = true
            status = .loading

        case .buffering:
            hasActiveSession = true
            status = .buffering

        case .bufferFinished:
            hasActiveSession = true
            status = isPlaying ? .playing : .paused

        case .paused:
            hasActiveSession = true
            status = .paused

        case .ended:
            hasActiveSession = false
            status = .ended

        case .error:
            status = .failed(message: nil)
        }
    }
}
