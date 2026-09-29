import Foundation
import Testing

@testable import AngelLiveCore

@Suite("Favorite refresh session", .serialized)
struct FavoriteRefreshSessionTests {
    @Test("failure diagnostics are structured, bounded, and omit raw error messages")
    func structuredFailureDiagnostic() {
        let room = sessionRoom(
            plugin: "ignored",
            id: "room\n\"42\"",
            userId: String(repeating: "u", count: 200)
        )
        let failure = FavoriteRefreshFailure(
            kind: .authenticationRequired,
            underlyingError: FavoriteRefreshUnderlyingError(
                domain: "NSURLErrorDomain\nInjected",
                code: -1009
            ),
            standardCode: .authRequired,
            receivedHTTPResponse: false,
            attempts: 2,
            elapsed: .milliseconds(125),
            pluginId: "fixture.plugin"
        )
        let classified = favoriteRefreshFailure(from: failure, pluginId: "fixture.plugin")
        #expect(classified == failure)
        let diagnostic = FavoriteRefreshFailureDiagnostic(room: room, failure: classified)
        let line = diagnostic.logLine(
            generationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            index: 1,
            total: 27
        )

        #expect(line.contains("index=1/27"))
        #expect(line.contains("pluginId=\"fixture.plugin\""))
        #expect(line.contains("roomFingerprint="))
        #expect(line.contains("kind=authenticationRequired"))
        #expect(line.contains("standardCode=AUTH_REQUIRED"))
        #expect(line.contains("underlyingDomain=\"NSURLErrorDomain\\nInjected\""))
        #expect(line.contains("underlyingCode=-1009"))
        #expect(line.contains("receivedHTTPResponse=false attempts=2"))
        #expect(diagnostic.elapsed == .milliseconds(125))
        #expect(line.contains("elapsed=\(failure.elapsed)"))
        #expect(!line.contains("收藏状态刷新失败"))
        #expect(!line.contains("room\n\"42\""))
        #expect(!line.contains(String(repeating: "u", count: 200)))
        #expect(line.count < 700)
    }

    @Test("fast result arrives before slow result and foreground budget does not cancel slow work")
    func incrementalResultAndForegroundBudget() async throws {
        let harness = FavoriteSessionOperationHarness([
            "fast": [.success("1")],
            "slow": [.gatedSuccess("2")]
        ])
        let session = makeSession(harness: harness, foregroundBudget: .milliseconds(30))
        let handle = await session.start(
            members: [sessionRoom(plugin: "a", id: "fast"), sessionRoom(plugin: "b", id: "slow")],
            trigger: .automatic
        )
        let collector = Task { await collectEvents(handle.events) }

        await handle.foregroundCompletion.value
        #expect(await harness.wasCancelled("slow") == false)
        #expect(await harness.callCount("fast") == 1)
        #expect(await harness.callCount("slow") == 1)

        await harness.release("slow")
        let events = await collector.value
        let updatedIDs = events.compactMap { event -> String? in
            guard case .roomUpdated(_, _, let room) = event else { return nil }
            return room.roomId
        }
        #expect(updatedIDs.first == "fast")
        #expect(updatedIDs == ["fast", "slow"])
        #expect(events.contains { if case .foregroundFinished = $0 { true } else { false } })
    }

