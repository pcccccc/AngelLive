import CryptoKit
import Foundation
import Observation

public struct VodProgressKey: Codable, Hashable, Sendable {
    public let pluginID: String
    public let workID: String

    public init(pluginID: String, workID: String) {
        self.pluginID = pluginID
        self.workID = workID
    }

    var isValid: Bool {
        VodCatalog.hasIdentity(pluginID) && VodCatalog.hasIdentity(workID)
    }

    var filename: String {
        let identity = "\(pluginID.utf8.count):\(pluginID)\(workID.utf8.count):\(workID)"
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

public struct VodEpisodeProgress: Codable, Equatable, Sendable {
    public let position: Double
    public let duration: Double
    public let completed: Bool
    public let updatedAt: Date

    public init(position: Double, duration: Double, completed: Bool, updatedAt: Date) {
        self.position = position
        self.duration = duration
        self.completed = completed
        self.updatedAt = updatedAt
    }

    fileprivate var isValid: Bool {
        position.isFinite && position >= 0 && duration.isFinite && duration > 0
            && position <= duration && updatedAt.timeIntervalSinceReferenceDate.isFinite
    }
}

/// Display metadata for the local viewing history.
public struct VodHistoryMetadata: Codable, Equatable, Sendable {
    public let title: String
    public let posterURL: String?
    public let kind: VodWorkKind
    public let episodeID: String?
    public let episodeTitle: String?
    public let episodeNumber: Int?
    public let lastWatchedAt: Date

    public init(title: String, posterURL: String? = nil, kind: VodWorkKind, episodeID: String? = nil,
                episodeTitle: String? = nil, episodeNumber: Int? = nil, lastWatchedAt: Date = .now) {
        self.title = title
        self.posterURL = posterURL
        self.kind = kind
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.episodeNumber = episodeNumber
        self.lastWatchedAt = lastWatchedAt
    }

    fileprivate var isValid: Bool { lastWatchedAt.timeIntervalSinceReferenceDate.isFinite }
}

public struct VodHistoryEntry: Identifiable, Equatable, Sendable {
    public var id: VodProgressKey { key }
    public let key: VodProgressKey
    public let lastEpisodeID: String
    public let metadata: VodHistoryMetadata
    public let progress: VodEpisodeProgress
    public var title: String { metadata.title }
    public var coverURL: String? { metadata.posterURL }
    public var episodeTitle: String? { metadata.episodeID == lastEpisodeID ? metadata.episodeTitle : nil }
    public var episodeNumber: Int? { metadata.episodeID == lastEpisodeID ? metadata.episodeNumber : nil }
    public var position: Double { progress.position }
    public var duration: Double { progress.duration }
    public var completed: Bool { progress.completed }
    public var updatedAt: Date { max(metadata.lastWatchedAt, progress.updatedAt) }
}

public struct VodProgressSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let key: VodProgressKey
    public fileprivate(set) var lastEpisodeID: String?
    public fileprivate(set) var episodes: [String: VodEpisodeProgress]
    public fileprivate(set) var historyMetadata: VodHistoryMetadata?
    public fileprivate(set) var historyHidden: Bool?

    public init(key: VodProgressKey) {
        version = 1
        self.key = key
        episodes = [:]
    }

    fileprivate var isValid: Bool {
        version == 1 && key.isValid && episodes.allSatisfy { !$0.key.isEmpty && $0.value.isValid }
            && (lastEpisodeID.map { episodes[$0] != nil } ?? true)
            && (historyMetadata?.isValid ?? true)
    }
}

@MainActor
@Observable
public final class VodProgressStore {
    public static let shared = VodProgressStore()
    public enum StorageError: Error { case invalidSnapshot }

    public private(set) var historyEntries: [VodHistoryEntry] = []
    public private(set) var historyWarning: String?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let write: (Data, URL) throws -> Void
    @ObservationIgnored private var entries: [VodProgressKey: Entry] = [:]
    @ObservationIgnored private var readFailures: [VodProgressKey: any Error] = [:]

    private struct Entry {
        var snapshot: VodProgressSnapshot
        var dirty = false
        var lastFlushAttempt: Date?
    }

