import Foundation
import os.lock
import Testing

@testable import AngelLiveCore

@Suite("Host WebSocket runtime ownership", .serialized)
struct HostWebSocketOwnershipTests {
    @Test("owners cannot access each other's sessions and invalidation is isolated")
    func ownerIsolation() throws {
        let ownerA = HostWebSocketRegistry.registerOwner()
        let ownerB = HostWebSocketRegistry.registerOwner()
        let request = URLRequest(url: try #require(URL(string: "ws://127.0.0.1/socket")))
        let sessionA = HostWebSocketSession(id: "session-a", owner: ownerA, request: request) { _, _ in }
        let sessionB = HostWebSocketSession(id: "session-b", owner: ownerB, request: request) { _, _ in }
        #expect(HostWebSocketRegistry.add(sessionA, owner: ownerA))
        #expect(HostWebSocketRegistry.add(sessionB, owner: ownerB))
        #expect(HostWebSocketRegistry.get(sessionA.id, owner: ownerB) == nil)
        #expect(HostWebSocketRegistry.remove(sessionB.id, owner: ownerA) == nil)

        let retired = HostWebSocketRegistry.invalidate(owner: ownerA)
        retired.forEach { $0.tearDown() }
        #expect(retired.map(\.id) == [sessionA.id])
        #expect(!HostWebSocketRegistry.isActive(owner: ownerA))
        #expect(HostWebSocketRegistry.sessionCount(owner: ownerA) == 0)
        #expect(HostWebSocketRegistry.get(sessionB.id, owner: ownerB) === sessionB)

        let rejected = HostWebSocketSession(id: "late-a", owner: ownerA, request: request) { _, _ in }
        #expect(!HostWebSocketRegistry.add(rejected, owner: ownerA))
        rejected.tearDown()
        HostWebSocketRegistry.invalidate(owner: ownerB).forEach { $0.tearDown() }
    }

    @Test("natural terminal events unregister once and release their session")
    func terminalIsOneShot() async throws {
        let owner = HostWebSocketRegistry.registerOwner()
        let request = URLRequest(url: try #require(URL(string: "ws://127.0.0.1/socket")))
        let events = LockedWebSocketEvents()
        weak var weakSession: HostWebSocketSession?
        var session: HostWebSocketSession? = HostWebSocketSession(
            id: "terminal-session",
            owner: owner,
            request: request
        ) { json, terminal in events.append(json: json, terminal: terminal) }
        weakSession = session
        #expect(HostWebSocketRegistry.add(try #require(session), owner: owner))

        session?.receive(.cancelled)
        session?.receive(.peerClosed)
        await session?.drainForTesting()

        #expect(HostWebSocketRegistry.sessionCount(owner: owner) == 0)
        #expect(events.terminalCount == 1)
        session = nil
        #expect(weakSession == nil)
        _ = HostWebSocketRegistry.invalidate(owner: owner)
    }

    @Test("an event queued before owner invalidation is not delivered")
    func queuedEventIsDroppedAfterInvalidation() async throws {
        let owner = HostWebSocketRegistry.registerOwner()
        let request = URLRequest(url: try #require(URL(string: "ws://127.0.0.1/socket")))
        let events = LockedWebSocketEvents()
        let queue = DispatchQueue(label: "fixture.host-ws.gated")
        queue.suspend()
        let session = HostWebSocketSession(
            id: "queued-session",
            owner: owner,
            request: request,
            queue: queue
        ) { json, terminal in events.append(json: json, terminal: terminal) }
        #expect(HostWebSocketRegistry.add(session, owner: owner))
        session.receive(.text("late"))

        let retired = HostWebSocketRegistry.invalidate(owner: owner)
        queue.resume()
        await session.drainForTesting()
        retired.forEach { $0.tearDown() }

        #expect(events.count == 0)
        #expect(HostWebSocketRegistry.sessionCount(owner: owner) == 0)
    }

    @Test("runtime deinit invalidates its WebSocket owner")
    func runtimeReleaseInvalidatesOwner() {
        weak var weakRuntime: JSRuntime?
        var owner: UUID?
        do {
            let runtime = JSRuntime(pluginId: "fixture.plugin")
            weakRuntime = runtime
            owner = runtime.hostWebSocketOwner
            #expect(owner.map { HostWebSocketRegistry.isActive(owner: $0) } == true)
        }
        #expect(weakRuntime == nil)
        #expect(owner.map { HostWebSocketRegistry.isActive(owner: $0) } == false)
    }
}

private final class LockedWebSocketEvents: Sendable {
    private let values = OSAllocatedUnfairLock<[(json: String, terminal: Bool)]>(initialState: [])

    var count: Int { values.withLock { $0.count } }
    var terminalCount: Int { values.withLock { $0.count(where: \.terminal) } }

    func append(json: String, terminal: Bool) {
        values.withLock { $0.append((json, terminal)) }
    }
}
