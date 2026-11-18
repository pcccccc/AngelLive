import Alamofire
import Foundation
import Observation

/// What the room list should show. Loading indicators are separate: a cached list
/// stays `.content` while it refreshes, and a cancelled request never becomes
/// `.empty` or `.failure`.
public enum RoomListDisplayPhase: Equatable, Sendable {
    case skeleton
    case content
    case empty
    case failure

    public static func resolve(hasRooms: Bool, hasResolved: Bool, hasError: Bool) -> RoomListDisplayPhase {
        if hasRooms { return .content }
        if hasError { return .failure }
        if hasResolved { return .empty }
        return .skeleton
    }
}

/// One category owns its results, pagination and in-flight state. Selecting another
/// category never changes the destination of a response that is already running.
@MainActor
@Observable
public final class CategoryRoomListModel {
    public private(set) var rooms: [LiveModel] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var hasMore = true
    public private(set) var hasResolved = false
    public private(set) var error: (any Error)?

    public var phase: RoomListDisplayPhase {
        RoomListDisplayPhase.resolve(hasRooms: !rooms.isEmpty, hasResolved: hasResolved, hasError: error != nil)
    }

    @ObservationIgnored private var lastSuccessfulPage = 0
    @ObservationIgnored private let fetch: @MainActor (Int) async throws -> [LiveModel]

    public init(fetch: @escaping @MainActor (Int) async throws -> [LiveModel]) {
        self.fetch = fetch
    }

    /// `refresh` keeps the current rooms until the new page arrives. Pagination
    /// appends. Cancellation leaves the previous phase untouched.
    public func load(refresh: Bool = true) async {
        guard !isLoading, !Task.isCancelled, refresh || hasMore else { return }
        let requestedPage = refresh ? 1 : lastSuccessfulPage + 1
        isLoading = true
        isLoadingMore = !refresh && !rooms.isEmpty
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let fetched = try await fetch(requestedPage)
            try Task.checkCancellation()
            // Drop the error before replacing rooms so an empty success cannot
            // pass through the failure phase.
            error = nil
            hasResolved = true
            if refresh {
                rooms = fetched.removingDuplicates()
                lastSuccessfulPage = 1
            } else {
                rooms = rooms.appendingUnique(contentsOf: fetched)
                lastSuccessfulPage = requestedPage
            }
            hasMore = !fetched.isEmpty
        } catch {
            guard !isRequestCancellation(error) else { return }
            self.error = error
        }
    }

    public func loadMore() async {
        await load(refresh: false)
    }

    /// In-place identity updates from playback status. Does not change phase.
    public func replaceRooms(_ rooms: [LiveModel]) {
        self.rooms = rooms
    }
}

private func isRequestCancellation(_ error: Error) -> Bool {
    if Task.isCancelled || error is CancellationError { return true }
    if (error as? URLError)?.code == .cancelled { return true }
    if (error as? AFError)?.isExplicitlyCancelledError == true { return true }
    let bridged = error as NSError
    return bridged.domain == NSURLErrorDomain && bridged.code == NSURLErrorCancelled
}
