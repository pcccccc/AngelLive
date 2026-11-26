import Foundation
import Observation

public extension Notification.Name {
    static let platformAppearanceDidChange = Notification.Name("PlatformAppearanceDidChange")
}

@MainActor
@Observable
public final class PlatformAppearanceStore {
    public enum ChangeSource: String, Sendable { case local, sync }

    public static let shared = PlatformAppearanceStore(directory: defaultDirectory, useHostDefaults: true)
    nonisolated static let changeSourceKey = "source"
    nonisolated static var defaultDirectory: URL {
        #if os(tvOS)
        let root = URL.cachesDirectory
        #else
        let root = URL.applicationSupportDirectory
        #endif
        return root.appendingPathComponent("AngelLive", isDirectory: true)
    }

    public private(set) var snapshot = PlatformAppearanceSnapshot()
    public private(set) var isReady = false
    public private(set) var assetsRevision = 0
    public private(set) var profileRevision = 0
    public private(set) var persistenceFailed = false

    @ObservationIgnored private let disk: PlatformAppearanceDisk
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public convenience init(directory: URL) {
        self.init(directory: directory, useHostDefaults: false)
    }

    init(directory: URL, useHostDefaults: Bool, initialSnapshot: PlatformAppearanceSnapshot = .init()) {
        disk = PlatformAppearanceDisk(directory: directory, useHostDefaults: useHostDefaults)
        loadTask = Task { [weak self, disk] in
            do {
                let (scope, snapshot) = try await disk.loadActive(fallback: initialSnapshot)
                self?.scope = scope
                self?.snapshot = snapshot
                self?.isReady = true
            } catch {
                self?.persistenceFailed = true
            }
        }
    }

    public func ready() async { await loadTask?.value }

    public func orderedPlatforms(_ platforms: [Platformdescription]) -> [Platformdescription] {
        snapshot.ordered(platforms, id: \.pluginId)
    }

    public func updateGlobal<Value>(
        _ keyPath: WritableKeyPath<PlatformAppearanceSnapshot, Value>, to value: Value
    ) {
        guard isReady else { return }
        let supported = keyPath == \PlatformAppearanceSnapshot.globalBackground
            || keyPath == \PlatformAppearanceSnapshot.backgroundBlurRadius
            || keyPath == \PlatformAppearanceSnapshot.contrastScrimEnabled
            || keyPath == \PlatformAppearanceSnapshot.gridDensity
            || keyPath == \PlatformAppearanceSnapshot.cardAspect
        guard supported else { return }
        var next = snapshot
        next[keyPath: keyPath] = value
        next = next.normalized
        guard next != snapshot else { return }
        next.globalUpdatedAt = timestamp(after: snapshot.globalUpdatedAt)
        commit(next, source: .local)
    }

    public func updateMetrics(_ metrics: PlatformIdiomCustomMetrics, for idiom: PlatformDeviceIdiom) {
        guard isReady else { return }
        let metrics = metrics.clamped(for: idiom)
        guard snapshot.metrics(for: idiom) != metrics else { return }
        var next = snapshot
        next.idiomMetrics[idiom] = metrics
        next.idiomUpdatedAt[idiom] = timestamp(after: snapshot.idiomUpdatedAt[idiom] ?? .distantPast)
        commit(next, source: .local)
    }

    public func setOrder(_ installedIDs: [String]) {
        guard isReady else { return }
        let order = (installedIDs + snapshot.orderedPluginIds).preservingFirstOccurrence
        guard order != snapshot.orderedPluginIds else { return }
        var next = snapshot
        next.orderedPluginIds = order
        next.orderUpdatedAt = timestamp(after: snapshot.orderUpdatedAt)
        commit(next, source: .local)
    }

    public func move(_ pluginID: String, by offset: Int, among orderedIDs: [String]) {
        guard let index = orderedIDs.firstIndex(of: pluginID),
              (-1...1).contains(offset), orderedIDs.indices.contains(index + offset), offset != 0 else { return }
        var ids = orderedIDs
        ids.swapAt(index, index + offset)
        setOrder(ids)
    }

