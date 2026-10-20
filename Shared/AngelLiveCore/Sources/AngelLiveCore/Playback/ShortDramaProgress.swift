import CryptoKit
import Foundation
import Observation

public struct ShortDramaProgressKey: Codable, Hashable, Sendable {
    public let pluginID: String
    public let roomID: String

    public init(pluginID: String, roomID: String) {
        self.pluginID = pluginID
        self.roomID = roomID
    }

    var isValid: Bool {
        !pluginID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filename: String {
        let identity = "\(pluginID.utf8.count):\(pluginID)\(roomID.utf8.count):\(roomID)"
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

public struct ShortDramaEpisodeProgress: Codable, Equatable, Sendable {
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

    var isValid: Bool {
        position.isFinite && position >= 0 && duration.isFinite && duration > 0
            && position <= duration && updatedAt.timeIntervalSinceReferenceDate.isFinite
    }
}

public struct ShortDramaProgressSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let key: ShortDramaProgressKey
    public fileprivate(set) var lastEpisodeID: String?
    public fileprivate(set) var episodes: [String: ShortDramaEpisodeProgress]
    public fileprivate(set) var historyMetadata: ShortDramaHistoryMetadata?
    public fileprivate(set) var historyHidden: Bool?

    public init(key: ShortDramaProgressKey) {
        version = 1
        self.key = key
        lastEpisodeID = nil
        episodes = [:]
    }

    var isValid: Bool {
        version == 1 && key.isValid && episodes.allSatisfy { !$0.key.isEmpty && $0.value.isValid }
            && (lastEpisodeID.map { episodes[$0] != nil } ?? true)
            && (historyMetadata?.isValid ?? true)
    }
}

/// One small atomic file per drama. Playback URLs and credentials never enter the snapshot.
@MainActor
@Observable
public final class ShortDramaProgressStore {
    public static let shared = ShortDramaProgressStore()
    public enum StorageError: Error { case invalidSnapshot }
    public private(set) var historyEntries: [ShortDramaHistoryEntry] = []
    public private(set) var historyWarning: String?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let write: (Data, URL) throws -> Void
    @ObservationIgnored private let resolveHistoryPlugin: (LiveModel) -> String?
    @ObservationIgnored private var entries: [ShortDramaProgressKey: Entry] = [:]
    @ObservationIgnored private var readFailures: [ShortDramaProgressKey: any Error] = [:]
    @ObservationIgnored private var historyLoaded = false

    private struct Entry {
        var snapshot: ShortDramaProgressSnapshot
        var dirty = false
        var lastFlushAttempt: Date?
    }

    public init(directory: URL? = nil) {
        #if os(tvOS)
        // Like the existing local favorites store, this is best-effort on tvOS and may be purged.
        let base = URL.cachesDirectory
        #else
        let base = URL.applicationSupportDirectory
        #endif
        self.directory = directory ?? base.appendingPathComponent("ShortDramaProgress", isDirectory: true)
        write = { data, url in try data.write(to: url, options: .atomic) }
        resolveHistoryPlugin = Self.shortDramaPluginID
    }

    init(directory: URL, write: @escaping (Data, URL) throws -> Void,
         resolveHistoryPlugin: ((LiveModel) -> String?)? = nil) {
        self.directory = directory
        self.write = write
        self.resolveHistoryPlugin = resolveHistoryPlugin ?? Self.shortDramaPluginID
    }

    public func load(for key: ShortDramaProgressKey) throws -> ShortDramaProgressSnapshot {
        guard key.isValid else { throw StorageError.invalidSnapshot }
        if let failure = readFailures[key] { throw failure }
        if let entry = entries[key] { return entry.snapshot }
        do {
            let snapshot = try readSnapshot(for: key)
            entries[key] = Entry(snapshot: snapshot)
            refreshHistoryEntries()
            return snapshot
        } catch {
            // Keep the unreadable file and prevent a later session from overwriting it with defaults.
            readFailures[key] = error
            throw error
        }
    }

    public func updateEpisode(
        _ progress: ShortDramaEpisodeProgress, episodeID: String, for key: ShortDramaProgressKey,
        historyMetadata: ShortDramaHistoryMetadata? = nil
    ) throws {
        guard progress.isValid, !episodeID.isEmpty, historyMetadata?.isValid ?? true else {
            throw StorageError.invalidSnapshot
        }
        _ = try load(for: key)
        entries[key]?.snapshot.episodes[episodeID] = progress
        entries[key]?.snapshot.lastEpisodeID = episodeID
        if let historyMetadata { entries[key]?.snapshot.historyMetadata = historyMetadata }
        entries[key]?.dirty = true
        refreshHistoryEntries()
    }

    /// Enumerate once, then use accepted in-memory events. A failed read is retried on the next visit.
    /// Legacy rooms only enrich matching existing progress; they never fabricate a watched position.
    public func loadHistory(legacyRooms: [LiveModel] = []) {
        var failed = false
        if !historyLoaded || historyWarning != nil {
            do {
                let files: [URL]
                do {
                    files = try FileManager.default.contentsOfDirectory(
                        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    historyLoaded = true
                    migrateLegacyHistory(legacyRooms, failed: &failed)
                    historyWarning = failed ? "部分短剧历史暂时无法读取或保存" : nil
                    refreshHistoryEntries()
                    return
                }
                let cachedFilenames = Set(entries.keys.map(\.filename))
                for file in files where file.pathExtension == "json" && !cachedFilenames.contains(file.lastPathComponent) {
                    do {
                        let snapshot = try JSONDecoder().decode(ShortDramaProgressSnapshot.self,
                                                               from: Data(contentsOf: file))
                        guard snapshot.isValid, file.lastPathComponent == snapshot.key.filename else {
                            throw StorageError.invalidSnapshot
                        }
                        entries[snapshot.key] = Entry(snapshot: snapshot)
                        readFailures.removeValue(forKey: snapshot.key)
                    } catch {
                        // Do not remove or replace damaged/unsupported records when listing the rest.
                        failed = true
                    }
                }
                historyLoaded = true
            } catch {
                failed = true
            }
        }
        migrateLegacyHistory(legacyRooms, failed: &failed)
        historyWarning = failed ? "部分短剧历史暂时无法读取或保存" : nil
        refreshHistoryEntries()
    }

    /// FullUI classification includes hidden records, so removing a drama cannot move it into live history.
    public func isShortDramaHistory(_ room: LiveModel) -> Bool {
        if resolveHistoryPlugin(room) != nil { return true }
        return entries.values.contains {
            $0.snapshot.key.roomID == room.roomId
                && $0.snapshot.historyMetadata?.recordedLiveType == room.liveType
        }
    }

    public func removeHistory(for key: ShortDramaProgressKey) throws {
        _ = try load(for: key)
        guard var candidate = entries[key], candidate.snapshot.historyHidden != true else { return }
        candidate.snapshot.historyHidden = true
        try writeHistoryChange(candidate, for: key)
    }

    public func clearHistory() throws {
        // Each independent file commits atomically. A failed file remains visible and can be retried.
        var firstFailure: (any Error)?
        for key in historyEntries.map(\.key) {
            do { try removeHistory(for: key) } catch { if firstFailure == nil { firstFailure = error } }
        }
        if let firstFailure { throw firstFailure }
    }

    /// Called only once after a new playback UUID really becomes ready or finishes restoring.
    /// Ordinary samples may update metadata but must never undo a history removal.
    func recordPlaybackStarted(metadata: ShortDramaHistoryMetadata, for key: ShortDramaProgressKey) throws {
        guard metadata.isValid else { throw StorageError.invalidSnapshot }
        _ = try load(for: key)
        guard var candidate = entries[key] else { return }
        candidate.snapshot.historyMetadata = metadata
        candidate.snapshot.historyHidden = false
        // Share the same failure throttle as ordinary progress writes.
        entries[key]?.lastFlushAttempt = .now
        try writeHistoryChange(candidate, for: key)
    }

    private func writeHistoryChange(_ candidate: Entry, for key: ShortDramaProgressKey) throws {
        let data = try JSONEncoder().encode(candidate.snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(data, directory.appendingPathComponent(key.filename))
        var committed = candidate
        committed.dirty = false
        committed.lastFlushAttempt = .now
        entries[key] = committed
        refreshHistoryEntries()
    }

    private func migrateLegacyHistory(_ rooms: [LiveModel], failed: inout Bool) {
        for room in rooms {
            guard let pluginID = resolveHistoryPlugin(room) else { continue }
            let key = ShortDramaProgressKey(pluginID: pluginID, roomID: room.roomId)
            guard var candidate = entries[key], candidate.snapshot.historyMetadata == nil,
                  !candidate.snapshot.episodes.isEmpty else { continue }
            let updatedAt = candidate.snapshot.episodes.values.map(\.updatedAt).max() ?? .now
            candidate.snapshot.historyMetadata = ShortDramaHistoryMetadata(room: room, lastWatchedAt: updatedAt)
            do { try writeHistoryChange(candidate, for: key) } catch { failed = true }
        }
    }

    private func refreshHistoryEntries() {
        historyEntries = entries.values.compactMap { entry in
            let snapshot = entry.snapshot
            guard snapshot.historyHidden != true,
                  !snapshot.episodes.isEmpty || snapshot.historyMetadata != nil else { return nil }
            return ShortDramaHistoryEntry(snapshot: snapshot)
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.key.pluginID != $1.key.pluginID { return $0.key.pluginID < $1.key.pluginID }
            return $0.key.roomID < $1.key.roomID
        }
    }

    private static func shortDramaPluginID(_ room: LiveModel) -> String? {
        guard let platform = LiveParseJSPlatformManager.platform(for: room.liveType),
              SandboxPluginCatalog.isInstalled(pluginId: platform.pluginId),
              let behavior = try? LiveParsePlugins.shared.resolve(pluginId: platform.pluginId).manifest.hostBehavior,
              behavior.contentKind == "shortDrama", behavior.episodeSelection == "qualityList" else { return nil }
        return platform.pluginId
    }

    public func flush(for key: ShortDramaProgressKey) throws {
        _ = try load(for: key)
        try persist(for: key, now: .now)
    }

    public func flushIfNeeded(for key: ShortDramaProgressKey, now: Date = .now) throws {
        _ = try load(for: key)
        guard let entry = entries[key], entry.dirty,
              entry.lastFlushAttempt.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        try persist(for: key, now: now)
    }

    private func readSnapshot(for key: ShortDramaProgressKey) throws -> ShortDramaProgressSnapshot {
        let file = directory.appendingPathComponent(key.filename)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ShortDramaProgressSnapshot(key: key)
        }
        let snapshot = try JSONDecoder().decode(ShortDramaProgressSnapshot.self, from: data)
        guard snapshot.isValid, snapshot.key == key else { throw StorageError.invalidSnapshot }
        return snapshot
    }

    /// Test setup seam only. Production hosts submit one accepted episode event at a time.
    func save(_ snapshot: ShortDramaProgressSnapshot) throws {
        guard snapshot.isValid else { throw StorageError.invalidSnapshot }
        _ = try load(for: snapshot.key)
        entries[snapshot.key]?.snapshot = snapshot
        entries[snapshot.key]?.dirty = true
        try flush(for: snapshot.key)
    }

    private func persist(for key: ShortDramaProgressKey, now: Date) throws {
        guard let entry = entries[key], entry.dirty else { return }
        entries[key]?.lastFlushAttempt = now
        let data = try JSONEncoder().encode(entry.snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(data, directory.appendingPathComponent(key.filename))
        entries[key]?.dirty = false
    }
}

/// Validates samples against the active player and keeps EOF sticky until an explicit seek/replay.
public struct ShortDramaProgressSession: Sendable {
    public private(set) var snapshot: ShortDramaProgressSnapshot
    private var playbackID: UUID?
    private var episodeID: String?
    private var acceptsSamples = false
    private var lastSample: Sample?

    private struct Sample: Equatable, Sendable {
        let position: Double
        let duration: Double
        let completed: Bool
    }

    var activeEpisodeID: String? { episodeID }

    public init(snapshot: ShortDramaProgressSnapshot) {
        self.snapshot = snapshot
    }

    public func preferredEpisode(in episodes: [ShortDramaEpisode]) -> ShortDramaEpisode? {
        if let saved = episodes.first(where: { $0.id == snapshot.lastEpisodeID }),
           ShortDramaCompletionPolicy.firstPlayableEpisode(in: [saved]) != nil {
            return saved
        }
        return ShortDramaCompletionPolicy.firstPlayableEpisode(in: episodes)
    }

    public mutating func start(playbackID: UUID, episodeID: String) -> Double? {
        self.playbackID = playbackID
        self.episodeID = episodeID
        acceptsSamples = false
        lastSample = nil
        guard let progress = snapshot.episodes[episodeID], !progress.completed, progress.position > 0 else {
            return nil
        }
        return progress.position
    }

    /// Readiness is accepted once per UUID and only with a usable media duration.
    /// A replay clears an old completion here, never again on later ready/buffer callbacks.
    @discardableResult
    public mutating func ready(playbackID: UUID, duration: Double, updatedAt: Date = .now) -> Bool {
        guard self.playbackID == playbackID, !acceptsSamples, let episodeID,
              duration.isFinite, duration > 0, updatedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        acceptsSamples = true
        if snapshot.episodes[episodeID]?.completed == true {
            _ = update(episodeID: episodeID, position: 0, duration: duration,
                       completed: false, updatedAt: updatedAt)
        }
        return true
    }

    public mutating func invalidate() {
        playbackID = nil
        episodeID = nil
        acceptsSamples = false
        lastSample = nil
    }

    @discardableResult
    public mutating func record(
        playbackID: UUID, position: Double, duration: Double, updatedAt: Date = .now
    ) -> Bool {
        guard acceptsSamples, self.playbackID == playbackID, let episodeID,
              position.isFinite, position >= 0, duration.isFinite, duration > 0 else { return false }
        // Periodic samples after EOF must not undo the recorded completion.
        let completed = snapshot.episodes[episodeID]?.completed == true
        let sample = Sample(position: completed ? duration : min(position, duration),
                            duration: duration, completed: completed)
        guard sample != lastSample,
              update(episodeID: episodeID, position: sample.position, duration: duration,
                     completed: completed, updatedAt: updatedAt) else { return false }
        lastSample = sample
        return true
    }

    @discardableResult
    public mutating func seekSucceeded(
        playbackID: UUID, position: Double, duration: Double, updatedAt: Date = .now
    ) -> Bool {
        guard acceptsSamples, self.playbackID == playbackID, let episodeID,
              position.isFinite, position >= 0, duration.isFinite, duration > 0 else { return false }
        let target = min(position, duration)
        let completed = position >= duration
        guard update(episodeID: episodeID, position: target, duration: duration,
                     completed: completed, updatedAt: updatedAt) else { return false }
        lastSample = Sample(position: target, duration: duration, completed: completed)
        return true
    }

    @discardableResult
    public mutating func complete(playbackID: UUID, updatedAt: Date = .now) -> Bool {
        guard acceptsSamples, self.playbackID == playbackID, let episodeID,
              let progress = snapshot.episodes[episodeID] else { return false }
        guard update(episodeID: episodeID, position: progress.duration, duration: progress.duration,
                     completed: true, updatedAt: updatedAt) else { return false }
        lastSample = Sample(position: progress.duration, duration: progress.duration, completed: true)
        return true
    }

    private mutating func update(
        episodeID: String, position: Double, duration: Double, completed: Bool, updatedAt: Date
    ) -> Bool {
        let progress = ShortDramaEpisodeProgress(position: position, duration: duration,
                                                completed: completed, updatedAt: updatedAt)
        guard progress.isValid else { return false }
        snapshot.episodes[episodeID] = progress
        snapshot.lastEpisodeID = episodeID
        return true
    }
}