    @Test("DNS failure opens only its plugin circuit and preserves the other plugin")
    func strongFailureIsPluginScoped() async {
        let harness = FavoriteSessionOperationHarness([
            "a1": [.failure(.dns)],
            "b1": [.success("1")],
            "b2": [.success("1")]
        ], defaultBehavior: .success("1"))
        let session = makeSession(
            harness: harness,
            foregroundBudget: .seconds(1),
            globalLimit: 2,
            pluginLimit: 1
        )
        let rooms = (1...5).map { sessionRoom(plugin: "a", id: "a\($0)") }
            + (1...2).map { sessionRoom(plugin: "b", id: "b\($0)") }
        let handle = await session.start(members: rooms, trigger: .automatic)
        let events = await collectEvents(handle.events)
        let summary = completedSummary(in: events)

        #expect(await harness.totalCalls(forPlugin: "a") == 1)
        #expect(await harness.totalCalls(forPlugin: "b") == 2)
        #expect(summary?.succeeded == 2)
        #expect(summary?.skipped == 4)
        #expect(events.contains {
            if case .pluginUnavailable(_, "a", 4) = $0 { return true }
            return false
        })
    }

    @Test("one connection loss is suspect and the second opens the circuit")
    func connectionLossNeedsTwoFailures() async {
        let harness = FavoriteSessionOperationHarness([
            "r1": [.failure(.connectionLost)],
            "r2": [.failure(.connectionLost)]
        ], defaultBehavior: .success("1"))
        let session = makeSession(harness: harness, pluginLimit: 1)
        let rooms = (1...5).map { sessionRoom(plugin: "a", id: "r\($0)") }
        let events = await collectEvents((await session.start(members: rooms, trigger: .automatic)).events)

        #expect(await harness.totalCalls == 2)
        #expect(completedSummary(in: events)?.skipped == 3)
    }

    @Test("timeout and business failures never open the plugin network circuit")
    func nonCircuitFailuresRunEveryRoom() async {
        let harness = FavoriteSessionOperationHarness([
            "r1": [.failure(.timeout)],
            "r2": [.failure(.authenticationRequired)],
            "r3": [.failure(.notFound)],
            "r4": [.failure(.upstream)]
        ])
        let session = makeSession(harness: harness, pluginLimit: 1)
        let rooms = (1...4).map { sessionRoom(plugin: "a", id: "r\($0)") }
        let events = await collectEvents((await session.start(members: rooms, trigger: .automatic)).events)

        #expect(await harness.totalCalls == 4)
        #expect(completedSummary(in: events)?.skipped == 0)
        #expect(!events.contains { if case .pluginUnavailable = $0 { true } else { false } })
    }

    @Test("unsatisfied path starts no requests and keeps every room stale")
    func offlinePathSkipsNetwork() async {
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .success("1"))
        let session = makeSession(harness: harness, path: .unsatisfied)
        let rooms = (1...6).map { sessionRoom(plugin: "a", id: "r\($0)") }
        let events = await collectEvents((await session.start(members: rooms, trigger: .automatic)).events)

        #expect(await harness.totalCalls == 0)
        #expect(completedSummary(in: events)?.skipped == 6)
        #expect(events.filter { if case .roomStale = $0 { true } else { false } }.count == 6)
    }

    @Test("URLSession device-offline evidence stops all remaining plugin queues")
    func runtimeOfflineFailureIsGlobalForGeneration() async {
        let harness = FavoriteSessionOperationHarness([
            "a1": [.failure(.deviceOffline)]
        ], defaultBehavior: .success("1"))
        let session = makeSession(harness: harness, globalLimit: 1, pluginLimit: 1)
        let rooms = [
            sessionRoom(plugin: "a", id: "a1"),
            sessionRoom(plugin: "a", id: "a2"),
            sessionRoom(plugin: "b", id: "b1"),
            sessionRoom(plugin: "b", id: "b2")
        ]
        let events = await collectEvents((await session.start(members: rooms, trigger: .automatic)).events)

        #expect(await harness.totalCalls == 1)
        #expect(completedSummary(in: events)?.skipped == 3)
    }

    @Test("global and per-plugin concurrency limits bound a 160-room refresh")
    func boundedConcurrency() async {
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .gatedSuccess("1"))
        let session = makeSession(
            harness: harness,
            foregroundBudget: .seconds(2),
            globalLimit: FavoriteRefreshRequestPolicy.default.maximumConcurrentRequests,
            pluginLimit: FavoriteRefreshRequestPolicy.default.maximumConcurrentRequestsPerPlugin
        )
        let rooms = (0..<160).map {
            sessionRoom(plugin: "p\($0 % 4)", id: "r\($0)")
        }
        let handle = await session.start(members: rooms, trigger: .automatic)
        let collector = Task { await collectEvents(handle.events) }
        await harness.waitUntilStarted(20)

        #expect(await harness.maximumActive == 20)
        #expect(await harness.maximumActivePerPlugin.values.allSatisfy { $0 == 5 })
        #expect(await harness.totalCalls == 20)

        await harness.releaseAll()
        _ = await collector.value
        #expect(await harness.totalCalls == 160)
        #expect(await harness.maximumActive <= 20)
        #expect(await harness.maximumActivePerPlugin.values.allSatisfy { $0 <= 5 })
    }

    @Test("large refresh resolves plugin metadata once and buckets progress events")
    func largeRefreshUsesOneMetadataSnapshot() async {
        let resolverCounter = FavoriteBatchResolverCounter()
        let session = FavoriteRefreshSession(
            operation: FavoriteRefreshOperation { room, _, _ in room },
            pathObserver: FixedFavoritePath(status: .satisfied),
            pluginResolver: FavoritePluginIDResolver(batch: { rooms in
                await resolverCounter.resolve(rooms)
            }),
            failureCacheInvalidator: .none,
            policy: FavoriteRefreshRequestPolicy(
                foregroundBudget: .seconds(2),
                totalBudget: .seconds(20),
                maximumConcurrentRequests: 8,
                maximumConcurrentRequestsPerPlugin: 3
            )
        )
        let rooms = (0..<160).map { sessionRoom(plugin: "ignored", id: "r\($0)") }
        let handle = await session.start(members: rooms, trigger: .automatic)
        let events = await collectEvents(handle.events)

        #expect(await resolverCounter.callCount == 1)
        #expect(handle.pluginTotals == ["snapshot-plugin": 160])
        #expect(handle.pluginDisplayNames == ["snapshot-plugin": "Snapshot Plugin"])
        #expect(handle.roomKeys.count == 160)
        #expect(handle.roomKeys.allSatisfy { $0.contains("_u_") })
        let progressCount = events.reduce(into: 0) { count, event in
            if case .pluginProgress = event { count += 1 }
        }
        #expect(progressCount == 21)
    }

    @Test("a plugin success disables the compatibility NOT_FOUND retry for later rooms")
    func successfulPluginDisablesNotFoundRetry() async {
        let harness = FavoriteSessionOperationHarness([
            "r1": [.success("1")],
            "r2": [.failure(.notFound)]
        ])
        let session = makeSession(harness: harness, pluginLimit: 1)
        let rooms = [sessionRoom(plugin: "a", id: "r1"), sessionRoom(plugin: "a", id: "r2")]
        _ = await collectEvents((await session.start(members: rooms, trigger: .automatic)).events)

        #expect(await harness.notFoundRetryFlags == [true, false])
    }

    @Test("manual refresh invalidates failure cache and replaces the old generation")
    func manualRefreshCreatesNewGeneration() async {
        let harness = FavoriteSessionOperationHarness([
            "r1": [.gatedSuccess("2"), .success("1")]
        ])
        let invalidation = InvalidationCounter()
        let session = makeSession(
            harness: harness,
            invalidator: FavoriteHTTPFailureCacheInvalidator { await invalidation.increment() }
        )
        let room = sessionRoom(plugin: "a", id: "r1")
        let first = await session.start(members: [room], trigger: .automatic)
        await harness.waitUntilStarted(1)
        let second = await session.start(members: [room], trigger: .manual)
        let events = await collectEvents(second.events)

        #expect(first.generationID != second.generationID)
        #expect(await invalidation.count == 1)
        #expect(events.contains {
            if case .roomUpdated(let generation, _, let updated) = $0 {
                return generation == second.generationID && updated.liveState == "1"
            }
            return false
        })
        #expect(await harness.wasCancelled("r1"))
    }

    @Test("AppFavoriteModel applies a fast patch while a slow room retains its old state")
    @MainActor
    func appModelIncrementalMergeAndFreshness() async throws {
        let harness = FavoriteSessionOperationHarness([
            "fast": [.success("1")],
            "slow": [.gatedSuccess("2")]
        ])
        let session = makeSession(harness: harness, foregroundBudget: .milliseconds(30))
        let model = AppFavoriteModel(refreshSession: session)
        model.favoriteICloudSyncEnabled = false
        let fast = sessionRoom(plugin: "a", id: "fast", state: "0")
        let slow = sessionRoom(plugin: "b", id: "slow", state: "1")
        model.roomList = [fast, slow]

        await model.refreshStatesAndApply(members: model.roomList, trigger: .manual)
        try await waitUntil {
            model.roomList.first(where: { $0.roomId == "fast" })?.liveState == "1"
                && model.roomList.first(where: { $0.roomId == "slow" })?.liveState == "1"
                && !model.isFavoriteStatusRefreshing
                && model.pendingPluginIds == ["b"]
        }
        #expect(model.roomList.first(where: { $0.roomId == "fast" })?.liveState == "1")
        #expect(model.roomList.first(where: { $0.roomId == "slow" })?.liveState == "1")
        #expect(!model.isFavoriteStatusRefreshing)
        #expect(model.pendingPluginIds == ["b"])

        await harness.release("slow")
        try await waitUntil {
            model.roomList.first(where: { $0.roomId == "slow" })?.liveState == "2"
                && model.pendingPluginIds.isEmpty
        }
        #expect(model.pendingPluginIds.isEmpty)
    }

    @Test("AppFavoriteModel coalesces concurrent automatic refresh callers")
    @MainActor
    func appModelCoalescesAutomaticRefresh() async throws {
        let harness = FavoriteSessionOperationHarness([
            "r1": [.gatedSuccess("1")]
        ])
        let session = makeSession(harness: harness, foregroundBudget: .seconds(2))
        let model = AppFavoriteModel(refreshSession: session)
        let room = sessionRoom(plugin: "a", id: "r1", state: "0")
        model.roomList = [room]

        let first = Task {
            await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        }
        await harness.waitUntilStarted(1)
        let generationID = model.currentFavoriteGenerationID
        let second = Task {
            await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        }

        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.callCount("r1") == 1)
        #expect(model.currentFavoriteGenerationID == generationID)

        await harness.release("r1")
        await first.value
        await second.value
        #expect(await harness.callCount("r1") == 1)
    }

    @Test("automatic callers share a refresh even while plugin resolution is suspended", arguments: [false, true])
    @MainActor
    func appModelCoalescesDuringStartup(cancelFirstCaller: Bool) async throws {
        let gate = FavoriteStartupResolverGate()
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .success("1"))
        let session = makeSession(harness: harness, resolver: FavoritePluginIDResolver(batch: { rooms in
            await gate.resolve(rooms)
        }))
        let model = AppFavoriteModel(refreshSession: session)
        let room = sessionRoom(plugin: "source-a", id: "r1")
        model.roomList = [room]

        let first = Task {
            await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        }
        await gate.waitUntilEntered()
        #expect(model.currentFavoriteGenerationID == nil)
        if cancelFirstCaller { first.cancel() }

        let (entered, signal) = AsyncStream.makeStream(of: Void.self)
        let second = Task { @MainActor in
            signal.yield(())
            signal.finish()
            await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        }
        for await _ in entered { break }
        await gate.release()
        await first.value
        await second.value

        #expect(await gate.calls == 1)
        #expect(await harness.callCount("r1") == 1)
        try await waitUntil { model.roomList.first?.liveState == "1" }
    }

    @Test("manual refresh during startup replaces the generation without waiting for old network work")
    @MainActor
    func appModelManualRefreshDuringStartup() async throws {
        let gate = FavoriteStartupResolverGate()
        let harness = FavoriteSessionOperationHarness([
            "old": [.gatedSuccess("1")],
            "new": [.success("2")]
        ])
        let session = makeSession(harness: harness, foregroundBudget: .seconds(60), resolver: FavoritePluginIDResolver(batch: { rooms in
            await gate.resolve(rooms)
        }))
        let model = AppFavoriteModel(refreshSession: session)
        let oldRoom = sessionRoom(plugin: "source-a", id: "old")
        let newRoom = sessionRoom(plugin: "source-a", id: "new")
        model.roomList = [oldRoom, newRoom]

        let automatic = Task {
            await model.refreshStatesAndApply(members: [oldRoom], trigger: .automatic)
        }
        await gate.waitUntilEntered()
        let (entered, signal) = AsyncStream.makeStream(of: Void.self)
        let manual = Task { @MainActor in
            signal.yield(())
            signal.finish()
            await model.refreshStatesAndApply(members: [newRoom], trigger: .manual)
        }
        for await _ in entered { break }
        await gate.release()

        // The old operation remains gated. The replacement must complete anyway.
        try await waitUntil { model.roomList.first(where: { $0.roomId == "new" })?.liveState == "2" }
        await session.cancel()
        await harness.release("old")
        await automatic.value
        await manual.value
        #expect(await gate.calls == 2)
        #expect(await harness.callCount("new") == 1)
        #expect(model.roomList.first(where: { $0.roomId == "old" })?.liveState == "0")
    }

    @Test("public refresh entry points merge a burst before loading members", arguments: [false, true])
    @MainActor
    func publicRefreshBurst(manual: Bool) async throws {
        let gate = FavoriteStartupResolverGate()
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .success("1"))
        let session = makeSession(harness: harness, resolver: FavoritePluginIDResolver(batch: { await gate.resolve($0) }))
        let model = AppFavoriteModel(refreshSession: session)
        let originalCloudSetting = model.favoriteICloudSyncEnabled
        model.favoriteICloudSyncEnabled = false
        defer { model.favoriteICloudSyncEnabled = originalCloudSetting }
        model.roomList = [sessionRoom(plugin: "source-a", id: "r1")]
        let (entered, signal) = AsyncStream.makeStream(of: Void.self)
        let callers = (0..<24).map { _ in
            Task { @MainActor in
                signal.yield(())
                if manual {
                    await model.pullToRefresh()
                } else {
                    await model.syncWithActor()
                }
            }
        }
        var entries = 0
        for await _ in entered {
            entries += 1
            if entries == callers.count { break }
        }
        signal.finish()
        await gate.waitUntilEntered()
        await gate.release()
        for caller in callers { await caller.value }
        #expect(await gate.calls == 1)
        #expect(await harness.callCount("r1") == 1)
    }

    @Test("automatic refresh stays shared after foreground finishes and after completion")
    @MainActor
    func automaticRefreshForegroundAndCompletion() async throws {
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .gatedSuccess("1"))
        let session = makeSession(harness: harness, foregroundBudget: .milliseconds(10))
        let model = AppFavoriteModel(refreshSession: session)
        let room = sessionRoom(plugin: "source-a", id: "r1")
        model.roomList = [room]
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        await harness.waitUntilStarted(1)
        for _ in 0..<24 {
            await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        }
        #expect(await harness.callCount("r1") == 1)
        #expect(await harness.wasCancelled("r1") == false)
        await harness.release("r1")
        try await waitUntil { model.lastFavoriteRefreshSummary != nil && !model.hasActiveFavoriteRefresh }
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        #expect(await harness.callCount("r1") == 1)
        #expect(!model.shouldSync())
    }

    @Test("freshness permits manual refresh, expiry and changed membership")
    @MainActor
    func automaticRefreshFreshness() async throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .success("1"))
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness), refreshNow: { now })
        let room = sessionRoom(plugin: "source-a", id: "r1")
        model.roomList = [room]
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }
        let firstGeneration = model.currentFavoriteGenerationID
        now.addTimeInterval(60)
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        #expect(model.currentFavoriteGenerationID == firstGeneration)
        #expect(await harness.callCount("r1") == 1)
        await model.refreshStatesAndApply(members: [room], trigger: .manual)
        try await waitUntil { model.lastFavoriteRefreshSummary?.generationID != firstGeneration && !model.hasActiveFavoriteRefresh }
        #expect(await harness.callCount("r1") == 2)
        now.addTimeInterval(61)
        #expect(model.shouldSync())
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        #expect(await harness.callCount("r1") == 3)
        let added = sessionRoom(plugin: "source-a", id: "r2")
        model.roomList = [room, added]
        #expect(model.shouldSync())
        await model.refreshStatesAndApply(members: [room, added], trigger: .automatic)
        #expect(await harness.callCount("r2") == 1)
    }

    @Test("refresh identity collisions preserve distinct favorite members")
    @MainActor
    func refreshIdentityCollisionPreservesMembership() async throws {
        let harness = FavoriteSessionOperationHarness([
            "room-1": [.replacement(userId: "0", roomId: "shared-placeholder", state: "1")],
            "room-2": [.replacement(userId: "0", roomId: "shared-placeholder", state: "2")]
        ])
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness))
        model.favoriteICloudSyncEnabled = false
        let first = sessionRoom(plugin: "fixture.plugin", id: "room-1", userId: "user-1")
        let second = sessionRoom(plugin: "fixture.plugin", id: "room-2", userId: "user-2")
        model.roomList = [first, second]

        await model.refreshStatesAndApply(members: model.roomList, trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }

        #expect(model.roomList.count == 2)
        #expect(Set(model.roomList.map(\.roomId)) == ["room-1", "room-2"])
        #expect(Set(model.roomList.compactMap(\.liveState)) == ["1", "2"])
        #expect(!model.shouldSync())
    }

    @Test("valid user identity collisions preserve both favorite identities")
    @MainActor
    func validUserIdentityCollisionPreservesMembership() async throws {
        let harness = FavoriteSessionOperationHarness([
            "room-1": [.replacement(userId: "user-2", roomId: "room-new", state: "1")],
            "room-2": [.replacement(userId: "user-new", roomId: "room-1", state: "2")]
        ])
        let resolver = FavoritePluginIDResolver(batch: { rooms in
            rooms.map { _ in FavoriteResolvedPlugin(pluginId: "fixture.plugin", identityKey: .userId) }
        })
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness, resolver: resolver))
        model.favoriteICloudSyncEnabled = false
        model.roomList = [
            sessionRoom(plugin: "fixture.plugin", id: "room-1", userId: "user-1"),
            sessionRoom(plugin: "fixture.plugin", id: "room-2", userId: "user-2")
        ]

        await model.refreshStatesAndApply(members: model.roomList, trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }

        #expect(model.roomList.map(\.userId) == ["user-1", "user-2"])
        #expect(model.roomList.map(\.roomId) == ["room-1", "room-2"])
        #expect(model.roomList.compactMap(\.liveState) == ["1", "2"])
    }

    @Test("accepted favorite identity migration remains fresh for automatic callers")
    @MainActor
    func acceptedIdentityMigrationUpdatesRefreshBaseline() async throws {
        let harness = FavoriteSessionOperationHarness([
            "room-1": [.replacement(userId: "user-stable", roomId: "room-2", state: "1")]
        ])
        let resolver = FavoritePluginIDResolver(batch: { rooms in
            rooms.map { _ in
                FavoriteResolvedPlugin(
                    pluginId: "fixture.plugin",
                    identityKey: .userId
                )
            }
        })
        let model = AppFavoriteModel(
            refreshSession: makeSession(harness: harness, resolver: resolver)
        )
        model.favoriteICloudSyncEnabled = false
        let original = sessionRoom(plugin: "fixture.plugin", id: "room-1", userId: "0")
        model.roomList = [original]

        await model.refreshStatesAndApply(members: model.roomList, trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }

        #expect(model.roomList.first?.userId == "user-stable")
        #expect(model.roomList.first?.roomId == "room-2")
        #expect(!model.shouldSync())
        await model.refreshStatesAndApply(members: model.roomList, trigger: .automatic)
        #expect(await harness.totalCalls == 1)

        let refreshed = try #require(model.roomList.first)
        model.roomList = []
        #expect(model.shouldSync())
        model.roomList = [refreshed]
        #expect(!model.shouldSync())
        model.roomList.append(sessionRoom(plugin: "fixture.plugin", id: "room-3", userId: "user-3"))
        #expect(model.shouldSync())
    }

    @Test("room identity keeps its stable key while accepting a valid user id")
    @MainActor
    func roomIdentityAcceptsUserIDCompletion() async throws {
        let harness = FavoriteSessionOperationHarness([
            "room-1": [.replacement(userId: "user-completed", roomId: "unexpected-room", state: "1")]
        ])
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness))
        model.favoriteICloudSyncEnabled = false
        model.roomList = [sessionRoom(plugin: "fixture.plugin", id: "room-1", userId: "0")]

        await model.refreshStatesAndApply(members: model.roomList, trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }

        #expect(model.roomList.first?.roomId == "room-1")
        #expect(model.roomList.first?.userId == "user-completed")
        #expect(model.roomList.first?.liveState == "1")
        #expect(!model.shouldSync())
    }

    @Test("preserve room info behavior only applies refreshed live state")
    @MainActor
    func preserveRoomInfoBehavior() async throws {
        let harness = FavoriteSessionOperationHarness([
            "room-1": [.replacement(userId: "user-new", roomId: "room-new", state: "1")]
        ])
        let resolver = FavoritePluginIDResolver(batch: { rooms in
            rooms.map { _ in
                FavoriteResolvedPlugin(
                    pluginId: "fixture.plugin",
                    identityKey: .userId,
                    preserveFavoriteRoomInfoOnRefresh: true
                )
            }
        })
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness, resolver: resolver))
        model.favoriteICloudSyncEnabled = false
        model.roomList = [sessionRoom(plugin: "fixture.plugin", id: "room-1", userId: "user-old")]

        await model.refreshStatesAndApply(members: model.roomList, trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }

        #expect(model.roomList.first?.roomId == "room-1")
        #expect(model.roomList.first?.userId == "user-old")
        #expect(model.roomList.first?.liveState == "1")
    }

    @Test("external membership changes during rekey remain refresh-invalidating", arguments: [false, true])
    @MainActor
    func externalMembershipDuringRekey(removeMember: Bool) async throws {
        let harness = FavoriteSessionOperationHarness([
            "room-1": [.gatedReplacement(userId: "user-stable", roomId: "room-2", state: "1")]
        ])
        let resolver = FavoritePluginIDResolver(batch: { rooms in
            rooms.map { _ in FavoriteResolvedPlugin(pluginId: "fixture.plugin", identityKey: .userId) }
        })
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness, resolver: resolver))
        model.favoriteICloudSyncEnabled = false
        let original = sessionRoom(plugin: "fixture.plugin", id: "room-1", userId: "0")
        model.roomList = [original]

        let refresh = Task { @MainActor in
            await model.refreshStatesAndApply(members: [original], trigger: .automatic)
        }
        await harness.waitUntilStarted(1)
        if removeMember {
            model.roomList = []
        } else {
            model.roomList.append(
                sessionRoom(plugin: "fixture.plugin", id: "room-3", userId: "user-3"))
        }
        await harness.release("room-1")
        await refresh.value
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }

        #expect(model.shouldSync())
        #expect(model.roomList.count == (removeMember ? 0 : 2))
    }

    @Test("identical catalog notifications are ignored and an actual plugin update refreshes")
    @MainActor
    func automaticRefreshCatalogChanges() async throws {
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .success("1"))
        let model = AppFavoriteModel(refreshSession: makeSession(harness: harness))
        let room = sessionRoom(plugin: "source-a", id: "r1")
        model.roomList = [room]
        func catalog(_ version: String) -> [String: SandboxPluginMetadata] {
            ["source-a": SandboxPluginMetadata(pluginId: "source-a", version: version, displayName: nil, liveTypes: ["fixture-source"])]
        }
        #expect(!model.updateFavoriteRefreshCatalog(catalog("1.0.0")))
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        try await waitUntil { model.lastFavoriteRefreshSummary != nil }
        #expect(!model.updateFavoriteRefreshCatalog(catalog("1.0.0")))
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        #expect(await harness.callCount("r1") == 1)
        #expect(model.updateFavoriteRefreshCatalog(catalog("1.1.0")))
        #expect(model.shouldSync())
        await model.refreshStatesAndApply(members: [room], trigger: .automatic)
        #expect(await harness.callCount("r1") == 2)
    }

    @Test("terminating the sole event consumer cancels session-owned work")
    func consumerTerminationCancelsWork() async throws {
        let harness = FavoriteSessionOperationHarness(defaultBehavior: .gatedSuccess("1"))
        let session = makeSession(harness: harness, foregroundBudget: .seconds(2))
        let handle = await session.start(
            members: [sessionRoom(plugin: "a", id: "r1")],
            trigger: .automatic
        )
        let consumer = Task {
            for await _ in handle.events {
                try Task.checkCancellation()
            }
        }
        await harness.waitUntilStarted(1)
        consumer.cancel()
        _ = await consumer.result

        for _ in 0..<100 where !(await harness.wasCancelled("r1")) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await harness.wasCancelled("r1"))
    }
}

