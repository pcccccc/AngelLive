import Foundation
import Observation

@MainActor @Observable
public final class RoomTitleTranslationService {
    public static let shared = RoomTitleTranslationService()

    public private(set) var lastErrorMessage: String?
    private var nativeLanguageStatuses: [
        NativeTranslationLanguagePair: NativeTranslationLanguageStatus
    ] = [:]

    public var nativeLanguagePairs: [NativeTranslationLanguagePair] {
        RoomTranslationLanguageCatalog.nativePairs(targetLanguage: settings.targetLanguage)
    }

    private let settings: RoomTranslationSettings
    private let languageDetector: any RoomTitleLanguageDetecting
    private let appleProvider: any RoomTranslationProvider
    private let llmProvider: any RoomTranslationProvider
    private let coordinator: TranslationWorkCoordinator
    private let danmakuBroker: DanmakuTranslationBroker
    private let displayCacheCapacity: Int
    private var displayedTranslations: [RoomTranslationRequestIdentity: String] = [:]
    private var displayCacheOrder: [RoomTranslationRequestIdentity] = []

    public convenience init() {
        self.init(
            settings: .shared,
            languageDetector: NaturalRoomTitleLanguageDetector(),
            appleProvider: liveAppleRoomTranslationProvider(),
            llmProvider: OpenAICompatibleTranslationProvider.live()
        )
    }

    init(
        settings: RoomTranslationSettings,
        languageDetector: any RoomTitleLanguageDetecting,
        appleProvider: any RoomTranslationProvider,
        llmProvider: any RoomTranslationProvider,
        coordinator: TranslationWorkCoordinator = TranslationWorkCoordinator(),
        danmakuBroker: DanmakuTranslationBroker = .shared,
        displayCacheCapacity: Int = 200
    ) {
        self.settings = settings
        self.languageDetector = languageDetector
        self.appleProvider = appleProvider
        self.llmProvider = llmProvider
        self.coordinator = coordinator
        self.danmakuBroker = danmakuBroker
        self.displayCacheCapacity = max(1, displayCacheCapacity)
    }

    public func displayTitle(for original: String) -> String {
        guard settings.isEnabled else { return original }
        return displayedTranslations[requestIdentity(for: original)] ?? original
    }

    public func translate(_ original: String) async {
        guard settings.isEnabled,
              let key = cacheKey(for: original),
              !roomTranslationLanguagesMatch(key.sourceLanguage, key.targetLanguage) else {
            return
        }
        let displayKey = requestIdentity(for: original)
        if displayedTranslations[displayKey] != nil { return }

        let request: RoomTranslationRequest
        do {
            request = try makeRequest(text: original, sourceLanguage: key.sourceLanguage)
        } catch {
            record(error, for: key)
            return
        }

        let provider = key.engine == .apple ? appleProvider : llmProvider
        do {
            let acquisition = try await coordinator.acquire(key: key) {
                try await provider.translate(request)
            }
            let translated: String
            switch acquisition {
            case let .cached(value):
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { throw RoomTranslationError.invalidResponse }
                translated = normalized
            case let .lease(lease):
                translated = try await value(of: lease, key: key)
            }
            try Task.checkCancellation()
            guard isCurrent(key) else { return }
            storeForDisplay(translated, displayKey: displayKey, key: key)
            lastErrorMessage = nil
        } catch is CancellationError {
        } catch {
            record(error, for: key)
        }
    }

