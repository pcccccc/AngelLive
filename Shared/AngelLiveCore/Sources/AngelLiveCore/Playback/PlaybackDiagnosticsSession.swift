import Foundation
import Observation

public struct CDNStartupOutcome: Sendable, Equatable {
    public enum Result: Sendable, Equatable {
        case success(milliseconds: Double)
        case failure
    }
    public let pluginID: String
    public let lineID: String
    public let result: Result
}

/// Presentation and measurement for one room VM. Does not decide or retry playback.
@MainActor @Observable
public final class PlaybackDiagnosticsSession {
    public let sessionID: UUID
    public private(set) var startupStage: PlaybackStartupStage = .fetchingSource
    public private(set) var recoveryNotice: PlaybackRecoveryNotice?
    public private(set) var hasStartedPlayback = false
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private let isLoggingEnabled: () -> Bool
    @ObservationIgnored private let log: PlaybackEventLog
    @ObservationIgnored private let finishStartup: (CDNStartupOutcome) -> Void
    @ObservationIgnored private var startedAt: TimeInterval?
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var attempt: Attempt?
    @ObservationIgnored private var lastEngineState: PlaybackEngineState?
    @ObservationIgnored private var lastIsPlaying: Bool?
    @ObservationIgnored private var presentationPlayhead: TimeInterval?
    @ObservationIgnored private var hasAssignedSource = false

    private struct Attempt {
        let pluginID: String
        let lineID: String
        let startedAt: TimeInterval
        var baselinePlayhead: TimeInterval?
    }

    public init(sessionID: UUID = UUID(),
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                log: PlaybackEventLog = .shared,
                isLoggingEnabled: @escaping () -> Bool = {
                    UserDefaults.shared.bool(forKey: GeneralSettingModel.globalDeveloperMode)
                },
                finishStartup: ((CDNStartupOutcome) -> Void)? = nil) {
        self.sessionID = sessionID
        self.clock = clock
        self.log = log
        self.isLoggingEnabled = isLoggingEnabled
        self.finishStartup = finishStartup ?? { outcome in
            Task { await Self.persistOutcome(outcome) }
        }
    }

    private static func persistOutcome(_ outcome: CDNStartupOutcome) async {
        switch outcome.result {
        case .success(let milliseconds):
            await CDNPreferenceStore.shared.recordSuccess(
                lineID: outcome.lineID, pluginID: outcome.pluginID,
                startupMilliseconds: milliseconds)
        case .failure:
            await CDNPreferenceStore.shared.recordFailure(
                lineID: outcome.lineID, pluginID: outcome.pluginID)
        }
    }

    public func fetchingSource() {
        beginIfNeeded()
        guard !ended else { return }
        startupStage = .fetchingSource
        attempt = nil
    }

    public func sourceAssigned(pluginID: String, lineID: String, line: Int, quality: Int) {
        beginIfNeeded()
        guard !ended else { return }
        startupStage = .connecting
        hasAssignedSource = true
        presentationPlayhead = nil
        attempt = Attempt(pluginID: pluginID, lineID: lineID, startedAt: clock())
        lastEngineState = nil
        lastIsPlaying = nil
        record(.sourceAssigned(line: line, quality: quality))
    }

    public func preferenceApplied(originalIndex: Int, chosenIndex: Int) {
        beginIfNeeded()
        record(.preferenceApplied(originalIndex: originalIndex, chosenIndex: chosenIndex))
    }

    public func engineStateChanged(_ state: PlaybackEngineState, isPlaying: Bool) {
        guard !ended else { return }
        if state != lastEngineState || isPlaying != lastIsPlaying {
            record(.engineStateChanged(state: state, isPlaying: isPlaying))
            lastEngineState = state
            lastIsPlaying = isPlaying
        }
        if state == .paused { interruptStartup() }
        if state == .error { failStartup(.engineError) }
    }

    public func observe(_ observation: PlaybackRecoveryObservation) {
        guard !ended else { return }
        switch observation {
        case .sample(let sample): sampleReceived(sample)
        case let .recovering(action, attempt, limit, failure):
            if let failure { failStartup(failure) }
            recoveryNotice = .init(action: action, attempt: attempt, limit: limit)
            record(.recovery(action: action, attempt: attempt, limit: limit))
        case .exhausted(let failure):
            if let failure { failStartup(failure) }
            record(.recoveryExhausted)
        }
    }

    public func sourceUnavailable() {
        beginIfNeeded()
        record(.startupFailed(code: .sourceUnavailable))
        attempt = nil
    }

    /// Pause/background/manual interruption is not a failed startup observation.
    public func interruptStartup() {
        attempt = nil
        presentationPlayhead = nil
    }

    public func end() {
        guard !ended else { return }
        record(.sessionEnded)
        ended = true
        attempt = nil
        recoveryNotice = nil
    }

    private func sampleReceived(_ sample: PlaybackSample) {
        guard sample.playhead.isFinite, sample.buffered.isFinite else { return }
        if hasAssignedSource, let previous = presentationPlayhead, sample.isPlaying,
           sample.playhead > previous + 0.05 {
            hasStartedPlayback = true
        }
        presentationPlayhead = sample.playhead
        record(.sample(bytesRead: max(0, sample.bytesRead), playhead: sample.playhead,
                       buffered: max(0, sample.buffered)))
        guard var current = attempt else { return }
        if sample.bytesRead > 0 || sample.buffered > 0 { startupStage = .buffering }
        if let baseline = current.baselinePlayhead, sample.isPlaying,
           sample.playhead > baseline + 0.05 {
            attempt = nil
            let milliseconds = max(0, clock() - current.startedAt) * 1_000
            record(.startupCompleted(milliseconds: milliseconds))
            finishStartup(.init(pluginID: current.pluginID, lineID: current.lineID,
                                result: .success(milliseconds: milliseconds)))
        } else {
            current.baselinePlayhead = sample.playhead
            attempt = current
        }
    }

    private func failStartup(_ code: PlaybackStartupFailureCode) {
        guard let current = attempt else { return }
        attempt = nil
        record(.startupFailed(code: code))
        finishStartup(.init(pluginID: current.pluginID, lineID: current.lineID, result: .failure))
    }

    private func beginIfNeeded() {
        guard startedAt == nil, !ended else { return }
        startedAt = clock()
        record(.sessionStarted)
    }

    private func record(_ event: PlaybackEvent) {
        guard !ended, let startedAt, isLoggingEnabled() else { return }
        log.record(event, sessionID: sessionID, elapsed: max(0, clock() - startedAt))
    }
}
