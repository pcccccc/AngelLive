import Foundation
import Testing
@testable import AngelLiveDependencies

@Suite("Live subtitle reservations", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct LiveSubtitleReservationsTests {
    @available(macOS 26, *)
    @Test("Concurrent users share one reservation until the final release")
    func concurrentUsersShareReservation() async throws {
        let system = TestReservationSystem()
        let reservations = LiveSubtitleReservations(system: system)
        let locale = Locale(identifier: "en-US")

        async let first = reservations.acquire(locale: locale)
        async let second = reservations.acquire(locale: locale)
        let (firstLease, secondLease) = try await (first, second)

        #expect(system.reserveCallCount == 1)
        await reservations.release(firstLease)
        #expect(system.releaseCallCount == 0)
        await reservations.release(secondLease)
        #expect(system.releaseCallCount == 1)
        #expect(system.reservedLocaleKeys.isEmpty)
    }

    @available(macOS 26, *)
    @Test("A preexisting system reservation is borrowed and never released")
    func preexistingReservationIsBorrowed() async throws {
        let locale = Locale(identifier: "en-US")
        let system = TestReservationSystem(preexisting: [locale])
        let reservations = LiveSubtitleReservations(system: system)

        let lease = try await reservations.acquire(locale: locale)
        await reservations.release(lease)

        #expect(system.reserveCallCount == 1)
        #expect(system.releaseCallCount == 0)
        #expect(system.reservedLocaleKeys == [TestReservationSystem.key(locale)])
    }

    @available(macOS 26, *)
    @Test("A short query lease cannot release an active recognition lease")
    func queryCannotReleaseRun() async throws {
        let system = TestReservationSystem()
        let reservations = LiveSubtitleReservations(system: system)
        let locale = Locale(identifier: "en-US")

        let runLease = try await reservations.acquire(locale: locale)
        let queryLease = try await reservations.acquire(locale: locale)
        await reservations.release(queryLease)

        #expect(system.releaseCallCount == 0)
        #expect(system.reservedLocaleKeys == [TestReservationSystem.key(locale)])

        await reservations.release(runLease)
        #expect(system.releaseCallCount == 1)
        #expect(system.reservedLocaleKeys.isEmpty)
    }

    @available(macOS 26, *)
    @Test("Thrown and cancelled leased operations both release their reservation")
    func failureAndCancellationRelease() async throws {
        let failedSystem = TestReservationSystem()
        let failedReservations = LiveSubtitleReservations(system: failedSystem)
        let locale = Locale(identifier: "en-US")

        await #expect(throws: TestFailure.self) {
            try await failedReservations.withLease(locale: locale) { _ in
                throw TestFailure.expected
            }
        }
        #expect(failedSystem.releaseCallCount == 1)
        #expect(failedSystem.reservedLocaleKeys.isEmpty)

        let cancelledSystem = TestReservationSystem()
        let cancelledReservations = LiveSubtitleReservations(system: cancelledSystem)
        let operation = Task {
            try await cancelledReservations.withLease(locale: locale) { _ in
                try await Task.sleep(for: .seconds(30))
            }
        }
        await cancelledSystem.waitForReserveCall()
        operation.cancel()
        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
        #expect(cancelledSystem.releaseCallCount == 1)
        #expect(cancelledSystem.reservedLocaleKeys.isEmpty)
    }

    @available(macOS 26, *)
    @Test("A failed system reserve leaves the gate available for the next acquire")
    func reserveFailureDoesNotBlockNextAcquire() async throws {
        let system = TestReservationSystem()
        system.reserveErrorsRemaining = 1
        let reservations = LiveSubtitleReservations(system: system)
        let locale = Locale(identifier: "en-US")

        await #expect(throws: TestFailure.self) {
            try await reservations.acquire(locale: locale)
        }

        let lease = try await reservations.acquire(locale: locale)
        await reservations.release(lease)
        #expect(system.reserveCallCount == 2)
        #expect(system.releaseCallCount == 1)
        #expect(system.reservedLocaleKeys.isEmpty)
    }

    @available(macOS 26, *)
    @Test("A new acquire waits for an older system release to finish")
    func acquireWaitsForHangingRelease() async throws {
        let system = TestReservationSystem()
        let reservations = LiveSubtitleReservations(system: system)
        let locale = Locale(identifier: "en-US")
        let firstLease = try await reservations.acquire(locale: locale)
        system.suspendNextRelease = true

        let releaseTask = Task {
            await reservations.release(firstLease)
        }
        await system.waitForReleaseToSuspend()

        let acquireStarted = AsyncStream<Void>.makeStream()
        let acquireTask = Task {
            acquireStarted.continuation.yield(())
            acquireStarted.continuation.finish()
            return try await reservations.acquire(locale: locale)
        }
        for await _ in acquireStarted.stream { break }
        #expect(system.reserveCallCount == 1)

        system.resumeSuspendedRelease()
        await releaseTask.value
        let secondLease = try await acquireTask.value
        #expect(system.reserveCallCount == 2)

        await reservations.release(secondLease)
        #expect(system.releaseCallCount == 2)
        #expect(system.reservedLocaleKeys.isEmpty)
    }

    @available(macOS 26, *)
    @Test("Browsing four temporary languages returns to the prior baseline")
    func temporaryLanguageBrowsingReturnsToBaseline() async throws {
        let baseline = Locale(identifier: "fr-FR")
        let system = TestReservationSystem(preexisting: [baseline])
        let reservations = LiveSubtitleReservations(system: system)
        let baselineKeys = system.reservedLocaleKeys
        let locales = ["en-US", "ja-JP", "ko-KR", "zh-CN"].map(Locale.init(identifier:))

        var leases: [LiveSubtitleReservations.Lease] = []
        for locale in locales {
            leases.append(try await reservations.acquire(locale: locale))
        }
        for lease in leases.reversed() {
            await reservations.release(lease)
        }

        #expect(system.reserveCallCount == 4)
        #expect(system.releaseCallCount == 4)
        #expect(system.reservedLocaleKeys == baselineKeys)
    }

    @available(macOS 26, *)
    @Test("A successful explicit download retains its reservation")
    func retainedDownloadLeaseIsNotReleased() async throws {
        let system = TestReservationSystem()
        let reservations = LiveSubtitleReservations(system: system)
        let locale = Locale(identifier: "en-US")

        let lease = try await reservations.acquire(locale: locale)
        reservations.retain(lease)
        await reservations.release(lease)

        #expect(system.releaseCallCount == 0)
        #expect(system.reservedLocaleKeys == [TestReservationSystem.key(locale)])

        await #expect(throws: TestFailure.self) {
            try await reservations.withLease(locale: locale) { _ in
                throw TestFailure.expected
            }
        }
        #expect(system.releaseCallCount == 0)
        #expect(system.reservedLocaleKeys == [TestReservationSystem.key(locale)])
    }

    @available(macOS 26, *)
    @Test("A uniquely added standardized variant is released by its actual locale")
    func uniquelyAddedVariantIsReleased() async throws {
        let variant = Locale(identifier: "en-US")
        let system = TestReservationSystem()
        system.addedLocaleOverride = variant
        let reservations = LiveSubtitleReservations(system: system)

        let lease = try await reservations.acquire(locale: Locale(identifier: "en"))
        await reservations.release(lease)

        #expect(system.releaseCallCount == 1)
        #expect(system.lastReleasedLocaleKey == TestReservationSystem.key(variant))
        #expect(system.reservedLocaleKeys.isEmpty)
    }

    @available(macOS 26, *)
    @Test("A borrowed standardized variant does not require an exact locale spelling")
    func borrowedVariantDoesNotRequireExactKey() async throws {
        let variant = Locale(identifier: "en-US")
        let system = TestReservationSystem(preexisting: [variant])
        system.forceBorrowedReservation = true
        let reservations = LiveSubtitleReservations(system: system)

        let lease = try await reservations.acquire(locale: Locale(identifier: "en"))
        await reservations.release(lease)

        #expect(system.reserveCallCount == 1)
        #expect(system.releaseCallCount == 0)
        #expect(system.reservedLocaleKeys == [TestReservationSystem.key(variant)])
    }
}

