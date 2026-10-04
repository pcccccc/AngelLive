import Foundation
import Testing
@testable import AngelLiveCore

#if !os(tvOS)
import Translation

@Suite("Native translation resources", .serialized)
struct NativeTranslationResourceTests {
    @Test @MainActor
    func lowLatencyInstalledIsPreferredWithoutQueryingDefault() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let availability = NativeAvailabilityFixture(statuses: [
            .lowLatency: .installed,
            .systemDefault: .installed
        ])
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        #expect(try await policy.requireInstalled(pair) == .lowLatency)
        #expect(availability.callCount(for: .lowLatency) == 1)
        #expect(availability.callCount(for: .systemDefault) == 0)
    }

    @Test @MainActor
    func automaticFallsBackToInstalledDefaultWithoutDownloading() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let availability = NativeAvailabilityFixture(statuses: [
            .lowLatency: .supported,
            .systemDefault: .installed
        ])
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        #expect(try await policy.requireInstalled(pair) == .systemDefault)
        #expect(availability.callCount(for: .lowLatency) == 1)
        #expect(availability.callCount(for: .systemDefault) == 1)
    }

    @Test @MainActor
    func explicitTestPrefersInstalledLowLatencyThenFallsBackToDefault() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )
        let lowLatencyPolicy = NativeTranslationResourcePolicy(
            availability: NativeAvailabilityFixture(statuses: [
                .lowLatency: .installed,
                .systemDefault: .installed
            ])
        )
        #expect(try await lowLatencyPolicy.sessionSelection(
            for: pair,
            purpose: .explicitTest
        ) == .installed(.lowLatency))

        let defaultPolicy = NativeTranslationResourcePolicy(
            availability: NativeAvailabilityFixture(statuses: [
                .lowLatency: .supported,
                .systemDefault: .installed
            ])
        )

        #expect(try await defaultPolicy.sessionSelection(
            for: pair,
            purpose: .explicitTest
        ) == .installed(.systemDefault))
    }

    @Test @MainActor
    func explicitTestUsesDownloadCapableSessionOnlyWhenResourcesAreMissing() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let missingAvailability = NativeAvailabilityFixture(
            statuses: [.lowLatency: .supported, .systemDefault: .supported]
        )
        let policy = NativeTranslationResourcePolicy(availability: missingAvailability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ja",
            targetLanguage: "zh-Hans"
        )

        #expect(try await policy.sessionSelection(
            for: pair,
            purpose: .explicitTest
        ) == .downloadCapable)

        let prepareAvailability = NativeAvailabilityFixture(statuses: [:])
        let preparePolicy = NativeTranslationResourcePolicy(availability: prepareAvailability)
        #expect(try await preparePolicy.sessionSelection(
            for: pair,
            purpose: .prepareLanguages
        ) == .downloadCapable)
        #expect(prepareAvailability.callCount(for: .lowLatency) == 0)
        #expect(prepareAvailability.callCount(for: .systemDefault) == 0)
    }

    @Test @MainActor
    func explicitTestRejectsUnsupportedPairWithoutDownloadSession() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let policy = NativeTranslationResourcePolicy(availability: NativeAvailabilityFixture(
            statuses: [.lowLatency: .unsupported, .systemDefault: .unsupported]
        ))
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ko",
            targetLanguage: "zh-Hans"
        )

        await #expect(throws: RoomTranslationError.unavailable) {
            _ = try await policy.sessionSelection(for: pair, purpose: .explicitTest)
        }
    }

    @Test @MainActor
    func automaticDistinguishesMissingFromUnsupportedResources() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ko",
            targetLanguage: "zh-Hans"
        )

        let missing = NativeTranslationResourcePolicy(availability: NativeAvailabilityFixture(
            statuses: [.lowLatency: .supported, .systemDefault: .supported]
        ))
        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            _ = try await missing.requireInstalled(pair)
        }

        let unsupported = NativeTranslationResourcePolicy(availability: NativeAvailabilityFixture(
            statuses: [.lowLatency: .unsupported, .systemDefault: .unsupported]
        ))
        await #expect(throws: RoomTranslationError.unavailable) {
            _ = try await unsupported.requireInstalled(pair)
        }
    }

    @Test @MainActor
    func concurrentAutomaticChecksDeduplicateEachStrategy() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let availability = NativeAvailabilityFixture(
            statuses: [.lowLatency: .supported, .systemDefault: .installed],
            suspending: .lowLatency
        )
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ja",
            targetLanguage: "zh-Hans"
        )

        let first = Task { @MainActor in try await policy.requireInstalled(pair) }
        await availability.waitUntilCalled(.lowLatency)
        let second = Task { @MainActor in try await policy.requireInstalled(pair) }
        availability.resume(.lowLatency)

        #expect(try await first.value == .systemDefault)
        #expect(try await second.value == .systemDefault)
        #expect(availability.callCount(for: .lowLatency) == 1)
        #expect(availability.callCount(for: .systemDefault) == 1)
    }

    @Test @MainActor
    func downloadRefreshUsesManualStrategyWithoutDefaultFalsePositive() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let availability = NativeAvailabilityFixture(statuses: [
            .lowLatency: .supported,
            .systemDefault: .installed
        ])
        let provider = AppleRoomTranslationProvider(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        #expect(await provider.nativeLanguageStatus(for: pair) == .installed)
        #expect(await provider.downloadLanguageStatus(for: pair) == .notDownloaded)

        availability.statuses[.lowLatency] = .installed
        #expect(await provider.downloadLanguageStatus(for: pair) == .installed)

        availability.statuses[.lowLatency] = .supported
        #expect(await provider.downloadLanguageStatus(for: pair) == .notDownloaded)
        #expect(await provider.nativeLanguageStatus(for: pair) == .installed)
    }

    @Test @MainActor
    func refreshPromotesLowLatencyAfterDefaultStrategyWasCached() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let availability = NativeAvailabilityFixture(statuses: [
            .lowLatency: .supported,
            .systemDefault: .installed
        ])
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        #expect(try await policy.requireInstalled(pair) == .systemDefault)
        availability.statuses[.lowLatency] = .installed
        #expect(await policy.refreshDownloadStatus(pair) == .installed)
        #expect(try await policy.requireInstalled(pair) == .lowLatency)
    }

    @Test @MainActor
    func retiredAvailabilityResultDoesNotOverwriteRefreshedCache() async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let availability = StaleNativeAvailabilityFixture(responses: [
            .supported,
            .installed
        ])
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        let retired = Task { @MainActor in
            await policy.refreshDownloadStatus(pair)
        }
        await availability.waitForCallCount(1)
        let current = Task { @MainActor in
            await policy.refreshDownloadStatus(pair)
        }
        await availability.waitForCallCount(2)

        availability.resume(call: 1)
        #expect(await current.value == .installed)
        availability.resume(call: 0)
        #expect(await retired.value == .supported)
        #expect(try await policy.requireInstalled(pair) == .lowLatency)
    }

    @Test @MainActor
    func automaticMissingResourcesFailBeforeQueueingHostWork() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let availability = NativeAvailabilityFixture(statuses: [
            .lowLatency: .supported,
            .systemDefault: .supported
        ])
        let provider = AppleRoomTranslationProvider(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ko",
            targetLanguage: "zh-Hans"
        )

        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            try await provider.translate(request(for: pair))
        }
        #expect(provider.preferredSourceLanguage(targetLanguage: pair.targetLanguage) == nil)
        #expect(provider.configurationRevision == 0)
    }

    #if os(macOS)
    @Test(
        "Installed default resources translate through the live subtitle pipeline",
        .enabled(if: ProcessInfo.processInfo.environment["ANGELLIVE_NATIVE_TRANSLATION_INTEGRATION"] == "1")
    )
    @MainActor
    func installedDefaultResourcesTranslateThroughLiveSubtitlePipeline() async throws {
        guard #available(macOS 26.4, *) else { return }
        let sourceLanguage = "en"
        let targetLanguage = "zh-Hans"
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let lowLatencyStatus = await LanguageAvailability(preferredStrategy: .lowLatency)
            .status(from: source, to: target)
        let defaultStatus = await LanguageAvailability().status(from: source, to: target)
        #expect(lowLatencyStatus == .supported)
        #expect(defaultStatus == .installed)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        let selectedStrategy = try await NativeTranslationResourcePolicy(
            availability: NativeSystemAvailabilityFixture()
        ).requireInstalled(pair)
        #expect(selectedStrategy == .systemDefault)
        let installedOnlySession = TranslationSession(
            installedSource: source,
            target: target
        )
        #expect(!installedOnlySession.canRequestDownloads)

        let suiteName = "NativeSubtitleTranslationIntegration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RoomTranslationSettings(
            defaults: defaults,
            secretStorage: NativeTranslationMemorySecretStorage()
        )
        settings.engine = .apple
        settings.targetLanguage = targetLanguage

        let provider = AppleRoomTranslationProvider.shared
        let owner = UUID()
        provider.setHostExpected(owner: owner, expected: true)
        let hostTask = Task {
            await runNativeTranslationHost(
                owner: owner,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }

        let pipeline = LiveSubtitleTranslationPipeline(
            settings: settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer {
            pipeline.reset()
            provider.setHostExpected(owner: owner, expected: false)
            hostTask.cancel()
        }

        let sourceText = ProcessInfo.processInfo.environment[
            "ANGELLIVE_NATIVE_TRANSLATION_SOURCE_TEXT"
        ] ?? "Today we are checking the subtitle feature."
        let translationStartedAt = ContinuousClock.now
        pipeline.enqueue(
            sourceText,
            sourceLanguage: "en-US",
            segmentID: "native-fixture-segment"
        )
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while pipeline.text.isEmpty,
              pipeline.errorMessage == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let translatedText = try #require(
            pipeline.text.isEmpty ? nil : pipeline.text,
            "Native pipeline error: \(pipeline.errorMessage ?? "timed out")"
        )
        #expect(translatedText != sourceText)
        #expect(translatedText.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        })
        let elapsed = translationStartedAt.duration(to: .now).components
        let elapsedMilliseconds = Double(elapsed.seconds) * 1_000
            + Double(elapsed.attoseconds) / 1_000_000_000_000_000

        let result = NativeTranslationIntegrationResult(
            timestamp: Date.now.ISO8601Format(),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            translatedText: translatedText,
            selectedStrategy: selectedStrategy == .lowLatency
                ? "lowLatency"
                : "systemDefault",
            canRequestDownloads: installedOnlySession.canRequestDownloads,
            elapsedMilliseconds: elapsedMilliseconds
        )
        let data = try JSONEncoder().encode(result)
        print("ANGELLIVE_NATIVE_TRANSLATION_RESULT \(String(decoding: data, as: UTF8.self))")

        pipeline.reset()
        provider.setHostExpected(owner: owner, expected: false)
        hostTask.cancel()
        await hostTask.value
    }
    #endif

    @Test
    func batchResponsesRouteByClientIdentifierAndLeaveMissingResponsesUnmapped() {
        let first = UUID()
        let second = UUID()
        let missing = UUID()
        let unknown = UUID()
        let routed = RoomTranslationNativeBatchRouter.results(
            requestIDs: [first, second, missing],
            responses: [
                RoomTranslationNativeBatchResponse(
                    clientIdentifier: second.uuidString,
                    targetText: "second"
                ),
                RoomTranslationNativeBatchResponse(
                    clientIdentifier: unknown.uuidString,
                    targetText: "unknown"
                ),
                RoomTranslationNativeBatchResponse(
                    clientIdentifier: first.uuidString,
                    targetText: "first"
                ),
                RoomTranslationNativeBatchResponse(
                    clientIdentifier: first.uuidString,
                    targetText: "duplicate"
                ),
                RoomTranslationNativeBatchResponse(clientIdentifier: nil, targetText: "nil")
            ]
        )

        #expect(routed == [first: "first", second: "second"])
        #expect(routed[missing] == nil)
    }

    @Test
    func batchFailureUsesRemainingCurrentExecutionAfterFirstWasCancelled() throws {
        var state = RoomTranslationNativeExecutionState()
        let owner = UUID()
        let cancelledRequest = UUID()
        let remainingRequest = UUID()
        let cancelledExecution = state.assign(requestID: cancelledRequest, owner: owner)
        let remainingExecution = state.assign(requestID: remainingRequest, owner: owner)
        let candidates = [
            (requestID: cancelledRequest, executionID: cancelledExecution),
            (requestID: remainingRequest, executionID: remainingExecution)
        ]

        state.remove(requestID: cancelledRequest)
        let representative = try #require(state.firstCurrent(in: candidates))
        #expect(representative.requestID == remainingRequest)
        #expect(representative.executionID == remainingExecution)

        _ = state.retire(owner: owner)
        #expect(state.firstCurrent(in: candidates) == nil)
    }

    @Test
    func requestsDefaultToAutomaticAndLanguagePairHasStableIdentity() {
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ko",
            targetLanguage: "zh-Hans"
        )
        let request = request(for: pair)
        #expect(request.purpose == .automatic)
        #expect(pair.id == "ko\u{0}zh-Hans")
        #expect(pair.displayName.contains(" → "))
    }

    private func request(for pair: NativeTranslationLanguagePair) -> RoomTranslationRequest {
        RoomTranslationRequest(
            text: "A neutral live message",
            sourceLanguage: pair.sourceLanguage,
            targetLanguage: pair.targetLanguage,
            baseURL: nil,
            model: nil,
            apiKey: nil,
            contentKind: .danmaku
        )
    }
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor
private final class NativeAvailabilityFixture: NativeTranslationAvailabilityChecking {
    var statuses: [NativeTranslationStrategy: NativeTranslationAvailabilityStatus]
    private(set) var callCounts: [NativeTranslationStrategy: Int] = [:]
    private var continuations: [NativeTranslationStrategy: CheckedContinuation<Void, Never>] = [:]
    private var strategiesToSuspend: Set<NativeTranslationStrategy>

