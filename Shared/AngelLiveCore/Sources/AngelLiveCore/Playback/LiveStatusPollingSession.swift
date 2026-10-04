import Foundation

/// Owns the asynchronous part of one room's live-status polling. The host owns
/// the timer cadence; a slow request cannot overlap another tick or end a new room.
@MainActor
public final class LiveStatusPollingSession {
    private let check: @MainActor () async throws -> LiveState
    private let onEnded: @MainActor () -> Void
    private let onFailure: @MainActor (any Error) -> Void
    private(set) var task: Task<Void, Never>?
    private var generation = UUID()
    private var stopped = false

    public init(
        check: @escaping @MainActor () async throws -> LiveState,
        onEnded: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void = { _ in }
    ) {
        self.check = check
        self.onEnded = onEnded
        self.onFailure = onFailure
    }

    isolated deinit { task?.cancel() }

    public func poll() {
        guard !stopped, task == nil else { return }
        let token = generation
        let check = check
        task = Task { @MainActor [weak self] in
            do {
                let state = try await check()
                guard let self, !Task.isCancelled,
                      !self.stopped, self.generation == token else { return }
                self.task = nil
                if state == .close || state == .unknow {
                    self.stop()
                    self.onEnded()
                }
            } catch {
                guard let self, !Task.isCancelled,
                      !self.stopped, self.generation == token else { return }
                self.task = nil
                self.onFailure(error)
            }
        }
    }

    public func stop() {
        stopped = true
        generation = UUID()
        task?.cancel()
        task = nil
    }
}
