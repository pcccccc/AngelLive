import Foundation
import Observation

public enum PlaybackStartupFailureCode: String, Codable, Sendable {
    case engineError, timeout, sourceUnavailable
}

/// Intentionally contains no arbitrary strings, URLs, room identifiers or credentials.
public enum PlaybackEvent: Codable, Sendable, Equatable {
    case sessionStarted
    case sourceAssigned(line: Int, quality: Int)
    case engineStateChanged(state: PlaybackEngineState, isPlaying: Bool)
    case sample(bytesRead: Int64, playhead: TimeInterval, buffered: TimeInterval)
    case recovery(action: RecoveryActionKind, attempt: Int, limit: Int)
    case startupCompleted(milliseconds: Double)
    case startupFailed(code: PlaybackStartupFailureCode)
    case preferenceApplied(originalIndex: Int, chosenIndex: Int)
    case recoveryExhausted
    case sessionEnded
}

public struct PlaybackEventEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sessionID: UUID
    public let date: Date
    public let elapsed: TimeInterval
    public let event: PlaybackEvent

    public init(id: UUID = UUID(), sessionID: UUID, date: Date = .now,
                elapsed: TimeInterval, event: PlaybackEvent) {
        self.id = id
        self.sessionID = sessionID
        self.date = date
        self.elapsed = elapsed
        self.event = event
    }
}

@MainActor @Observable
public final class PlaybackEventLog {
    public static let shared = PlaybackEventLog()
    public private(set) var entries: [PlaybackEventEntry] = []
    @ObservationIgnored private let capacity: Int

    public init(capacity: Int = 500) { self.capacity = max(1, capacity) }

    public func record(_ event: PlaybackEvent, sessionID: UUID,
                       elapsed: TimeInterval, date: Date = .now) {
        guard elapsed.isFinite else { return }
        // Engine samples are external numeric input; reject non-JSON values.
        switch event {
        case let .sample(_, playhead, buffered):
            guard playhead.isFinite, buffered.isFinite else { return }
        case let .startupCompleted(milliseconds):
            guard milliseconds.isFinite else { return }
        default: break
        }
        entries.append(.init(sessionID: sessionID, date: date,
                             elapsed: max(0, elapsed), event: event))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public func clear() { entries.removeAll() }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries)
    }
}
