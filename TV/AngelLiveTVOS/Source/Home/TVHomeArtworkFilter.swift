import AngelLiveCore
import AngelLiveDependencies
import Foundation
import Observation
import os

nonisolated struct TVHomeArtworkFilterRequest: Equatable {
    let urls: [URL]
    let processor: TVHomeArtworkProcessor?
    let isActive: Bool
    let isRefreshing: Bool
}

/// Owns only the TV presentation decision. The shared feed and its room rails stay intact.
@MainActor
@Observable
final class TVHomeArtworkFilter {
    nonisolated enum Verdict: Sendable, Equatable { case accepted, rejected, unavailable }
    typealias Loader = @Sendable (URL, TVHomeArtworkProcessor) async -> Verdict

    private(set) var verdicts: [URL: Verdict] = [:]
    private(set) var processorIdentifier: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var checkedAt: [URL: Date] = [:]
#if DEBUG
    private static let logger = Logger(subsystem: "AngelLive", category: "TVHomeArtworkFilter")
#endif

    nonisolated static func artworkURL(for entry: HomeBannerEntry) -> URL? {
        if let url = entry.banner.imageURL { return url }
        if case .room(let room) = entry.banner.target, !room.roomCover.isEmpty {
            return URL(string: room.roomCover)
        }
        return nil
    }

    func accepts(_ entry: HomeBannerEntry, processor: TVHomeArtworkProcessor) -> Bool {
        guard processorIdentifier == processor.identifier,
              let url = Self.artworkURL(for: entry) else { return false }
        return verdicts[url] == .accepted
    }

    func hasPending(_ urls: [URL], processor: TVHomeArtworkProcessor) -> Bool {
        guard processorIdentifier == processor.identifier else { return !urls.isEmpty }
        return urls.contains { verdicts[$0] == nil }
    }

    func evaluate(_ request: TVHomeArtworkFilterRequest, loader: @escaping Loader = TVHomeArtworkFilter.load) async {
        generation &+= 1
        let currentGeneration = generation
        guard let processor = request.processor else {
            verdicts = [:]
            checkedAt = [:]
            processorIdentifier = nil
            return
        }
        var seen = Set<URL>()
        let urls = request.urls.filter { seen.insert($0).inserted }
        let requestedURLs = Set(urls)
        if processorIdentifier != processor.identifier {
            verdicts = [:]
            checkedAt = [:]
            processorIdentifier = processor.identifier
        } else {
            // Bound decisions to this feed. Network failures are retried on the next
            // refresh/activation; they must not become permanent quality rejections.
            let now = Date()
            verdicts = verdicts.filter {
                requestedURLs.contains($0.key) && $0.value != .unavailable
                    && now.timeIntervalSince(checkedAt[$0.key] ?? .distantPast) < 300
            }
            checkedAt = checkedAt.filter { verdicts[$0.key] != nil }
        }
        guard request.isActive else { return }
        let pending = urls.filter { verdicts[$0] == nil }

        await withTaskGroup(of: (URL, Verdict).self) { group in
            var next = 0
            func enqueue() {
                guard next < pending.count, !Task.isCancelled else { return }
                let url = pending[next]
                next += 1
                group.addTask { (url, await loader(url, processor)) }
            }
            enqueue()
            enqueue()
            while let (url, verdict) = await group.next() {
                guard !Task.isCancelled, generation == currentGeneration else {
                    group.cancelAll()
                    return
                }
                verdicts[url] = verdict
                checkedAt[url] = Date()
                enqueue()
            }
        }
#if DEBUG
        if !Task.isCancelled, generation == currentGeneration {
            let accepted = verdicts.values.filter { $0 == .accepted }.count
            let rejected = verdicts.values.filter { $0 == .rejected }.count
            let unavailable = verdicts.values.filter { $0 == .unavailable }.count
            Self.logger.debug("result=completed candidates=\(urls.count) accepted=\(accepted) rejected=\(rejected) unavailable=\(unavailable)")
        }
#endif
    }

    nonisolated private static func load(_ url: URL, processor: TVHomeArtworkProcessor) async -> Verdict {
        do {
            // The same processor/cache key is used by the visible image and prefetch.
            // Kingfisher does decoding and quality analysis on its processing queue.
            _ = try await KingfisherManager.shared.retrieveImage(with: url, options: [
                .processor(processor), .cacheSerializer(TVHomeArtworkCacheSerializer.shared),
                .scaleFactor(1), .cacheOriginalImage, .onlyLoadFirstFrame, .downloadPriority(0.25)
            ])
            return .accepted
        } catch let error as KingfisherError {
            if case .processorError = error { return .rejected }
            return .unavailable
        } catch {
            return .unavailable
        }
    }
}