    init(
        statuses: [NativeTranslationStrategy: NativeTranslationAvailabilityStatus],
        suspending strategy: NativeTranslationStrategy? = nil
    ) {
        self.statuses = statuses
        strategiesToSuspend = strategy.map { Set([$0]) } ?? []
    }

    func status(
        for pair: NativeTranslationLanguagePair,
        strategy: NativeTranslationStrategy
    ) async -> NativeTranslationAvailabilityStatus {
        callCounts[strategy, default: 0] += 1
        if strategiesToSuspend.remove(strategy) != nil {
            await withCheckedContinuation { continuations[strategy] = $0 }
        }
        return statuses[strategy] ?? .unsupported
    }

    func callCount(for strategy: NativeTranslationStrategy) -> Int {
        callCounts[strategy, default: 0]
    }

    func waitUntilCalled(_ strategy: NativeTranslationStrategy) async {
        while callCount(for: strategy) == 0 { await Task.yield() }
    }

    func resume(_ strategy: NativeTranslationStrategy) {
        continuations.removeValue(forKey: strategy)?.resume()
    }
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor
private final class StaleNativeAvailabilityFixture: NativeTranslationAvailabilityChecking {
    private let responses: [NativeTranslationAvailabilityStatus]
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var callCount = 0

    init(responses: [NativeTranslationAvailabilityStatus]) {
        self.responses = responses
    }