@Suite("Plugin HTTP single-flight")
struct PluginHTTPFlightCoordinatorTests {
    @Test("two waiters share one real request and success cache")
    func joinsAndCachesSuccess() async throws {
        let coordinator = PluginHTTPFlightCoordinator()
        let operation = SharedHTTPTestOperation()
        let key = flightKey(revision: "r1")
        let first = Task {
            try await coordinator.execute(key: key, successTTL: 10, failureTTL: 0) {
                try await operation.runGated()
            }
        }
        await operation.waitUntilStarted(1)
        let second = Task {
            try await coordinator.execute(key: key, successTTL: 10, failureTTL: 0) {
                try await operation.runGated()
            }
        }
        await operation.release()
        _ = try await first.value
        _ = try await second.value
        _ = try await coordinator.execute(key: key, successTTL: 10, failureTTL: 0) {
            await operation.runImmediate()
        }

        #expect(await operation.calls == 1)
        let metrics = await coordinator.metrics()
        #expect(metrics.realRequests == 1)
        #expect(metrics.joinedFlights == 1)
        #expect(metrics.successCacheHits == 1)
    }

    @Test("failure cache is short-lived state and explicit invalidation removes it")
    func failureCacheInvalidation() async throws {
        let coordinator = PluginHTTPFlightCoordinator()
        let operation = SharedHTTPTestOperation()
        let key = flightKey(revision: "r1")
        await #expect(throws: PluginHTTPFlightFailure.self) {
            try await coordinator.execute(key: key, successTTL: 0, failureTTL: 10) {
                try await operation.runFailure()
            }
        }
        await #expect(throws: PluginHTTPFlightFailure.self) {
            try await coordinator.execute(key: key, successTTL: 0, failureTTL: 10) {
                await operation.runImmediate()
            }
        }
        #expect(await operation.calls == 1)

        await coordinator.invalidateFailures()
        _ = try await coordinator.execute(key: key, successTTL: 0, failureTTL: 10) {
            await operation.runImmediate()
        }
        #expect(await operation.calls == 2)
    }

    @Test("session revision is part of the cache key")
    func sessionRevisionSeparatesCache() async throws {
        let coordinator = PluginHTTPFlightCoordinator()
        let operation = SharedHTTPTestOperation()
        _ = try await coordinator.execute(key: flightKey(revision: "before"), successTTL: 10, failureTTL: 0) {
            await operation.runImmediate()
        }
        _ = try await coordinator.execute(key: flightKey(revision: "after"), successTTL: 10, failureTTL: 0) {
            await operation.runImmediate()
        }
        #expect(await operation.calls == 2)
    }

    @Test("cancelling one waiter does not cancel the shared network task")
    func waiterCancellationDoesNotCancelFlight() async throws {
        let coordinator = PluginHTTPFlightCoordinator()
        let operation = SharedHTTPTestOperation()
        let key = flightKey(revision: "r1")
        let first = Task {
            try await coordinator.execute(key: key, successTTL: 0, failureTTL: 0) {
                try await operation.runGated()
            }
        }
        await operation.waitUntilStarted(1)
        let second = Task {
            try await coordinator.execute(key: key, successTTL: 0, failureTTL: 0) {
                try await operation.runGated()
            }
        }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await operation.release()
        _ = try await second.value

        #expect(await operation.calls == 1)
        #expect(await operation.cancelled == false)
    }
}