    public func testTranslation() async throws -> String {
        let revision = settings.revision
        let engine = settings.engine
        let target = settings.targetLanguage
        let endpoint = settings.cloudBaseURL
        let model = settings.cloudModel
        let targetsEnglish = target.lowercased().split(separator: "-").first == "en"
        let text = targetsEnglish ? "これは翻訳のテストです" : "A neutral live room title"
        let source = targetsEnglish ? "ja" : "en"
        let request = try makeRequest(
            text: text,
            sourceLanguage: source,
            purpose: .explicitTest
        )
        let provider = settings.engine == .apple ? appleProvider : llmProvider
        do {
            await danmakuBroker.prepareForExplicitRetry(revision: revision)
            if let retrying = provider as? any RoomTranslationRetrying {
                await retrying.prepareForExplicitRetry()
            }
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await provider.translate(request) }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw RoomTranslationError.unavailable
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw RoomTranslationError.invalidResponse }
            try Task.checkCancellation()
            guard settings.revision == revision,
                  settings.engine == engine,
                  settings.targetLanguage == target,
                  settings.cloudBaseURL == endpoint,
                  settings.cloudModel == model else {
                throw CancellationError()
            }
            lastErrorMessage = nil
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RoomTranslationError {
            try Task.checkCancellation()
            guard isCurrentTestConfiguration(
                revision: revision,
                engine: engine,
                target: target,
                endpoint: endpoint,
                model: model
            ) else { throw CancellationError() }
            lastErrorMessage = error.localizedDescription
            throw error
        } catch {
            try Task.checkCancellation()
            guard isCurrentTestConfiguration(
                revision: revision,
                engine: engine,
                target: target,
                endpoint: endpoint,
                model: model
            ) else { throw CancellationError() }
            lastErrorMessage = RoomTranslationError.serviceUnavailable.localizedDescription
            throw RoomTranslationError.serviceUnavailable
        }
    }

    public func clearError() {
        lastErrorMessage = nil
    }

    public func nativeLanguageStatus(
        for pair: NativeTranslationLanguagePair
    ) -> NativeTranslationLanguageStatus {
        nativeLanguageStatuses[pair] ?? .checking
    }

    public func refreshNativeLanguageStatuses() async {
        let engine = settings.engine
        let target = settings.targetLanguage
        let pairs = nativeLanguagePairs
        let provider = appleProvider as? any RoomTranslationLanguagePreparing
        nativeLanguageStatuses = Dictionary(uniqueKeysWithValues: pairs.map { ($0, .checking) })
        var refreshed: [NativeTranslationLanguagePair: NativeTranslationLanguageStatus] = [:]
        refreshed.reserveCapacity(pairs.count)

        for pair in pairs {
            guard !Task.isCancelled else { return }
            if let provider {
                refreshed[pair] = await provider.nativeLanguageStatus(for: pair)
            } else {
                refreshed[pair] = .unsupported
            }
        }
        guard !Task.isCancelled,
              settings.engine == engine,
              settings.targetLanguage == target else {
            return
        }
        nativeLanguageStatuses = refreshed
    }

    public func prepareNativeLanguages(_ pair: NativeTranslationLanguagePair) async throws {
        guard let provider = appleProvider as? any RoomTranslationLanguagePreparing else {
            throw RoomTranslationError.unavailable
        }
        let engine = settings.engine
        let target = settings.targetLanguage
        do {
            try await provider.prepareLanguages(
                sourceLanguage: pair.sourceLanguage,
                targetLanguage: pair.targetLanguage
            )
            try Task.checkCancellation()
            guard settings.engine == engine,
                  settings.targetLanguage == target else {
                throw CancellationError()
            }
            nativeLanguageStatuses[pair] = .installed
            lastErrorMessage = nil
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RoomTranslationError {
            let status = await provider.nativeLanguageStatus(for: pair)
            try Task.checkCancellation()
            guard settings.engine == engine,
                  settings.targetLanguage == target else {
                throw CancellationError()
            }
            nativeLanguageStatuses[pair] = status
            lastErrorMessage = error.localizedDescription
            throw error
        } catch {
            let status = await provider.nativeLanguageStatus(for: pair)
            try Task.checkCancellation()
            guard settings.engine == engine,
                  settings.targetLanguage == target else {
                throw CancellationError()
            }
            nativeLanguageStatuses[pair] = status
            lastErrorMessage = RoomTranslationError.serviceUnavailable.localizedDescription
            throw RoomTranslationError.serviceUnavailable
        }
    }

    func requestIdentity(for original: String, lifecycleEnabled: Bool = true) -> RoomTranslationRequestIdentity {
        RoomTranslationRequestIdentity(
            original: original,
            enabled: settings.isEnabled && lifecycleEnabled,
            revision: settings.revision
        )
    }

    private func cacheKey(for original: String) -> RoomTranslationCacheKey? {
        guard let sourceLanguage = languageDetector.sourceLanguage(for: original),
              RoomTranslationLanguageCatalog.supportsAutomaticTranslation(from: sourceLanguage) else {
            return nil
        }
        return RoomTranslationCacheKey(
            original: original,
            sourceLanguage: sourceLanguage,
            targetLanguage: settings.targetLanguage,
            engine: settings.engine,
            endpoint: settings.engine == .llm ? settings.cloudBaseURL : "",
            model: settings.engine == .llm ? settings.cloudModel : "",
            configurationRevision: settings.revision
        )
    }

    private func makeRequest(
        text: String,
        sourceLanguage: String,
        purpose: RoomTranslationRequestPurpose = .automatic
    ) throws -> RoomTranslationRequest {
        if settings.engine == .llm {
            let cloud = try settings.cloudConfiguration()
            return RoomTranslationRequest(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: settings.targetLanguage,
                baseURL: cloud.baseURL,
                model: cloud.model,
                apiKey: cloud.apiKey,
                purpose: purpose
            )
        }
        return RoomTranslationRequest(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: settings.targetLanguage,
            baseURL: nil,
            model: nil,
            apiKey: nil,
            purpose: purpose
        )
    }

    private func value(
        of lease: TranslationWorkCoordinator.Lease,
        key: RoomTranslationCacheKey
    ) async throws -> String {
        try await withTaskCancellationHandler {
            do {
                let value = try await lease.task.value
                try Task.checkCancellation()
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { throw RoomTranslationError.invalidResponse }
                guard isCurrent(key) else {
                    await coordinator.release(key: key, flightID: lease.flightID, consumerID: lease.consumerID)
                    throw CancellationError()
                }
                await coordinator.complete(key: key, flightID: lease.flightID, value: normalized)
                return normalized
            } catch {
                await coordinator.release(key: key, flightID: lease.flightID, consumerID: lease.consumerID)
                throw error
            }
        } onCancel: {
            Task {
                await self.coordinator.release(
                    key: key,
                    flightID: lease.flightID,
                    consumerID: lease.consumerID
                )
            }
        }
    }

    private func isCurrent(_ key: RoomTranslationCacheKey) -> Bool {
        settings.isEnabled
            && settings.revision == key.configurationRevision
            && settings.engine == key.engine
            && settings.targetLanguage == key.targetLanguage
            && (key.engine != .llm
                || (settings.cloudBaseURL == key.endpoint && settings.cloudModel == key.model))
    }

    private func isCurrentTestConfiguration(
        revision: Int,
        engine: RoomTranslationEngine,
        target: String,
        endpoint: String,
        model: String
    ) -> Bool {
        settings.revision == revision
            && settings.engine == engine
            && settings.targetLanguage == target
            && settings.cloudBaseURL == endpoint
            && settings.cloudModel == model
    }

    private func storeForDisplay(
        _ translation: String,
        displayKey: RoomTranslationRequestIdentity,
        key: RoomTranslationCacheKey
    ) {
        displayedTranslations[displayKey] = translation
        displayCacheOrder.removeAll { $0 == displayKey }
        displayCacheOrder.append(displayKey)
        while displayCacheOrder.count > displayCacheCapacity, let oldest = displayCacheOrder.first {
            displayCacheOrder.removeFirst()
            displayedTranslations.removeValue(forKey: oldest)
        }
    }

    private func record(_ error: any Error, for key: RoomTranslationCacheKey) {
        guard isCurrent(key) else { return }
        if let error = error as? RoomTranslationError {
            lastErrorMessage = error.localizedDescription
        } else {
            lastErrorMessage = RoomTranslationError.serviceUnavailable.localizedDescription
        }
    }
}

struct RoomTranslationRequestIdentity: Hashable {
    let original: String
    let enabled: Bool
    let revision: Int
}