    func status(
        for pair: NativeTranslationLanguagePair,
        strategy: NativeTranslationStrategy
    ) async -> NativeTranslationAvailabilityStatus {
        let call = callCount
        callCount += 1
        await withCheckedContinuation { continuations[call] = $0 }
        return responses[call]
    }

    func waitForCallCount(_ expected: Int) async {
        while callCount < expected { await Task.yield() }
    }

    func resume(call: Int) {
        continuations.removeValue(forKey: call)?.resume()
    }
}

#if os(macOS)
private struct NativeTranslationIntegrationResult: Codable {
    let timestamp: String
    let sourceLanguage: String
    let targetLanguage: String
    let sourceText: String
    let translatedText: String
    let selectedStrategy: String
    let canRequestDownloads: Bool
    let elapsedMilliseconds: Double
}

@available(macOS 26.4, *)
@MainActor
private final class NativeSystemAvailabilityFixture: NativeTranslationAvailabilityChecking {
    func status(
        for pair: NativeTranslationLanguagePair,
        strategy: NativeTranslationStrategy
    ) async -> NativeTranslationAvailabilityStatus {
        let availability = strategy == .lowLatency
            ? LanguageAvailability(preferredStrategy: .lowLatency)
            : LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: pair.sourceLanguage),
            to: Locale.Language(identifier: pair.targetLanguage)
        )
        switch status {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}

@available(macOS 26.4, *)
private nonisolated func runNativeTranslationHost(
    owner: UUID,
    sourceLanguage: String,
    targetLanguage: String
) async {
    let session = TranslationSession(
        installedSource: Locale.Language(identifier: sourceLanguage),
        target: Locale.Language(identifier: targetLanguage),
        preferredStrategy: .lowLatency
    )
    await AppleRoomTranslationProvider.hostAction(
        owner: owner,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage
    )(session)
}

private final class NativeTranslationMemorySecretStorage: RoomTranslationSecretStorage {
    private var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}
#endif
#endif
