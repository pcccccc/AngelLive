import CryptoKit
import Foundation

public struct CDNObservation: Codable, Sendable, Equatable {
    public var attempts: Int
    public var successes: Int
    public var meanStartupMilliseconds: Double
    public var updatedAt: Date
}

/// Learns only a stable plugin-provided line identity. Playback URLs are never keys.
public actor CDNPreferenceStore {
    public static let shared = CDNPreferenceStore()
    private let defaults: UserDefaults
    private let storageKey = "AngelLive.Playback.CDNObservations.v1"
    private var observations: [String: CDNObservation]
    private let validity: TimeInterval = 7 * 24 * 60 * 60

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observations = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: CDNObservation].self, from: $0) } ?? [:]
    }

    public func preferredIndex(in args: [LiveQualityModel], pluginID: String,
                               now: Date = .now) -> Int? {
        preferredIndex(lineIDs: args.map(\.cdn), pluginID: pluginID, now: now)
    }

    public func preferredIndex(lineIDs: [String], pluginID: String,
                               now: Date = .now) -> Int? {
        prune(now: now)
        guard !lineIDs.isEmpty else { return nil }
        var best: (index: Int, score: Double)?
        for (index, lineID) in lineIDs.enumerated() {
            guard let key = key(pluginID: pluginID, lineID: lineID),
                  let observation = observations[key], observation.attempts >= 3 else { return nil }
            let successRate = Double(observation.successes) / Double(observation.attempts)
            let speed = observation.successes == 0 ? 0
                : 500 / max(observation.meanStartupMilliseconds, 500)
            let score = 0.7 * successRate + 0.3 * speed
            if best == nil || score > best!.score { best = (index, score) }
        }
        return best?.index
    }

    public func recordSuccess(lineID: String, pluginID: String,
                              startupMilliseconds: Double, now: Date = .now) {
        guard startupMilliseconds.isFinite, startupMilliseconds >= 0,
              let key = key(pluginID: pluginID, lineID: lineID) else { return }
        prune(now: now)
        var item = observations[key] ?? .init(attempts: 0, successes: 0,
                                              meanStartupMilliseconds: 0, updatedAt: now)
        item.attempts += 1
        item.successes += 1
        item.meanStartupMilliseconds += (startupMilliseconds - item.meanStartupMilliseconds)
            / Double(item.successes)
        item.updatedAt = now
        observations[key] = item
        persist()
    }

    public func recordFailure(lineID: String, pluginID: String, now: Date = .now) {
        guard let key = key(pluginID: pluginID, lineID: lineID) else { return }
        prune(now: now)
        var item = observations[key] ?? .init(attempts: 0, successes: 0,
                                              meanStartupMilliseconds: 0, updatedAt: now)
        item.attempts += 1
        item.updatedAt = now
        observations[key] = item
        persist()
    }

    private func key(pluginID: String, lineID: String) -> String? {
        guard !pluginID.isEmpty, !lineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        // Hash both components, including their boundaries. No raw plugin/line names are persisted.
        let value = "\(pluginID.utf8.count):\(pluginID)\(lineID.utf8.count):\(lineID)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func prune(now: Date) {
        let oldCount = observations.count
        observations = observations.filter { now.timeIntervalSince($0.value.updatedAt) < validity }
        if observations.count != oldCount { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(observations) { defaults.set(data, forKey: storageKey) }
    }
}
