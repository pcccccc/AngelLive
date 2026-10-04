import Foundation
import Observation

/// One category owns its results, pagination and in-flight state. Selecting another
/// category never changes the destination of a response that is already running.
@MainActor
@Observable
public final class CategoryRoomListModel {
    public private(set) var rooms: [LiveModel] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = true
    public private(set) var error: (any Error)?

    @ObservationIgnored private var lastSuccessfulPage = 0
    @ObservationIgnored private let fetch: @MainActor (Int) async throws -> [LiveModel]

    public init(fetch: @escaping @MainActor (Int) async throws -> [LiveModel]) {
        self.fetch = fetch
    }

    public func load(refresh: Bool = true) async {
        guard !isLoading, !Task.isCancelled, refresh || hasMore else { return }
        if refresh {
            rooms.removeAll()
            lastSuccessfulPage = 0
            hasMore = true
        }
        error = nil
        let requestedPage = lastSuccessfulPage + 1
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await fetch(requestedPage)
            try Task.checkCancellation()
            rooms = rooms.appendingUnique(contentsOf: fetched)
            lastSuccessfulPage = requestedPage
            hasMore = !fetched.isEmpty
        } catch {
            guard !Task.isCancelled,
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return }
            self.error = error
        }
    }

    public func loadMore() async {
        await load(refresh: false)
    }
}
