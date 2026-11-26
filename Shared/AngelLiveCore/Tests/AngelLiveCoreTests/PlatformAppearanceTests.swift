import CloudKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AngelLiveCore

@Suite struct PlatformAppearanceTests {
    private let older = Date(timeIntervalSince1970: 10)
    private let newer = Date(timeIntervalSince1970: 20)

    @Test func defaultsAndCustomizedValuesRoundTrip() throws {
        let defaults = PlatformAppearanceSnapshot()
        #expect(defaults.gridDensity == .standard)
        #expect(defaults.cardAspect == .classic)
        #expect(defaults.globalBackground == .defaultAsset)
        #expect(defaults.metrics(for: .tv).columns == 4)
        #expect(try PlatformAppearanceSnapshot.decode(JSONEncoder().encode(defaults)) == defaults)

        var customized = defaults
        customized.cardOverrides["fixture.alpha"] = .init(
            pluginId: "fixture.alpha", logoMode: .monogramBadge(text: "甲乙", tintHex: "#347B9E"),
            titleVisibility: .always, backgroundOverride: .preset(.ocean), spansTwoColumns: true, updatedAt: newer
        )
        customized.idiomMetrics[.mac] = .init(useCustomMetrics: true, columns: 5, cardHeight: 140, cornerRadius: 19)
        customized.idiomUpdatedAt[.mac] = newer
        customized.resetTombstones["fixture.beta"] = older
        #expect(try PlatformAppearanceSnapshot.decode(JSONEncoder().encode(customized)) == customized)

        let shortHex = try #require(PlatformRGBAColor(hex: "#3aF"))
        #expect(shortHex.red == Double(0x33) / 255)
        #expect(shortHex.blue == 1)
        #expect(PlatformRGBAColor(hex: "347B9E80")?.alpha == Double(0x80) / 255)
        #expect(PlatformRGBAColor(hex: "12ZZ34") == nil)
    }