    public convenience init(directory: URL? = nil) {
        #if os(tvOS)
        let base = URL.cachesDirectory
        #else
        let base = URL.applicationSupportDirectory
        #endif
        self.init(directory: directory ?? base.appendingPathComponent("VodProgress", isDirectory: true),
                  write: { try $0.write(to: $1, options: .atomic) })
    }

    init(directory: URL, write: @escaping (Data, URL) throws -> Void) {
        self.directory = directory
        self.write = write
    }

    public func load(for key: VodProgressKey) throws -> VodProgressSnapshot {
        guard key.isValid else { throw StorageError.invalidSnapshot }
        if let error = readFailures[key] { throw error }
        if let entry = entries[key] { return entry.snapshot }
        let snapshot: VodProgressSnapshot
        do {
            let decoded = try read(directory.appendingPathComponent(key.filename))
            guard decoded.key == key else { throw StorageError.invalidSnapshot }
            snapshot = decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            snapshot = VodProgressSnapshot(key: key)
        } catch {
            readFailures[key] = error
            throw error
        }
        entries[key] = Entry(snapshot: snapshot)
        refreshHistory()
        return snapshot
    }

    public func updateEpisode(_ progress: VodEpisodeProgress, episodeID: String, for key: VodProgressKey,
                              historyMetadata: VodHistoryMetadata? = nil, playbackStarted: Bool = false) throws {
        guard progress.isValid, VodCatalog.hasIdentity(episodeID), historyMetadata?.isValid ?? true else {
            throw StorageError.invalidSnapshot
        }
        _ = try load(for: key)
        entries[key]?.snapshot.episodes[episodeID] = progress
        entries[key]?.snapshot.lastEpisodeID = episodeID
        if let historyMetadata { entries[key]?.snapshot.historyMetadata = historyMetadata }
        if playbackStarted { entries[key]?.snapshot.historyHidden = nil }
        entries[key]?.dirty = true
        refreshHistory()
    }

    public func loadHistory() {
        var failed = false
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
            let knownFiles = Set(entries.keys.map(\.filename))
            for file in files where file.pathExtension == "json" && !knownFiles.contains(file.lastPathComponent) {
                do {
                    let snapshot = try read(file)
                    entries[snapshot.key] = Entry(snapshot: snapshot)
                    readFailures.removeValue(forKey: snapshot.key)
                } catch {
                    failed = true
                }
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // No local history yet.
        } catch {
            failed = true
        }
        historyWarning = failed ? "部分影视历史暂时无法读取" : nil
        refreshHistory()
    }

    public func removeHistory(for key: VodProgressKey) throws {
        _ = try load(for: key)
        guard var entry = entries[key], entry.snapshot.historyHidden != true,
              entry.snapshot.historyMetadata != nil else { return }
        entry.snapshot.historyHidden = true
        try persist(entry.snapshot)
        entry.dirty = false
        entry.lastFlushAttempt = .now
        entries[key] = entry
        refreshHistory()
    }

    public func flush(for key: VodProgressKey) throws {
        try flush(for: key, now: .now)
    }

    public func flushIfNeeded(for key: VodProgressKey, now: Date = .now) throws {
        guard entries[key]?.lastFlushAttempt.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        try flush(for: key, now: now)
    }

    private func flush(for key: VodProgressKey, now: Date) throws {
        _ = try load(for: key)
        guard let entry = entries[key], entry.dirty else { return }
        entries[key]?.lastFlushAttempt = now
        try persist(entry.snapshot)
        entries[key]?.dirty = false
    }

    private func persist(_ snapshot: VodProgressSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(data, directory.appendingPathComponent(snapshot.key.filename))
    }

