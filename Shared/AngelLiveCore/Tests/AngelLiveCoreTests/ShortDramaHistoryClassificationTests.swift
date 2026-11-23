import Foundation
import Testing
@testable import AngelLiveCore

@Suite("History classification batches")
@MainActor
struct ShortDramaHistoryClassificationTests {
    @Test("Live history switch candidates retain current order and exclude drama duplicates")
    func liveHistorySwitchCandidates() {
        let store = ShortDramaProgressStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let current = room("current", "live-alias")
        let drama = room("drama", "drama-alias")
        let next = room("next", "live-alias")
        let rooms = [current, drama, next, current, next]
        let snapshot = ShortDramaHistoryClassification.make(for: rooms, platforms: {
            ["drama-alias": platform("source-a", ["drama-alias"]), "live-alias": platform("source-b", ["live-alias"])]
        }, installedPluginIDs: { ["source-a", "source-b"] }, resolveManifest: { id in
            manifest(id, version: "1.0.0", drama: id == "source-a")
        })
        let filtered = store.liveHistory(from: rooms, classification: snapshot)
        let candidates = RoomSwitchCandidates.orderedRooms(for: .history, favorites: [], history: filtered, category: [])
        #expect(candidates == [current, next])
        #expect(RoomSwitchCandidates.orderedRooms(for: .history, favorites: [], history: [], category: []).isEmpty)
    }
    @Test("one batch discovers platforms once and resolves each relevant installed plugin once")
    func batchUsesDistinctPlugins() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ShortDramaProgressStore(directory: directory)
        let rooms = (0..<30).map { room("drama-\($0)", "drama-alias") }
            + [room("same", "second-alias"), room("same", "live-alias"),
               room("unknown", "missing-alias"), room("uninstalled", "uninstalled-alias")]
        let drama = platform("source-a", ["drama-alias", "second-alias"])
        let live = platform("source-b", ["live-alias"])
        let missing = platform("source-c", ["uninstalled-alias"])
        var platformCalls = 0, installedCalls = 0
        var resolutions: [String: Int] = [:]
        let snapshot = ShortDramaHistoryClassification.make(for: rooms, platforms: {
            platformCalls += 1
            return ["drama-alias": drama, "second-alias": drama, "live-alias": live, "uninstalled-alias": missing]
        }, installedPluginIDs: {
            installedCalls += 1
            return ["source-a", "source-b"]
        }, resolveManifest: { id in
            resolutions[id, default: 0] += 1
            return manifest(id, version: "1.0.0", drama: id == "source-a")
        })
        let remaining = store.liveHistory(from: rooms, classification: snapshot)
        #expect(remaining.map(\.id) == Array(rooms.suffix(3)).map(\.id))
        #expect(platformCalls == 1)
        #expect(installedCalls == 1)
        #expect(resolutions == ["source-a": 1, "source-b": 1])
    }

    @Test("a new batch follows the effective installed version after unpinning")
    func newBatchUsesEffectiveVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        try storage.ensureDirectories()
        for (version, drama) in [("1.0.0", true), ("2.0.0", false)] {
            let directory = storage.pluginVersionDirectory(pluginId: "fixture.plugin", version: version)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(manifest("fixture.plugin", version: version, drama: drama))
                .write(to: directory.appendingPathComponent("manifest.json"))
            try Data("globalThis.LiveParsePlugin = { apiVersion: 1 };".utf8)
                .write(to: directory.appendingPathComponent("index.js"))
        }
        try storage.saveState(.init(plugins: ["fixture.plugin": .init(pinnedVersion: "1.0.0")]))
        let manager = LiveParsePluginManager(storage: storage, bundle: .main)
        let rooms = [room("room", "fixture-alias")]
        let store = ShortDramaProgressStore(directory: root.appendingPathComponent("progress"))
        func classify() -> ShortDramaHistoryClassification {
            .make(for: rooms, platforms: { ["fixture-alias": platform("fixture.plugin", ["fixture-alias"])] },
                  installedPluginIDs: { ["fixture.plugin"] },
                  resolveManifest: { try manager.resolve(pluginId: $0).manifest })
        }
        let pinned = classify()
        #expect(store.liveHistory(from: rooms, classification: pinned).isEmpty)
        try manager.unpin(pluginId: "fixture.plugin")
        let updated = classify()
        #expect(store.liveHistory(from: rooms, classification: updated).map(\.id) == rooms.map(\.id))
        #expect(store.liveHistory(from: rooms, classification: pinned).isEmpty)
    }

    @Test("hidden history remains excluded after its plugin is unavailable")
    func hiddenUninstalledHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShortDramaProgressStore(directory: root)
        let drama = room("shared", "old-alias")
        let otherSource = room("shared", "other-alias")
        let key = ShortDramaProgressKey(pluginID: "fixture.plugin", roomID: "shared")
        try store.recordPlaybackStarted(metadata: ShortDramaHistoryMetadata(room: drama), for: key)
        try store.removeHistory(for: key)
        let rooms = [drama, otherSource]
        let snapshot = ShortDramaHistoryClassification.make(for: rooms, platforms: { [:] },
                                                             installedPluginIDs: { [] },
                                                             resolveManifest: { _ in throw FixtureError.unavailable })
        #expect(store.historyEntries.isEmpty)
        #expect(store.liveHistory(from: rooms, classification: snapshot).map(\.id) == [otherSource.id])
    }

    private func platform(_ id: String, _ types: [LiveType]) -> LiveParseJSPlatform {
        LiveParseJSPlatform(pluginId: id, liveTypes: types)
    }

    private func manifest(_ id: String, version: String, drama: Bool) -> LiveParsePluginManifest {
        LiveParsePluginManifest(pluginId: id, version: version, apiVersion: 1, liveTypes: ["fixture-alias"],
                                entry: "index.js", hostBehavior: drama ? .init(contentKind: "shortDrama", episodeSelection: "qualityList") : nil)
    }

    private func room(_ id: String, _ type: LiveType) -> LiveModel {
        LiveModel(userName: "Fixture", roomTitle: "Fixture room", roomCover: "", userHeadImg: "",
                  liveType: type, liveState: nil, userId: "author", roomId: id, liveWatchedCount: nil)
    }

    private enum FixtureError: Error { case unavailable }
}