private enum SessionFailure: Sendable {
    case deviceOffline
    case dns
    case connectionLost
    case timeout
    case authenticationRequired
    case notFound
    case upstream

    func error(pluginId: String) -> FavoriteRefreshFailure {
        let source: any Error
        switch self {
        case .deviceOffline: source = URLError(.notConnectedToInternet)
        case .dns: source = URLError(.cannotFindHost)
        case .connectionLost: source = URLError(.networkConnectionLost)
        case .timeout: source = URLError(.timedOut)
        case .authenticationRequired:
            source = LiveParsePluginError.standardized(.init(code: .authRequired, message: "auth"))
        case .notFound:
            source = LiveParsePluginError.standardized(.init(code: .notFound, message: "not found"))
        case .upstream:
            source = LiveParsePluginError.standardized(.init(code: .upstream, message: "upstream"))
        }
        return favoriteRefreshFailure(from: source, pluginId: pluginId)
    }
}

private actor FavoriteSessionOperationHarness {
    enum Behavior: Sendable {
        case success(String)
        case gatedSuccess(String)
        case replacement(userId: String, roomId: String, state: String)
        case gatedReplacement(userId: String, roomId: String, state: String)
        case failure(SessionFailure)
    }

    private var behaviors: [String: [Behavior]]
    private let defaultBehavior: Behavior
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var cancelledIDs: Set<String> = []
    private var releasedIDs: Set<String> = []
    private var releaseFutureWaiters = false
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callsByRoom: [String: Int] = [:]
    private(set) var active = 0
    private(set) var maximumActive = 0
    private(set) var activePerPlugin: [String: Int] = [:]
    private(set) var maximumActivePerPlugin: [String: Int] = [:]
    private(set) var notFoundRetryFlags: [Bool] = []

    init(
        _ behaviors: [String: [Behavior]] = [:],
        defaultBehavior: Behavior = .success("1")
    ) {
        self.behaviors = behaviors
        self.defaultBehavior = defaultBehavior
    }

    var totalCalls: Int { callsByRoom.values.reduce(0, +) }

    func callCount(_ roomId: String) -> Int { callsByRoom[roomId, default: 0] }

    func totalCalls(forPlugin pluginId: String) -> Int {
        callsByRoom.filter { $0.key.hasPrefix(pluginId) }.values.reduce(0, +)
    }

    func wasCancelled(_ roomId: String) -> Bool { cancelledIDs.contains(roomId) }

    func run(room: LiveModel, pluginId: String, allowNotFoundRetry: Bool) async throws -> LiveModel {
        callsByRoom[room.roomId, default: 0] += 1
        notFoundRetryFlags.append(allowNotFoundRetry)
        active += 1
        maximumActive = max(maximumActive, active)
        activePerPlugin[pluginId, default: 0] += 1
        maximumActivePerPlugin[pluginId] = max(
            maximumActivePerPlugin[pluginId, default: 0],
            activePerPlugin[pluginId, default: 0]
        )
        resumeStartWaitersIfNeeded()
        defer {
            active -= 1
            activePerPlugin[pluginId, default: 1] -= 1
        }

        let behavior: Behavior
        if var queue = behaviors[room.roomId], !queue.isEmpty {
            behavior = queue.removeFirst()
            behaviors[room.roomId] = queue
        } else {
            behavior = defaultBehavior
        }

        switch behavior {
        case .success(let state):
            var result = room
            result.liveState = state
            return result
        case .gatedSuccess(let state):
            try await wait(room.roomId)
            var result = room
            result.liveState = state
            return result
        case .replacement(let userId, let roomId, let state):
            return LiveModel(
                userName: room.userName,
                roomTitle: room.roomTitle,
                roomCover: room.roomCover,
                userHeadImg: room.userHeadImg,
                liveType: room.liveType,
                liveState: state,
                userId: userId,
                roomId: roomId,
                liveWatchedCount: room.liveWatchedCount,
                identityUpdatedAt: room.identityUpdatedAt
            )
        case .gatedReplacement(let userId, let roomId, let state):
            try await wait(room.roomId)
            return LiveModel(
                userName: room.userName,
                roomTitle: room.roomTitle,
                roomCover: room.roomCover,
                userHeadImg: room.userHeadImg,
                liveType: room.liveType,
                liveState: state,
                userId: userId,
                roomId: roomId,
                liveWatchedCount: room.liveWatchedCount,
                identityUpdatedAt: room.identityUpdatedAt
            )
        case .failure(let failure):
            throw failure.error(pluginId: pluginId)
        }
    }

    func waitUntilStarted(_ count: Int) async {
        guard totalCalls < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func release(_ roomId: String) {
        releasedIDs.insert(roomId)
        waiters.removeValue(forKey: roomId)?.resume()
    }

    func releaseAll() {
        releaseFutureWaiters = true
        let continuations = Array(waiters.values)
        releasedIDs.formUnion(waiters.keys)
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func wait(_ roomId: String) async throws {
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if releaseFutureWaiters || releasedIDs.contains(roomId) || cancelledIDs.contains(roomId) {
                    continuation.resume()
                } else {
                    waiters[roomId] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(roomId) }
        }
        try Task.checkCancellation()
    }

    private func cancel(_ roomId: String) {
        cancelledIDs.insert(roomId)
        waiters.removeValue(forKey: roomId)?.resume()
    }

    private func resumeStartWaitersIfNeeded() {
        var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in startWaiters {
            if totalCalls >= waiter.0 {
                waiter.1.resume()
            } else {
                remaining.append(waiter)
            }
        }
        startWaiters = remaining
    }
}

private struct FixedFavoritePath: FavoriteNetworkPathObserving {
    let status: FavoriteNetworkPathStatus
    func currentStatus() async -> FavoriteNetworkPathStatus { status }
}

private actor InvalidationCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor FavoriteBatchResolverCounter {
    private(set) var callCount = 0

    func resolve(_ rooms: [LiveModel]) -> [FavoriteResolvedPlugin] {
        callCount += 1
        return rooms.map { _ in
            FavoriteResolvedPlugin(
                pluginId: "snapshot-plugin",
                displayName: "Snapshot Plugin",
                identityKey: .userId,
                preserveFavoriteRoomInfoOnRefresh: true
            )
        }
    }
}

private actor FavoriteStartupResolverGate {
    private(set) var calls = 0
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    func resolve(_ rooms: [LiveModel]) async -> [FavoriteResolvedPlugin] {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
                enteredContinuation?.resume()
                enteredContinuation = nil
            }
        }
        return rooms.map { FavoriteResolvedPlugin(pluginId: $0.userName) }
    }

    func waitUntilEntered() async {
        if calls > 0 { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func makeSession(
    harness: FavoriteSessionOperationHarness,
    foregroundBudget: Duration = .seconds(1),
    globalLimit: Int = 8,
    pluginLimit: Int = 3,
    path: FavoriteNetworkPathStatus = .satisfied,
    invalidator: FavoriteHTTPFailureCacheInvalidator = .none,
    resolver: FavoritePluginIDResolver = FavoritePluginIDResolver { $0.userName }
) -> FavoriteRefreshSession {
    FavoriteRefreshSession(
        operation: FavoriteRefreshOperation { room, pluginId, allowRetry in
            try await harness.run(
                room: room,
                pluginId: pluginId,
                allowNotFoundRetry: allowRetry
            )
        },
        pathObserver: FixedFavoritePath(status: path),
        pluginResolver: resolver,
        failureCacheInvalidator: invalidator,
        policy: FavoriteRefreshRequestPolicy(
            foregroundBudget: foregroundBudget,
            totalBudget: .seconds(20),
            maximumConcurrentRequests: globalLimit,
            maximumConcurrentRequestsPerPlugin: pluginLimit
        )
    )
}

private func sessionRoom(
    plugin: String,
    id: String,
    state: String? = "0",
    userId: String? = nil
) -> LiveModel {
    LiveModel(
        userName: plugin,
        roomTitle: id,
        roomCover: "cover",
        userHeadImg: "avatar",
        liveType: LiveType(rawValue: "fixture-source")!,
        liveState: state,
        userId: userId ?? "user-\(id)",
        roomId: id,
        liveWatchedCount: nil
    )
}

private func collectEvents(_ stream: AsyncStream<FavoriteRefreshEvent>) async -> [FavoriteRefreshEvent] {
    var events: [FavoriteRefreshEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private func completedSummary(in events: [FavoriteRefreshEvent]) -> FavoriteRefreshSummary? {
    events.compactMap { event in
        guard case .completed(_, let summary) = event else { return nil }
        return summary
    }.last
}

@MainActor
private func waitUntil(
    attempts: Int = 100,
    _ predicate: () -> Bool
) async throws {
    for _ in 0..<attempts {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition did not become true")
}

private actor SharedHTTPTestOperation {
    private var waiter: CheckedContinuation<Void, Never>?
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var calls = 0
    private(set) var cancelled = false

    func runGated() async throws -> PluginHTTPFlightSnapshot {
        calls += 1
        resumeStartWaiters()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { await self.markCancelled() }
        }
        try Task.checkCancellation()
        return httpSnapshot()
    }

    func runImmediate() -> PluginHTTPFlightSnapshot {
        calls += 1
        return httpSnapshot()
    }

    func runFailure() throws -> PluginHTTPFlightSnapshot {
        calls += 1
        throw PluginHTTPFlightFailure(
            domain: NSURLErrorDomain,
            code: URLError.Code.cannotFindHost.rawValue,
            receivedHTTPResponse: false,
            message: "dns"
        )
    }

    func waitUntilStarted(_ target: Int) async {
        guard calls < target else { return }
        await withCheckedContinuation { startWaiters.append((target, $0)) }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }

    private func markCancelled() {
        cancelled = true
        waiter?.resume()
        waiter = nil
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { calls >= $0.0 }
        startWaiters.removeAll { calls >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private func flightKey(revision: String) -> PluginHTTPFlightKey {
    PluginHTTPFlightKey(
        pluginId: "plugin",
        sessionRevision: revision,
        method: "GET",
        singleFlightKey: "token"
    )
}

private func httpSnapshot() -> PluginHTTPFlightSnapshot {
    PluginHTTPFlightSnapshot(
        data: Data("ok".utf8),
        statusCode: 200,
        headers: [:],
        responseURL: "https://example.invalid/token"
    )
}
