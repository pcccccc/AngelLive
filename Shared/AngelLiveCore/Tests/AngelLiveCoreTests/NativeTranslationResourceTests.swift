import Foundation
import Testing
@testable import AngelLiveCore

#if !os(tvOS)
@Suite("Native translation resources", .serialized)
struct NativeTranslationResourceTests {
    @Test @MainActor
    func automaticSupportedPairStopsBeforeHostExecutionAndCachesResourceGate() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let availability = NativeAvailabilityFixture(status: .supported)
        let provider = AppleRoomTranslationProvider(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ko",
            targetLanguage: "zh-Hans"
        )

        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            try await provider.translate(request(for: pair))
        }
        #expect(availability.callCount == 1)

        // The cached supported result blocks another automatic request without
        // entering a download-capable host or repeating the availability query.
        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            try await provider.translate(request(for: pair))
        }
        #expect(availability.callCount == 1)
    }

    @Test @MainActor
    func resourcePolicyRefreshesCachedAvailabilityForAutomaticGate() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let availability = NativeAvailabilityFixture(status: .supported)
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            try await policy.requireInstalled(pair)
        }
        #expect(await policy.refresh(pair) == .supported)

        availability.status = .installed
        #expect(await policy.refresh(pair) == .installed)
        try await policy.requireInstalled(pair)
        #expect(availability.callCount == 3)
    }

    @Test @MainActor
    func concurrentAutomaticChecksShareOneAvailabilityLookup() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let availability = NativeAvailabilityFixture(status: .supported, suspendsOnce: true)
        let policy = NativeTranslationResourcePolicy(availability: availability)
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "ja",
            targetLanguage: "zh-Hans"
        )

        let first = Task { @MainActor in try await policy.requireInstalled(pair) }
        await availability.waitUntilCalled()
        let second = Task { @MainActor in try await policy.requireInstalled(pair) }
        availability.resume()

        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            try await first.value
        }
        await #expect(throws: RoomTranslationError.languageResourcesRequired) {
            try await second.value
        }
        #expect(availability.callCount == 1)
    }

    @Test @MainActor
    func providerMapsInstalledNotDownloadedAndUnsupportedStatuses() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let pair = NativeTranslationLanguagePair(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )
        for (availabilityStatus, expected) in [
            (NativeTranslationAvailabilityStatus.installed, NativeTranslationLanguageStatus.installed),
            (.supported, .notDownloaded),
            (.unsupported, .unsupported)
        ] {
            let availability = NativeAvailabilityFixture(status: availabilityStatus)
            let provider = AppleRoomTranslationProvider(availability: availability)
            #expect(await provider.nativeLanguageStatus(for: pair) == expected)
            #expect(availability.callCount == 1)
        }
    }

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
    var status: NativeTranslationAvailabilityStatus
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private let suspendsOnce: Bool

    init(status: NativeTranslationAvailabilityStatus, suspendsOnce: Bool = false) {
        self.status = status
        self.suspendsOnce = suspendsOnce
    }

    func status(for pair: NativeTranslationLanguagePair) async -> NativeTranslationAvailabilityStatus {
        callCount += 1
        if suspendsOnce, callCount == 1 {
            await withCheckedContinuation { continuation = $0 }
        }
        return status
    }

    func waitUntilCalled() async {
        while callCount == 0 { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
#endif