    public func updateCard(_ pluginID: String, change: (inout PlatformCardAppearanceOverride) -> Void) {
        guard isReady, !pluginID.isEmpty else { return }
        let previous = snapshot.appearance(for: pluginID)
        var card = previous
        change(&card)
        card.pluginId = pluginID
        card.updatedAt = previous.updatedAt
        card = card.normalized
        guard card != previous else { return }
        var next = snapshot
        card.updatedAt = timestamp(after: max(previous.updatedAt, next.latestReset(for: pluginID) ?? .distantPast))
        next.cardOverrides[pluginID] = card
        next.resetTombstones.removeValue(forKey: pluginID)
        commit(next, source: .local)
    }

    public func resetCard(_ pluginID: String) {
        guard isReady, !pluginID.isEmpty else { return }
        var next = snapshot
        let removed = next.cardOverrides.removeValue(forKey: pluginID)
        next.resetTombstones[pluginID] = timestamp(after: max(removed?.updatedAt ?? .distantPast,
                                                               next.latestReset(for: pluginID) ?? .distantPast))
        commit(next, source: .local)
    }

    public func resetAll(defaultOrder: [String]) {
        guard isReady else { return }
        var next = PlatformAppearanceSnapshot()
        next.globalUpdatedAt = timestamp(after: snapshot.globalUpdatedAt)
        next.orderedPluginIds = (defaultOrder + snapshot.orderedPluginIds).preservingFirstOccurrence
        next.orderUpdatedAt = timestamp(after: snapshot.orderUpdatedAt)
        for idiom in PlatformDeviceIdiom.allCases {
            next.idiomUpdatedAt[idiom] = timestamp(after: snapshot.idiomUpdatedAt[idiom] ?? .distantPast)
        }
        // A global reset also covers older overrides this device has never downloaded.
        next.allCardsResetAt = timestamp(after: max(
            snapshot.allCardsResetAt ?? .distantPast,
            snapshot.cardOverrides.values.map(\.updatedAt).max() ?? .distantPast,
            snapshot.resetTombstones.values.max() ?? .distantPast
        ))
        commit(next, source: .local)
    }

    func bind(to newScope: String) async throws {
        await ready()
        guard isReady else { throw CocoaError(.fileReadCorruptFile) }
        guard PlatformAppearanceDisk.isScope(newScope) else { throw PlatformAppearanceStorageError.accountChanged }
        if scope == newScope {
            try await disk.setActiveScope(newScope)
            return
        }
        let stored = try await disk.load(scope: newScope)
        try Task.checkCancellation()
        let previousScope = scope
        let next = stored ?? (previousScope == nil ? snapshot : PlatformAppearanceSnapshot())
        // Keep edits made while loading under the previous account's disk path.
        scope = newScope
        if previousScope != nil || stored != nil { profileRevision += 1 }
        commit(next, source: .sync)
        try await flush()
        try await disk.setActiveScope(newScope)
    }

    func applySynced(_ value: PlatformAppearanceSnapshot, expected: PlatformAppearanceSnapshot, scope: String) -> Bool {
        guard self.scope == scope, snapshot == expected else { return false }
        if value != snapshot { commit(value, source: .sync) }
        return true
    }

    func notifyDownloadedAsset() {
        assetsRevision += 1
        postChange(.sync)
    }

    func flush() async throws {
        await saveTask?.value
        let revision = revision
        do {
            try await disk.save(snapshot, scope: scope, revision: revision)
            if revision == self.revision { persistenceFailed = false }
        } catch {
            if revision == self.revision { persistenceFailed = true }
            throw error
        }
    }

    func retainedAssetIDs() async throws -> Set<String> {
        let stored = try await disk.referencedAssetIDs()
        return stored.union(snapshot.referencedAssetIDs)
    }

    private func commit(_ value: PlatformAppearanceSnapshot, source: ChangeSource) {
        snapshot = value
        revision += 1
        let revision = revision
        let scope = scope
        saveTask = Task { [weak self, disk] in
            do {
                try await disk.save(value, scope: scope, revision: revision)
                if self?.revision == revision { self?.persistenceFailed = false }
            } catch {
                if self?.revision == revision { self?.persistenceFailed = true }
            }
        }
        postChange(source)
    }