    @Test(arguments: PlatformDeviceIdiom.allCases)
    func customMetricsClampPerIdiom(_ idiom: PlatformDeviceIdiom) {
        let large = PlatformIdiomCustomMetrics(useCustomMetrics: true, columns: 50, cardHeight: 1_000, cornerRadius: 100)
            .clamped(for: idiom)
        let small = PlatformIdiomCustomMetrics(columns: -4, cardHeight: 0, cornerRadius: -1)
            .clamped(for: idiom)
        #expect(large == .init(useCustomMetrics: true, columns: idiom.columnRange.upperBound,
                              cardHeight: idiom.cardHeightRange.upperBound, cornerRadius: idiom.cornerRadiusRange.upperBound))
        #expect(small == .init(columns: idiom.columnRange.lowerBound, cardHeight: idiom.cardHeightRange.lowerBound,
                              cornerRadius: idiom.cornerRadiusRange.lowerBound))
        let nonFinite = PlatformIdiomCustomMetrics(columns: idiom.defaultMetrics.columns, cardHeight: .nan, cornerRadius: .infinity)
        #expect(nonFinite.clamped(for: idiom) == idiom.defaultMetrics)
    }

    @Test func mergesGlobalAndPerIdiomUpdatesIndependently() {
        var local = PlatformAppearanceSnapshot()
        local.globalUpdatedAt = newer
        local.gridDensity = .compact
        local.globalBackground = .systemSurface
        let phone = PlatformIdiomCustomMetrics(useCustomMetrics: true, columns: 3, cardHeight: 86, cornerRadius: 22)
        local.idiomMetrics[.phone] = phone
        local.idiomUpdatedAt[.phone] = newer
        local.idiomUpdatedAt[.mac] = newer

        var remote = PlatformAppearanceSnapshot()
        remote.globalUpdatedAt = older
        remote.idiomMetrics[.phone] = .init(columns: 1, cardHeight: 130, cornerRadius: 12)
        remote.idiomUpdatedAt[.phone] = older
        let pad = PlatformIdiomCustomMetrics(useCustomMetrics: true, columns: 4, cardHeight: 122, cornerRadius: 23)
        remote.idiomMetrics[.pad] = pad
        remote.idiomUpdatedAt[.pad] = older
        remote.idiomMetrics[.mac] = .init(useCustomMetrics: true, columns: 2, cardHeight: 160, cornerRadius: 12)
        remote.idiomUpdatedAt[.mac] = older

        let result = PlatformAppearanceSyncMerge.merge(local: local, remote: remote)
        #expect(result.metrics(for: .phone) == phone)
        #expect(result.metrics(for: .pad) == pad)
        #expect(result.metrics(for: .mac) == PlatformDeviceIdiom.mac.defaultMetrics)
        #expect(result.idiomUpdatedAt[.mac] == newer)
        #expect(result.gridDensity == .compact)
        #expect(result.globalBackground == .systemSurface)
    }

    @Test func winningTombstoneRemovesCardAtEqualTimeAndNewerCardCanBeRecreated() {
        var local = PlatformAppearanceSnapshot()
        local.cardOverrides["fixture.alpha"] = .init(pluginId: "fixture.alpha", spansTwoColumns: true, updatedAt: newer)
        local.resetTombstones["fixture.beta"] = older
        var remote = PlatformAppearanceSnapshot()
        remote.resetTombstones["fixture.alpha"] = newer
        remote.cardOverrides["fixture.beta"] = .init(pluginId: "fixture.beta", titleVisibility: .hidden, updatedAt: newer)

        let merged = PlatformAppearanceSyncMerge.merge(local: local, remote: remote)
        #expect(merged.cardOverrides["fixture.alpha"] == nil)
        #expect(merged.resetTombstones["fixture.alpha"] == newer)
        #expect(merged.cardOverrides["fixture.beta"]?.titleVisibility == .hidden)
        #expect(merged.resetTombstones["fixture.beta"] == nil)
        #expect(PlatformAppearanceSyncMerge.merge(local: merged, remote: local) == merged)
    }

    @Test @MainActor func globalResetAlsoCoversOlderCardsThatWereOnlyInTheCloud() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlatformAppearanceStore(directory: directory)
        await store.ready()
        store.updateGlobal(\.gridDensity, to: .compact)
        #expect(store.snapshot.gridDensity == .compact)
        store.updateMetrics(.init(useCustomMetrics: true, columns: 3, cardHeight: 100, cornerRadius: 28), for: .phone)
        #expect(store.snapshot.cardCornerRadius(for: .phone) == 28)
        store.resetAll(defaultOrder: ["fixture.beta", "fixture.alpha"])
        var remote = PlatformAppearanceSnapshot()
        remote.cardOverrides["fixture.gamma"] = .init(pluginId: "fixture.gamma", spansTwoColumns: true, updatedAt: older)
        remote.orderedPluginIds = ["fixture.alpha", "fixture.gamma"]
        remote.orderUpdatedAt = older
        let merged = PlatformAppearanceSyncMerge.merge(local: store.snapshot, remote: remote)
        #expect(merged.cardOverrides.isEmpty)
        #expect(merged.gridDensity == .standard)
        #expect(merged.cardCornerRadius(for: .phone) == PlatformDeviceIdiom.phone.defaultMetrics.cornerRadius)
        #expect(merged.orderedPluginIds == ["fixture.beta", "fixture.alpha", "fixture.gamma"])
        try await store.flush()
    }

    @Test func newerOrderWinsAndUnlistedPlatformsAppendInOriginalOrder() {
        var local = PlatformAppearanceSnapshot()
        local.orderedPluginIds = ["fixture.beta", "fixture.alpha", "fixture.beta"]
        local.orderUpdatedAt = newer
        var remote = PlatformAppearanceSnapshot()
        remote.orderedPluginIds = ["fixture.alpha", "fixture.gamma"]
        remote.orderUpdatedAt = older

        struct Platform { let id: String }
        let installed = ["fixture.new-b", "fixture.alpha", "fixture.new-a", "fixture.beta"].map(Platform.init)
        let merged = PlatformAppearanceSyncMerge.merge(local: local, remote: remote)
        #expect(merged.orderedPluginIds == ["fixture.beta", "fixture.alpha", "fixture.gamma"])
        #expect(merged.ordered(installed, id: \.id).map(\.id) == ["fixture.beta", "fixture.alpha", "fixture.new-b", "fixture.new-a"])
    }

    @Test func twoColumnSlotsAlignWithTwoAdjacentSinglesAndWrapWithoutReordering() throws {
        let planner = PlatformGridLayoutPlanner(containerWidth: 1_010, columnsCount: 3, spacing: 16, horizontalPadding: 20)
        let placements = planner.placements(spansTwoColumns: [false, false, true, false, false])
        #expect(placements.map(\.row) == [0, 0, 1, 1, 2])
        #expect(placements.map(\.column) == [0, 1, 0, 2, 0])
        #expect(placements.map(\.span) == [1, 1, 2, 1, 1])
        let left = try #require(placements.first)
        let right = placements[1]
        let wide = placements[2]
        #expect(wide.x == left.x)
        #expect(abs(wide.x + wide.width - (right.x + right.width)) < 0.000_001)
        #expect(wide.width == 2 * planner.unitWidth + 16)
        #expect(abs(placements[3].x + placements[3].width - 990) < 0.000_001)

        let single = PlatformGridLayoutPlanner(containerWidth: 320, columnsCount: 1, spacing: 16, horizontalPadding: 16)
        #expect(single.placements(spansTwoColumns: [true, false]).map(\.width) == [288, 288])
    }

    @Test func dominantColorIgnoresNeutralAndNearlyTransparentPixels() throws {
        let bitmap = try makeBitmap(size: 32) { context in
            context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
            context.setFillColor(CGColor(srgbRed: 0.1, green: 1, blue: 0.1, alpha: 0.08))
            context.fill(CGRect(x: 0, y: 24, width: 32, height: 5))
            context.setFillColor(CGColor(srgbRed: 0.92, green: 0.1, blue: 0.15, alpha: 1))
            context.fill(CGRect(x: 0, y: 29, width: 32, height: 3))
        }
        let color = try #require(PlatformIconDominantColor.extract(from: bitmap, cacheKey: "fixture.alpha"))
        #expect(color.red > 0.8 && color.green < 0.2 && color.blue < 0.2)

        let transparent = try makeBitmap(size: 32) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 1, alpha: 0.07))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        #expect(PlatformIconDominantColor.extract(from: transparent) == nil)
    }

    @Test @MainActor
    func syncRefetchesAfterServerRecordChangedAndHydratesMissingAsset() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = PlatformAppearanceAssetCache(directory: directory.appendingPathComponent("assets"))
        let store = PlatformAppearanceStore(directory: directory)
        await store.ready()
        store.updateCard("fixture.alpha") { $0.spansTwoColumns = true }

        let imageData = try makePNG(size: 64)
        let assetID = PlatformAppearanceAssetCache.assetID(for: imageData)
        var initialRemote = PlatformAppearanceSnapshot()
        initialRemote.orderUpdatedAt = older
        initialRemote.orderedPluginIds = ["fixture.beta"]
        var interveningRemote = initialRemote
        interveningRemote.orderUpdatedAt = newer
        interveningRemote.orderedPluginIds = ["fixture.gamma", "fixture.beta"]
        interveningRemote.globalBackground = .customImage(assetID: assetID, focalY: 0.3)
        interveningRemote.globalUpdatedAt = newer

        let cloud = AppearanceCloudMock(snapshot: initialRemote, conflictSnapshot: interveningRemote, assetData: [assetID: imageData])
        let service = PlatformAppearanceSyncService(store: store, assets: assets, cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .synced)
        let readback = await cloud.state()
        #expect(readback.fetches == 2)
        #expect(readback.writes == 2)
        #expect(readback.downloaded == [assetID])
        #expect(readback.snapshot.orderedPluginIds == ["fixture.gamma", "fixture.beta"])
        #expect(readback.snapshot.cardOverrides["fixture.alpha"]?.spansTwoColumns == true)
        #expect(store.snapshot == readback.snapshot)
        #expect(try await assets.data(for: assetID) == imageData)
        #expect(store.assetsRevision == 1)
    }

    @Test @MainActor
    func unavailableCloudAssetFallsBackLocallyAndNextSyncRepairsCache() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = PlatformAppearanceAssetCache(directory: directory.appendingPathComponent("assets"))
        let store = PlatformAppearanceStore(directory: directory)
        let imageData = try makePNG(size: 50)
        let assetID = PlatformAppearanceAssetCache.assetID(for: imageData)
        var remote = PlatformAppearanceSnapshot()
        remote.globalBackground = .customImage(assetID: assetID, focalY: 0.5)
        remote.globalUpdatedAt = newer
        let cloud = AppearanceCloudMock(snapshot: remote)
        let service = PlatformAppearanceSyncService(store: store, assets: assets, cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .failed)
        #expect(store.snapshot.globalBackground == remote.globalBackground)
        #expect(await assets.image(for: assetID) == nil)

        await cloud.installAsset(imageData, id: assetID)
        #expect(await service.sync() == .synced)
        #expect(try await assets.data(for: assetID) == imageData)
        #expect(await cloud.state().writes == 0)
    }

    @Test @MainActor
    func persistsOfflineMutationsAndKeepsAccountScopesSeparate() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlatformAppearanceStore(directory: directory)
        await store.ready()
        store.setOrder(["fixture.beta", "fixture.alpha"])
        store.updateCard("fixture.alpha") { $0.titleVisibility = .hidden }
        try await store.flush()

        let reloaded = PlatformAppearanceStore(directory: directory)
        await reloaded.ready()
        #expect(reloaded.snapshot == store.snapshot)
        let scopeA = PlatformAppearanceAssetCache.digest(for: Data("fixture.alpha".utf8))
        let scopeB = PlatformAppearanceAssetCache.digest(for: Data("fixture.beta".utf8))
        try await reloaded.bind(to: scopeA)
        let profileA = reloaded.snapshot
        try await reloaded.bind(to: scopeB)
        #expect(reloaded.snapshot == PlatformAppearanceSnapshot())
        try await reloaded.bind(to: scopeA)
        #expect(reloaded.snapshot == profileA)
        let reopened = PlatformAppearanceStore(directory: directory)
        await reopened.ready()
        #expect(reopened.snapshot == profileA)
    }

    @Test @MainActor
    func editDuringFetchIsMergedOnTheNextPass() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlatformAppearanceStore(directory: directory)
        let cloud = AppearanceCloudMock(snapshot: .init())
        await cloud.onNextFetch {
            await store.updateCard("fixture.alpha") { $0.spansTwoColumns = true }
        }
        let service = PlatformAppearanceSyncService(store: store, assets: .init(directory: directory), cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .synced)
        let result = await cloud.state()
        #expect(result.fetches == 2)
        #expect(result.snapshot.cardOverrides["fixture.alpha"]?.spansTwoColumns == true)
        #expect(result.snapshot == store.snapshot)
    }

    @Test @MainActor
    func accountSwitchDuringFetchDiscardsOldReplyAndNextSyncUsesNewProfile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlatformAppearanceStore(directory: directory)
        await store.ready()
        store.setOrder(["fixture.alpha"])
        let original = store.snapshot
        var oldRemote = PlatformAppearanceSnapshot()
        oldRemote.globalUpdatedAt = newer
        oldRemote.gridDensity = .compact
        let cloud = AppearanceCloudMock(snapshot: oldRemote)
        let originalScope = await cloud.accountScope()
        await cloud.onNextFetch { await cloud.switchAccount() }
        let service = PlatformAppearanceSyncService(store: store, assets: .init(directory: directory), cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .failed)
        #expect(await cloud.state().writes == 0)
        #expect(store.snapshot == original)
        #expect(await service.sync() == .synced)
        #expect(store.snapshot.orderedPluginIds.isEmpty)
        #expect(store.snapshot.gridDensity == .standard)
        #expect(await cloud.state().snapshot == store.snapshot)
        try await store.bind(to: originalScope)
        #expect(store.snapshot == original)
    }

    @Test @MainActor
    func repeatedRecordConflictsLeaveLastLocalSnapshotOnDisk() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlatformAppearanceStore(directory: directory)
        await store.ready()
        store.setOrder(["fixture.alpha"])
        let local = store.snapshot
        var remote = PlatformAppearanceSnapshot()
        remote.globalUpdatedAt = newer
        remote.gridDensity = .compact
        let cloud = AppearanceCloudMock(snapshot: remote, alwaysConflicts: true)
        let service = PlatformAppearanceSyncService(store: store, assets: .init(directory: directory), cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .failed)
        let result = await cloud.state()
        #expect(result.fetches == 3)
        #expect(result.writes == 3)
        #expect(result.snapshot == remote)
        #expect(store.snapshot == local)
        let reopened = PlatformAppearanceStore(directory: directory)
        await reopened.ready()
        #expect(reopened.snapshot == local)
    }

    @Test @MainActor
    func failedAssetUploadRetriesBeforePublishingReference() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = PlatformAppearanceAssetCache(directory: directory.appending(path: "assets"))
        let id = try await assets.importImage(makePNG(size: 48), kind: .logo)
        let store = PlatformAppearanceStore(directory: directory)
        await store.ready()
        store.updateCard("fixture.alpha") { $0.logoMode = .customImage(assetID: id) }
        let local = store.snapshot
        let cloud = AppearanceCloudMock(snapshot: .init(), failsFirstUpload: true)
        let service = PlatformAppearanceSyncService(store: store, assets: assets, cloud: cloud, isEnabled: { true })
        #expect(await service.sync() == .failed)
        #expect(await cloud.state().writes == 0)
        #expect(store.snapshot == local)
        #expect(await service.sync() == .synced)
        #expect(await cloud.state().writes == 1)
        #expect(await cloud.state().snapshot == local)
        #expect(try await assets.data(for: id) == cloud.fetchAsset(id))
    }

    #if DEBUG
    @Test func inspectionFixturesResolveThroughTheInstalledCatalog() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try PlatformAppearanceDemo.makeManager(in: directory)
        let loader = PlatformAppearanceArtworkLoader(storage: manager.storage)
        let metadata = SandboxPluginCatalog.installedPluginMap(storage: manager.storage)
        let initial = PlatformAppearanceDemo.initialSnapshot
        #expect(initial.globalBackground == .defaultAsset)
        #expect(initial.cardOverrides.isEmpty)
        #expect(Set(metadata.keys) == ["fixture.wordmark", "fixture.aura", "fixture.alpha", "fixture.beta"])
        for item in PlatformAppearanceDemo.platforms where !PlaylistPlatformIdentity.isPlaylist(item.liveType) {
            let manifest = try manager.resolve(pluginId: item.pluginId).manifest
            #expect(manifest.displayName == item.title)
            #expect(manifest.platformDescription == item.descripiton)
            let assets = manager.storage.pluginVersionDirectory(pluginId: item.pluginId, version: manifest.version)
                .appending(path: "assets")
            let files = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
            switch item.pluginId {
            case "fixture.wordmark": #expect(files.count == 2)
            case "fixture.aura": #expect(files.count == 1)
            default: #expect(files.isEmpty)
            }
            for file in files {
                let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
                let bitmap = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                if item.pluginId == "fixture.wordmark" {
                    #expect(bitmap.width >= 3 * bitmap.height)
                } else {
                    #expect(bitmap.width == bitmap.height)
                    let color = try #require(PlatformIconDominantColor.extract(from: bitmap))
                    #expect(color.red > color.green && color.green > color.blue)
                }
            }
        }
        let platforms = PlatformAppearanceDemo.platforms.map { ($0.pluginId, $0.liveType) }
        #expect(platforms.filter { PlaylistPlatformIdentity.isPlaylist($0.1) }.count == 1)
        for (id, type) in platforms {
            for dark in [false, true] {
                let artwork = await loader.artwork(
                    pluginID: id,
                    liveType: type,
                    dark: dark,
                    revision: 0,
                    includesWordmark: true
                )
                #expect((artwork.wordmark != nil) == (id == "fixture.wordmark"))
                #expect((artwork.square != nil) == (id == "fixture.aura"))
                #expect((artwork.dominantColor != nil) == (id == "fixture.aura"))
            }
        }
    }
    #endif

    @Test func imageCacheDownsamplesAndRejectsMismatchedIdentity() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PlatformAppearanceAssetCache(directory: directory)
        let png = try makePNG(size: 900)
        let id = try await cache.importImage(png, kind: .logo)
        let image = try #require(await cache.image(for: id))
        #expect(max(image.width, image.height) <= 512)
        #expect(id.count == 32)
        let encoded = try #require(try await cache.data(for: id))
        #expect(PlatformAppearanceAssetCache.assetID(for: encoded) == id)
        await #expect(throws: PlatformAppearanceAssetCache.AssetError.integrityMismatch) {
            try await cache.storeDownloaded(png, assetID: id)
        }
    }

    #if os(macOS)
    @Test func unentitledProcessDoesNotCreateCloudKitContainer() async {
        guard !LivePersistentSyncRetryExecutor.hasCloudKitContainerEntitlement else { return }
        await #expect(throws: CKError.self) { try await CloudKitPlatformAppearanceStore().fetch() }
    }
    #endif

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeBitmap(size: Int, draw: (CGContext) -> Void) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context)
        return try #require(context.makeImage())
    }

    private func makePNG(size: Int) throws -> Data {
        let image = try makeBitmap(size: size) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.5, blue: 0.7, alpha: 0.7))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor AppearanceCloudMock: PlatformAppearanceCloudStoring {
    private var snapshot: PlatformAppearanceSnapshot
    private var conflictSnapshot: PlatformAppearanceSnapshot?
    private var assetData: [String: Data]
    private var scope = PlatformAppearanceAssetCache.digest(for: Data("fixture.account".utf8))
    private let alwaysConflicts: Bool
    private var failsFirstUpload: Bool
    private var nextFetch: (@Sendable () async -> Void)?
    private var fetches = 0
    private var writes = 0
    private var downloaded: [String] = []
    private var version = Data([1])

    init(snapshot: PlatformAppearanceSnapshot, conflictSnapshot: PlatformAppearanceSnapshot? = nil,
         assetData: [String: Data] = [:], alwaysConflicts: Bool = false, failsFirstUpload: Bool = false) {
        self.alwaysConflicts = alwaysConflicts
        self.failsFirstUpload = failsFirstUpload
        self.snapshot = snapshot
        self.conflictSnapshot = conflictSnapshot
        self.assetData = assetData
    }

    func accountScope() -> String { scope }

    func switchAccount() {
        scope = PlatformAppearanceAssetCache.digest(for: Data("fixture.other".utf8))
        snapshot = .init()
    }

    func onNextFetch(_ action: @escaping @Sendable () async -> Void) { nextFetch = action }

    func fetch() async -> PlatformAppearanceCloudPayload {
        fetches += 1
        let reply = PlatformAppearanceCloudPayload(snapshot: snapshot, systemFields: version)
        let action = nextFetch
        nextFetch = nil
        await action?()
        return reply
    }

    func save(_ snapshot: PlatformAppearanceSnapshot, over systemFields: Data?) -> PlatformAppearanceCloudWriteResult {
        writes += 1
        if alwaysConflicts { return .conflict }
        if let conflictSnapshot {
            self.conflictSnapshot = nil
            self.snapshot = conflictSnapshot
            version = Data([2])
            return .conflict
        }
        guard systemFields == version else { return .conflict }
        self.snapshot = snapshot
        return .saved
    }

    func fetchAsset(_ id: String) -> Data? {
        downloaded.append(id)
        return assetData[id]
    }

    func saveAssetIfNeeded(_ data: Data, id: String) throws {
        if failsFirstUpload {
            failsFirstUpload = false
            throw CKError(.assetFileNotFound)
        }
        if assetData[id] == nil { assetData[id] = data }
    }

    func installAsset(_ data: Data, id: String) { assetData[id] = data }

    func state() -> (snapshot: PlatformAppearanceSnapshot, fetches: Int, writes: Int, downloaded: [String]) {
        (snapshot, fetches, writes, downloaded)
    }
}