    private func read(_ file: URL) throws -> VodProgressSnapshot {
        let snapshot = try JSONDecoder().decode(VodProgressSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.isValid, file.lastPathComponent == snapshot.key.filename else {
            throw StorageError.invalidSnapshot
        }
        return snapshot
    }

    private func refreshHistory() {
        historyEntries = entries.values.compactMap { entry -> VodHistoryEntry? in
            let snapshot = entry.snapshot
            guard snapshot.historyHidden != true, let metadata = snapshot.historyMetadata,
                  let id = snapshot.lastEpisodeID, let progress = snapshot.episodes[id] else { return nil }
            return VodHistoryEntry(key: snapshot.key, lastEpisodeID: id, metadata: metadata, progress: progress)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}

public struct VodProgressSession: Sendable {
    public private(set) var snapshot: VodProgressSnapshot
    private var playbackID: UUID?
    private var episodeID: String?
    private var readyDuration: Double?
    private var lastSample: VodEpisodeProgress?

    public init(snapshot: VodProgressSnapshot) {
        self.snapshot = snapshot
    }

    public func preferredEpisode(in episodes: [VodEpisode]) -> VodEpisode? {
        guard let index = episodes.firstIndex(where: { $0.id == snapshot.lastEpisodeID }) else {
            return episodes.first
        }
        let current = episodes[index]
        guard snapshot.episodes[current.id]?.completed == true else { return current }
        return episodes.dropFirst(index + 1).first ?? current
    }

    public mutating func start(playbackID: UUID, episodeID: String) -> Double? {
        self.playbackID = playbackID
        self.episodeID = episodeID
        readyDuration = nil
        lastSample = nil
        guard let progress = snapshot.episodes[episodeID], !progress.completed, progress.position > 0 else { return nil }
        return progress.position
    }

    @discardableResult
    public mutating func ready(playbackID: UUID, duration: Double, updatedAt: Date = .now) -> Bool {
        guard self.playbackID == playbackID, readyDuration == nil, let episodeID else { return false }
        let saved = snapshot.episodes[episodeID]
        let position = saved?.completed == false ? saved?.position ?? 0 : 0
        guard update(episodeID, position: position, duration: duration, completed: false, updatedAt: updatedAt) else {
            return false
        }
        readyDuration = duration
        return true
    }

    public mutating func invalidate() {
        playbackID = nil
        episodeID = nil
        readyDuration = nil
        lastSample = nil
    }

    @discardableResult
    public mutating func record(playbackID: UUID, position: Double, duration: Double, updatedAt: Date = .now) -> Bool {
        guard playbackID == self.playbackID, readyDuration != nil, let episodeID, lastSample?.completed != true else {
            return false
        }
        return update(episodeID, position: position, duration: duration, completed: false, updatedAt: updatedAt)
    }

    @discardableResult
    public mutating func seekSucceeded(playbackID: UUID, position: Double, duration: Double,
                                      creditsStart: Double?, updatedAt: Date = .now) -> Bool {
        guard playbackID == self.playbackID, readyDuration != nil, let episodeID else { return false }
        let completed = position >= (creditsStart ?? duration)
        return update(episodeID, position: position, duration: duration, completed: completed, updatedAt: updatedAt)
    }

    @discardableResult
    public mutating func markCreditsReached(playbackID: UUID, position: Double, duration: Double,
                                           updatedAt: Date = .now) -> Bool {
        guard playbackID == self.playbackID, readyDuration != nil, let episodeID, lastSample?.completed != true else {
            return false
        }
        return update(episodeID, position: position, duration: duration, completed: true, updatedAt: updatedAt)
    }

    @discardableResult
    public mutating func complete(playbackID: UUID, updatedAt: Date = .now) -> Bool {
        guard let duration = lastSample?.duration ?? readyDuration else { return false }
        return markCreditsReached(playbackID: playbackID, position: duration, duration: duration, updatedAt: updatedAt)
    }

    private mutating func update(_ episodeID: String, position: Double, duration: Double,
                                 completed: Bool, updatedAt: Date) -> Bool {
        guard position.isFinite else { return false }
        let sample = VodEpisodeProgress(position: min(position, duration), duration: duration,
                                        completed: completed, updatedAt: updatedAt)
        guard sample.isValid else { return false }
        if let lastSample, lastSample.position == sample.position, lastSample.duration == sample.duration,
           lastSample.completed == sample.completed {
            return false
        }
        lastSample = sample
        snapshot.episodes[episodeID] = sample
        snapshot.lastEpisodeID = episodeID
        return true
    }
}