@available(macOS 26, *)
@MainActor
private final class TestReservationSystem: LiveSubtitleReservationSystem {
    private var localesByKey: [String: Locale]
    private var reserveWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseSuspendWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendedRelease: CheckedContinuation<Void, Never>?

    var reserveCallCount = 0
    var releaseCallCount = 0
    var suspendNextRelease = false
    var forceBorrowedReservation = false
    var reserveErrorsRemaining = 0
    var addedLocaleOverride: Locale?
    var lastReleasedLocaleKey: String?

    init(preexisting: [Locale] = []) {
        localesByKey = Dictionary(uniqueKeysWithValues: preexisting.map { (Self.key($0), $0) })
    }

    var reservedLocaleKeys: Set<String> {
        Set(localesByKey.keys)
    }

    func reservedLocales() async -> [Locale] {
        Array(localesByKey.values)
    }

    func reserve(locale: Locale) async throws -> Bool {
        reserveCallCount += 1
        let waiters = reserveWaiters
        reserveWaiters.removeAll()
        waiters.forEach { $0.resume() }

        if reserveErrorsRemaining > 0 {
            reserveErrorsRemaining -= 1
            throw TestFailure.expected
        }
        if forceBorrowedReservation {
            forceBorrowedReservation = false
            return false
        }

        let key = Self.key(locale)
        guard localesByKey[key] == nil else { return false }
        let addedLocale = addedLocaleOverride
            ?? Locale(identifier: locale.identifier.replacingOccurrences(of: "-", with: "_"))
        localesByKey[Self.key(addedLocale)] = addedLocale
        return true
    }

    func release(locale: Locale) async -> Bool {
        releaseCallCount += 1
        lastReleasedLocaleKey = Self.key(locale)
        if suspendNextRelease {
            suspendNextRelease = false
            let waiters = releaseSuspendWaiters
            releaseSuspendWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                suspendedRelease = continuation
            }
        }
        return localesByKey.removeValue(forKey: Self.key(locale)) != nil
    }

    func waitForReserveCall() async {
        guard reserveCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            reserveWaiters.append(continuation)
        }
    }

    func waitForReleaseToSuspend() async {
        guard suspendedRelease == nil else { return }
        await withCheckedContinuation { continuation in
            releaseSuspendWaiters.append(continuation)
        }
    }

    func resumeSuspendedRelease() {
        suspendedRelease?.resume()
        suspendedRelease = nil
    }

    static func key(_ locale: Locale) -> String {
        locale.identifier(.bcp47).lowercased()
    }
}

private enum TestFailure: Error {
    case expected
}
