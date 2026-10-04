import Foundation
import Speech

@available(iOS 26, macOS 26, tvOS 26, *)
@MainActor
protocol LiveSubtitleReservationSystem: AnyObject {
    func reservedLocales() async -> [Locale]
    func reserve(locale: Locale) async throws -> Bool
    func release(locale: Locale) async -> Bool
}

@available(iOS 26, macOS 26, tvOS 26, *)
@MainActor
private final class SystemLiveSubtitleReservationSystem: LiveSubtitleReservationSystem {
    func reservedLocales() async -> [Locale] {
        await AssetInventory.reservedLocales
    }

    func reserve(locale: Locale) async throws -> Bool {
        try await AssetInventory.reserve(locale: locale)
    }

    func release(locale: Locale) async -> Bool {
        await AssetInventory.release(reservedLocale: locale)
    }
}

@available(iOS 26, macOS 26, tvOS 26, *)
@MainActor
final class LiveSubtitleReservations {
    struct Lease: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let localeKey: String
    }

    static let shared = LiveSubtitleReservations(
        system: SystemLiveSubtitleReservationSystem()
    )

    private struct Reservation {
        var leaseIDs: Set<UUID>
        let systemLocale: Locale
        let ownsSystemReservation: Bool
        var retained: Bool
    }

    private let system: any LiveSubtitleReservationSystem
    private var reservations: [String: Reservation] = [:]
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(system: any LiveSubtitleReservationSystem) {
        self.system = system
    }

    func acquire(locale: Locale) async throws -> Lease {
        await enterOperation()
        defer { leaveOperation() }
        try Task.checkCancellation()

        let localeKey = Self.localeKey(locale)
        let lease = Lease(id: UUID(), localeKey: localeKey)
        if var reservation = reservations[localeKey] {
            reservation.leaseIDs.insert(lease.id)
            reservations[localeKey] = reservation
            return lease
        }

        let before = await system.reservedLocales()
        let beforeKeys = Set(before.map(Self.localeKey))
        let created = try await system.reserve(locale: locale)
        let after = await system.reservedLocales()

        let systemLocale: Locale
        if created {
            let addedLocales = after.filter { !beforeKeys.contains(Self.localeKey($0)) }
            let addedLocale: Locale?
            if addedLocales.count == 1 {
                addedLocale = addedLocales[0]
            } else {
                addedLocale = addedLocales.first(where: { Self.localeKey($0) == localeKey })
            }
            guard let addedLocale else {
                throw LiveSubtitleReservationError.createdLocaleNotFound
            }
            systemLocale = addedLocale
        } else {
            // A false result means the system already had an equivalent reservation.
            // Borrowed reservations are never released, so its exact system spelling
            // is intentionally not inferred from the locale inventory.
            systemLocale = locale
        }

        reservations[localeKey] = Reservation(
            leaseIDs: [lease.id],
            systemLocale: systemLocale,
            ownsSystemReservation: created,
            retained: false
        )
        return lease
    }

    func release(_ lease: Lease) async {
        await enterOperation()
        defer { leaveOperation() }

        guard var reservation = reservations[lease.localeKey],
              reservation.leaseIDs.remove(lease.id) != nil
        else {
            return
        }
        guard reservation.leaseIDs.isEmpty else {
            reservations[lease.localeKey] = reservation
            return
        }

        reservations.removeValue(forKey: lease.localeKey)
        guard reservation.ownsSystemReservation, !reservation.retained else { return }
        _ = await system.release(locale: reservation.systemLocale)
    }

    func retain(_ lease: Lease) {
        guard var reservation = reservations[lease.localeKey],
              reservation.leaseIDs.contains(lease.id)
        else {
            return
        }
        reservation.retained = true
        reservations[lease.localeKey] = reservation
    }

    func withLease<Result: Sendable>(
        locale: Locale,
        operation: @MainActor (Lease) async throws -> Result
    ) async throws -> Result {
        let lease = try await acquire(locale: locale)
        do {
            try Task.checkCancellation()
            let result = try await operation(lease)
            await release(lease)
            return result
        } catch {
            await release(lease)
            throw error
        }
    }

    private func enterOperation() async {
        if !operationInProgress {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func leaveOperation() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            return
        }
        operationWaiters.removeFirst().resume()
    }

    private static func localeKey(_ locale: Locale) -> String {
        locale.identifier(.bcp47).lowercased()
    }
}

private enum LiveSubtitleReservationError: Error {
    case createdLocaleNotFound
}
