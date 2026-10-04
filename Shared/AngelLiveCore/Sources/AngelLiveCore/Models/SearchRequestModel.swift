import Foundation
import Observation

public enum RoomSearchKind: Sendable, Equatable {
    case keyword
    case share
}

public struct RoomSearchRequest: Sendable, Equatable {
    public let input: String
    public let kind: RoomSearchKind
    public let page: Int

    public init(input: String, kind: RoomSearchKind, page: Int) {
        self.input = input
        self.kind = kind
        self.page = page
    }
}

@MainActor
@Observable
public final class SearchRequestModel {
    public private(set) var rooms: [LiveModel] = []
    public private(set) var isLoading = false
    public private(set) var error: Error?
    public private(set) var hasSearched = false
    public private(set) var hasMore = false
    public private(set) var authenticationRequiredPluginIDs: [String] = []

    private let fetchOutcome: @MainActor (RoomSearchRequest) async throws -> RoomSearchOutcome
    private let onAccepted: (@MainActor (RoomSearchRequest, [LiveModel]) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var currentRequest: RoomSearchRequest?
    private var currentPage = 0
    private var didLoadFirstPage = false
    var pendingTask: Task<Void, Never>? { task }

    public init(
        fetch: @escaping @MainActor (RoomSearchRequest) async throws -> [LiveModel],
        onAccepted: (@MainActor (RoomSearchRequest, [LiveModel]) -> Void)? = nil
    ) {
        self.fetchOutcome = { request in
            RoomSearchOutcome(rooms: try await fetch(request))
        }
        self.onAccepted = onAccepted
    }

    public init(
        fetchOutcome: @escaping @MainActor (RoomSearchRequest) async throws -> RoomSearchOutcome,
        onAccepted: (@MainActor (RoomSearchRequest, [LiveModel]) -> Void)? = nil
    ) {
        self.fetchOutcome = fetchOutcome
        self.onAccepted = onAccepted
    }

    isolated deinit { task?.cancel() }

    public func submit(input: String, kind: RoomSearchKind) {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            clear()
            return
        }

        invalidateTask()
        rooms = []
        error = nil
        hasSearched = true
        hasMore = false
        authenticationRequiredPluginIDs = []
        currentPage = 0
        didLoadFirstPage = false
        start(RoomSearchRequest(input: normalized, kind: kind, page: 1), appending: false)
    }

    public func loadMore() {
        guard !isLoading, hasMore, didLoadFirstPage,
              let currentRequest, currentRequest.kind == .keyword else { return }
        start(
            RoomSearchRequest(input: currentRequest.input, kind: .keyword, page: currentPage + 1),
            appending: true
        )
    }

    public func clear() {
        invalidateTask()
        rooms = []
        error = nil
        hasSearched = false
        hasMore = false
        authenticationRequiredPluginIDs = []
        currentRequest = nil
        currentPage = 0
        didLoadFirstPage = false
    }

    public func cancel() {
        invalidateTask()
        isLoading = false
    }

    public func dismissError() {
        error = nil
    }

    public func updateRoomLiveState(id: String, state: String) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        rooms[index].liveState = state
    }

    private func start(_ request: RoomSearchRequest, appending: Bool) {
        let requestGeneration = generation
        currentRequest = request
        isLoading = true
        error = nil
        let fetchOutcome = self.fetchOutcome
        task = Task { [weak self] in
            defer {
                if let self, self.generation == requestGeneration {
                    self.isLoading = false
                    self.task = nil
                }
            }
            do {
                let outcome = try await fetchOutcome(request)
                try Task.checkCancellation()
                guard let self, self.generation == requestGeneration else { return }
                let fetched = outcome.rooms
                self.authenticationRequiredPluginIDs = outcome.authenticationRequiredPluginIDs
                if fetched.isEmpty, !outcome.authenticationRequiredPluginIDs.isEmpty {
                    self.hasMore = false
                    if self.rooms.isEmpty {
                        self.error = PluginAuthenticationRequiredError(
                            pluginIDs: outcome.authenticationRequiredPluginIDs
                        )
                    }
                    return
                }
                if appending {
                    self.rooms = self.rooms.appendingUnique(contentsOf: fetched)
                } else {
                    self.rooms = fetched.removingDuplicates()
                }
                self.currentPage = request.page
                self.didLoadFirstPage = self.didLoadFirstPage || request.page == 1
                self.hasMore = request.kind == .keyword && !fetched.isEmpty
                self.onAccepted?(request, fetched)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.generation == requestGeneration else { return }
                let nsError = error as NSError
                guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
                self.error = error
            }
        }
    }

    private func invalidateTask() {
        generation = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }
}