    private func postChange(_ source: ChangeSource) {
        NotificationCenter.default.post(name: .platformAppearanceDidChange, object: self,
                                        userInfo: [Self.changeSourceKey: source.rawValue])
    }

    private func timestamp(after previous: Date) -> Date {
        max(.now, previous.addingTimeInterval(0.001))
    }
}

private actor PlatformAppearanceDisk {
    private let directory: URL
    private let useHostDefaults: Bool
    private var writtenRevisions: [String: Int] = [:]
    private var activeScope: String?
    private static let name = "platform-appearance-v1"
    private static let scopeKey = "SimpleLive.Setting.PlatformAppearanceAccountScope"
    private static let backupKey = "SimpleLive.Setting.PlatformAppearanceBackups"

    init(directory: URL, useHostDefaults: Bool) {
        self.directory = directory
        self.useHostDefaults = useHostDefaults
    }

    func loadActive(fallback: PlatformAppearanceSnapshot) throws -> (String?, PlatformAppearanceSnapshot) {
        #if os(tvOS)
        if useHostDefaults {
            activeScope = UserDefaults.standard.string(forKey: Self.scopeKey)
        } else {
            activeScope = try readScopeMarker()
        }
        #else
        activeScope = try readScopeMarker()
        #endif
        if let activeScope, !Self.isScope(activeScope) { throw CocoaError(.fileReadCorruptFile) }
        return (activeScope, try load(scope: activeScope) ?? fallback)
    }

    func load(scope: String?) throws -> PlatformAppearanceSnapshot? {
        let url = fileURL(scope: scope)
        #if os(tvOS)
        if useHostDefaults,
           let data = UserDefaults.standard.dictionary(forKey: Self.backupKey)?[url.lastPathComponent] as? Data {
            return try PlatformAppearanceSnapshot.decode(data).normalized
        }
        #endif
        do {
            return try PlatformAppearanceSnapshot.decode(Data(contentsOf: url)).normalized
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func setActiveScope(_ scope: String) throws {
        guard scope != activeScope else { return }
        #if os(tvOS)
        if useHostDefaults {
            UserDefaults.standard.set(scope, forKey: Self.scopeKey)
        } else {
            try Data(scope.utf8).write(to: scopeMarkerURL, options: .atomic)
        }
        #else
        try Data(scope.utf8).write(to: scopeMarkerURL, options: .atomic)
        #endif
        activeScope = scope
    }

    func save(_ snapshot: PlatformAppearanceSnapshot, scope: String?, revision: Int) throws {
        let url = fileURL(scope: scope)
        let key = url.lastPathComponent
        guard revision > writtenRevisions[key, default: -1] else { return }
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        #if os(tvOS)
        if useHostDefaults {
            var backups = UserDefaults.standard.dictionary(forKey: Self.backupKey) ?? [:]
            backups[key] = data
            UserDefaults.standard.set(backups, forKey: Self.backupKey)
        }
        #endif
        writtenRevisions[key] = revision
    }

    func referencedAssetIDs() throws -> Set<String> {
        var result = Set<String>()
        #if os(tvOS)
        if useHostDefaults {
            for data in (UserDefaults.standard.dictionary(forKey: Self.backupKey) ?? [:]).values.compactMap({ $0 as? Data }) {
                result.formUnion(try PlatformAppearanceSnapshot.decode(data).referencedAssetIDs)
            }
        }
        #endif
        guard FileManager.default.fileExists(atPath: directory.path) else { return result }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.lastPathComponent.hasPrefix(Self.name) && url.pathExtension == "json" {
            result.formUnion(try PlatformAppearanceSnapshot.decode(Data(contentsOf: url)).referencedAssetIDs)
        }
        return result
    }

    private func fileURL(scope: String?) -> URL {
        let base = scope.map { "\(Self.name)-\($0)" } ?? Self.name
        return directory.appendingPathComponent(base).appendingPathExtension("json")
    }

    nonisolated static func isScope(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private var scopeMarkerURL: URL {
        directory.appendingPathComponent("platform-appearance-account-v1", isDirectory: false)
    }

    private func readScopeMarker() throws -> String? {
        do {
            return try String(contentsOf: scopeMarkerURL, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
