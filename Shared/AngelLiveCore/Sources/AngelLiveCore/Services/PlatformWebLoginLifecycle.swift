import Foundation

/// Tracks which presentation may consume asynchronous web-login callbacks.
/// The host owns this value on its UI actor; no credentials are stored here.
public struct PlatformWebLoginLifecycle: Sendable {
    public private(set) var isInitialStatusLoaded = false
    public private(set) var generation = UUID()
    public private(set) var attemptID: UUID?

    public init() {}

    @discardableResult
    public mutating func beginLoading() -> UUID {
        stopLoginAttempt()
        isInitialStatusLoaded = false
        return generation
    }

    public mutating func completeInitialStatus(
        generation: UUID,
        isAuthenticated: Bool,
        startsWithLogin: Bool
    ) {
        guard isCurrentGeneration(generation) else { return }
        isInitialStatusLoaded = true
        attemptID = startsWithLogin || !isAuthenticated ? generation : nil
    }

    @discardableResult
    public mutating func beginLoginAttempt() -> UUID {
        generation = UUID()
        isInitialStatusLoaded = true
        attemptID = generation
        return generation
    }

    public mutating func stopLoginAttempt() {
        generation = UUID()
        attemptID = nil
    }

    public func isCurrentGeneration(_ generation: UUID) -> Bool {
        self.generation == generation
    }

    public func acceptsCallback(for attemptID: UUID) -> Bool {
        self.attemptID == attemptID && isCurrentGeneration(attemptID)
    }
}
