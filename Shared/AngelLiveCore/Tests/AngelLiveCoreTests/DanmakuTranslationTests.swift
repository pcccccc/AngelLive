import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Danmaku translation", .serialized)
struct DanmakuTranslationTests {
    @Test @MainActor
    func settingsDefaultOffAndIndependentFromRoomTitles() {
        let fixture = DanmakuSettingsFixture()
        #expect(!fixture.settings.isEnabled)
        #expect(!fixture.settings.isDanmakuEnabled)

        let revision = fixture.settings.revision
        fixture.settings.isDanmakuEnabled = true
        #expect(!fixture.settings.isEnabled)
        #expect(fixture.settings.revision == revision + 1)

        let restored = RoomTranslationSettings(
            defaults: fixture.defaults,
            secretStorage: fixture.secrets
        )
        #expect(restored.isDanmakuEnabled)
        #expect(!restored.isEnabled)
    }

    @Test @MainActor
    func mixedSegmentsTranslateTextAndPreserveImagesAndMetadata() async throws {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuPrefixProvider()
        let pipeline = makePipeline(fixture: fixture, provider: provider)
        let image = DanmakuDisplayImage(
            url: try #require(URL(string: "https://media.example.invalid/reaction.png")),
            pixelSize: .init(width: 40, height: 20),
            altText: "[reaction]"
        )
        let original = DanmakuDisplayMessage(
            text: "Hello[reaction]World",
            nickname: "viewer-a",
            color: 0x123456,
            segments: [.text("Hello"), .image(image), .text("World")]
        )

        let delivered = await deliveredMessage(from: pipeline, message: original)
        #expect(delivered.text == "译:Hello[reaction]译:World")
        #expect(delivered.nickname == original.nickname)
        #expect(delivered.color == original.color)
        #expect(delivered.segments == [.text("译:Hello"), .image(image), .text("译:World")])

        let requests = await provider.requests
        #expect(requests.map(\.text) == ["Hello", "World"])
        #expect(requests.allSatisfy { $0.contentKind == .danmaku })
        #expect(requests.allSatisfy { !$0.text.contains(original.nickname) })
        #expect(requests.allSatisfy { !$0.text.contains(image.url.absoluteString) })
    }

    @Test @MainActor
    func pureImageAndUncertainOrSameLanguageTextStayOriginalWithoutProviderWork() async throws {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuPrefixProvider()
        let image = DanmakuDisplayImage(
            url: try #require(URL(string: "https://media.example.invalid/only-image.png")),
            pixelSize: nil,
            altText: "image"
        )
        let pureImage = DanmakuDisplayMessage(
            text: "image",
            nickname: "viewer-a",
            color: 0xFFFFFF,
            segments: [.image(image)]
        )
        let uncertain = DanmakuDisplayMessage(
            text: "2026 !!!",
            nickname: "viewer-b",
            color: 0xFFFFFF
        )

        let uncertainPipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            detector: DanmakuFixedLanguageDetector(language: nil)
        )
        #expect(await deliveredMessage(from: uncertainPipeline, message: pureImage) == pureImage)
        #expect(await deliveredMessage(from: uncertainPipeline, message: uncertain) == uncertain)

        let sameLanguagePipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            detector: DanmakuFixedLanguageDetector(language: "zh-Hans")
        )
        let sameLanguage = DanmakuDisplayMessage(
            text: "一条普通弹幕",
            nickname: "viewer-c",
            color: 0xFFFFFF
        )
        #expect(await deliveredMessage(from: sameLanguagePipeline, message: sameLanguage) == sameLanguage)
        #expect(await provider.callCount == 0)
    }

    @Test @MainActor
    func automaticDanmakuRejectsNonCommonSourcesForAppleAndLLM() async throws {
        for engine in [RoomTranslationEngine.apple, .llm] {
            let fixture = DanmakuSettingsFixture()
            fixture.settings.isDanmakuEnabled = true
            fixture.settings.engine = engine
            if engine == .llm {
                try fixture.settings.saveCloudConfiguration(
                    baseURL: "https://api.example.invalid/v1",
                    model: "fixture-model",
                    apiKey: "fixture-secret"
                )
            }
            let provider = DanmakuPrefixProvider()
            let pipeline = makePipeline(
                fixture: fixture,
                provider: provider,
                detector: DanmakuFixedLanguageDetector(language: "fr-FR")
            )
            let original = message("Un message neutre")

            #expect(await deliveredMessage(from: pipeline, message: original) == original)
            #expect(await provider.callCount == 0)
        }
    }

    @Test @MainActor
    func commonDanmakuLanguageVariantTranslatesAndSameBaseTargetSkips() async {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuPrefixProvider()
        let translatedPipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            detector: DanmakuFixedLanguageDetector(language: "ko-KR")
        )
        #expect(
            await deliveredMessage(from: translatedPipeline, message: message("fixture message")).text
                == "译:fixture message"
        )

        fixture.settings.targetLanguage = "en-US"
        let sameLanguagePipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            detector: DanmakuFixedLanguageDetector(language: "en-GB")
        )
        let original = message("Same language message")
        #expect(await deliveredMessage(from: sameLanguagePipeline, message: original) == original)
        #expect(await provider.callCount == 1)
    }

    @Test @MainActor
    func nativeBurstTranslatesFortyUniqueMessagesWhileCloudBudgetIsOccupied() async throws {
        let broker = DanmakuTranslationBroker()

        let cloudFixture = DanmakuSettingsFixture()
        cloudFixture.settings.isDanmakuEnabled = true
        try cloudFixture.settings.saveCloudConfiguration(
            baseURL: "https://api.example.invalid/v1",
            model: "fixture-model",
            apiKey: "fixture-secret"
        )
        cloudFixture.settings.engine = .llm
        let cloudProvider = DanmakuControlledProvider(
            behaviors: ["Cloud first": .hold, "Cloud second": .value("云端第二条译文")]
        )
        let cloudPipeline = makePipeline(
            fixture: cloudFixture,
            provider: cloudProvider,
            broker: broker
        )
        let cloudLog = DanmakuDeliveryLog()
        cloudPipeline.enqueue(message("Cloud first")) { cloudLog.messages.append($0) }
        cloudPipeline.enqueue(message("Cloud second")) { cloudLog.messages.append($0) }
        await cloudProvider.waitForCallCount(1)

        let nativeFixture = DanmakuSettingsFixture()
        nativeFixture.settings.isDanmakuEnabled = true
        nativeFixture.settings.engine = .apple
        let nativeProvider = DanmakuPrefixProvider()
        let nativePipeline = makePipeline(
            fixture: nativeFixture,
            provider: nativeProvider,
            detector: DanmakuFixedLanguageDetector(language: "ko"),
            broker: broker
        )
        let nativeLog = DanmakuDeliveryLog()
        for index in 0..<40 {
            nativePipeline.enqueue(message("Native message \(index)")) {
                nativeLog.messages.append($0)
            }
        }
        await waitForDeliveryCount(40, in: nativeLog)
        #expect(nativeLog.messages.map(\.text) == (0..<40).map { "译:Native message \($0)" })
        #expect(await nativeProvider.callCount == 40)
        #expect(await cloudProvider.callCount == 1)

        await cloudProvider.resume("Cloud first", returning: "云端第一条译文")
        await waitForDeliveryCount(2, in: cloudLog)
        #expect(cloudLog.messages.map(\.text) == ["云端第一条译文", "Cloud second"])
        #expect(await cloudProvider.callCount == 1)
    }

    @Test @MainActor
    func timeoutPreservesArrivalOrderAndRetiredRateLimitFailureDoesNotSuppressNewWork() async {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuControlledProvider(
            behaviors: [
                "First message": .hold,
                "Second message": .value("第二条译文"),
                "Third message": .value("第三条译文")
            ]
        )
        let broker = DanmakuTranslationBroker(
            nativeMaximumConcurrent: 2,
            cloudMinimumRequestInterval: .zero
        )
        let pipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            broker: broker,
            messageTimeout: .milliseconds(40)
        )
        let log = DanmakuDeliveryLog()
        let first = message("First message")
        let second = message("Second message")
        pipeline.enqueue(first) { log.messages.append($0) }
        pipeline.enqueue(second) { log.messages.append($0) }

        await provider.waitForCallCount(2)
        await waitForDeliveryCount(2, in: log)
        #expect(log.messages == [first, message("第二条译文")])

        await provider.resume("First message", throwing: RoomTranslationError.rateLimited)
        try? await Task.sleep(for: .milliseconds(10))
        let third = await deliveredMessage(from: pipeline, message: message("Third message"))
        #expect(third.text == "第三条译文")
        #expect(await provider.callCount == 3)
    }

    @Test @MainActor
    func pendingLimitReleasesOldestOriginalAndResetDropsRemainingResults() async {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuControlledProvider(
            behaviors: [
                "One message": .hold,
                "Two message": .hold,
                "Three message": .hold
            ]
        )
        let pipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            broker: DanmakuTranslationBroker(
                nativeMaximumConcurrent: 2,
                cloudMinimumRequestInterval: .zero
            ),
            maximumPending: 2,
            messageTimeout: .seconds(1)
        )
        let log = DanmakuDeliveryLog()
        let first = message("One message")
        pipeline.enqueue(first) { log.messages.append($0) }
        pipeline.enqueue(message("Two message")) { log.messages.append($0) }
        await provider.waitForCallCount(2)
        pipeline.enqueue(message("Three message")) { log.messages.append($0) }

        #expect(log.messages == [first])
        pipeline.reset()
        await provider.resumeAll(returning: "late")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(log.messages == [first])
    }

    @Test @MainActor
    func resetAndConfigurationRevisionRejectLateResultsWithoutLosingPendingMessages() async {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuControlledProvider(
            behaviors: ["Delayed message": .hold, "Reset message": .hold]
        )
        let pipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            broker: DanmakuTranslationBroker(
                nativeMaximumConcurrent: 2,
                cloudMinimumRequestInterval: .zero
            ),
            messageTimeout: .seconds(1)
        )
        let log = DanmakuDeliveryLog()

        let delayed = message("Delayed message")
        pipeline.enqueue(delayed) { log.messages.append($0) }
        await provider.waitForCallCount(1)
        fixture.settings.targetLanguage = "ja"
        await provider.resume("Delayed message", returning: "古い翻訳")
        await waitForDeliveryCount(1, in: log)
        #expect(log.messages == [delayed])

        pipeline.enqueue(message("Reset message")) { log.messages.append($0) }
        await provider.waitForCallCount(2)
        pipeline.reset()
        await provider.resume("Reset message", returning: "破棄する翻訳")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(log.messages == [delayed])
    }

    @Test @MainActor
    func disablingFlushesPendingOriginalBeforeSynchronouslyDeliveringNewOriginal() async {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuControlledProvider(behaviors: ["Pending message": .hold])
        let pipeline = makePipeline(
            fixture: fixture,
            provider: provider,
            broker: DanmakuTranslationBroker(cloudMinimumRequestInterval: .zero)
        )
        let log = DanmakuDeliveryLog()
        let pending = message("Pending message")
        let disabled = message("Disabled message")
        pipeline.enqueue(pending) { log.messages.append($0) }
        await provider.waitForCallCount(1)

        fixture.settings.isDanmakuEnabled = false
        pipeline.enqueue(disabled) { log.messages.append($0) }
        #expect(log.messages == [pending, disabled])

        await provider.resume("Pending message", returning: "late")
        try? await Task.sleep(for: .milliseconds(10))
        #expect(log.messages == [pending, disabled])
    }

    @Test @MainActor
    func sharedBrokerDeduplicatesCachesRateLimitsAndCapsProviderConcurrency() async throws {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        try fixture.settings.saveCloudConfiguration(
            baseURL: "https://api.example.invalid/v1",
            model: "fixture-model",
            apiKey: "fixture-secret"
        )
        fixture.settings.engine = .llm
        let provider = DanmakuControlledProvider(behaviors: ["Shared message": .hold])
        let broker = DanmakuTranslationBroker(
            cloudMaximumConcurrent: 2,
            cloudMinimumRequestInterval: .seconds(1)
        )
        let pipeline = makePipeline(fixture: fixture, provider: provider, broker: broker)
        let log = DanmakuDeliveryLog()

        pipeline.enqueue(message("Shared message")) { log.messages.append($0) }
        pipeline.enqueue(message("Shared message")) { log.messages.append($0) }
        await provider.waitForCallCount(1)
        await provider.resume("Shared message", returning: "共享译文")
        await waitForDeliveryCount(2, in: log)
        #expect(log.messages.map(\.text) == ["共享译文", "共享译文"])
        #expect(await provider.callCount == 1)

        let cached = await deliveredMessage(from: pipeline, message: message("Shared message"))
        #expect(cached.text == "共享译文")
        #expect(await provider.callCount == 1)
        let rateLimited = await deliveredMessage(from: pipeline, message: message("Different message"))
        #expect(rateLimited.text == "Different message")
        #expect(await provider.callCount == 1)

        let concurrencyProvider = DanmakuControlledProvider(
            behaviors: ["Alpha message": .hold, "Bravo message": .hold, "Charlie message": .value("C译文")]
        )
        let concurrencyPipeline = makePipeline(
            fixture: fixture,
            provider: concurrencyProvider,
            broker: DanmakuTranslationBroker(
                cloudMaximumConcurrent: 2,
                cloudMinimumRequestInterval: .zero
            )
        )
        let concurrencyLog = DanmakuDeliveryLog()
        concurrencyPipeline.enqueue(message("Alpha message")) { concurrencyLog.messages.append($0) }
        concurrencyPipeline.enqueue(message("Bravo message")) { concurrencyLog.messages.append($0) }
        await concurrencyProvider.waitForCallCount(2)
        concurrencyPipeline.enqueue(message("Charlie message")) { concurrencyLog.messages.append($0) }
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await concurrencyProvider.callCount == 2)
        await concurrencyProvider.resume("Alpha message", returning: "A译文")
        await concurrencyProvider.resume("Bravo message", returning: "B译文")
        await waitForDeliveryCount(3, in: concurrencyLog)
        #expect(concurrencyLog.messages.map(\.text) == ["A译文", "B译文", "Charlie message"])
        #expect(await concurrencyProvider.callCount == 2)
    }

    @Test @MainActor
    func explicitTitleTestClearsMatchingDanmakuFailureSuppression() async throws {
        let fixture = DanmakuSettingsFixture()
        fixture.settings.isDanmakuEnabled = true
        let provider = DanmakuSequenceProvider(
            outcomes: [
                .failure(.rateLimited),
                .success("标题测试成功"),
                .success("弹幕重试成功")
            ]
        )
        let broker = DanmakuTranslationBroker(cloudMinimumRequestInterval: .zero)
        let firstKey = danmakuKey(text: "First message", revision: fixture.settings.revision)
        let firstRequest = danmakuRequest(text: "First message")
        await #expect(throws: RoomTranslationError.rateLimited) {
            try await broker.translate(
                key: firstKey,
                request: firstRequest,
                provider: provider,
                timeout: .seconds(1)
            )
        }
        await #expect(throws: RoomTranslationError.rateLimited) {
            try await broker.translate(
                key: danmakuKey(text: "Blocked message", revision: fixture.settings.revision),
                request: danmakuRequest(text: "Blocked message"),
                provider: provider,
                timeout: .seconds(1)
            )
        }
        #expect(await provider.callCount == 1)

        let titleService = RoomTitleTranslationService(
            settings: fixture.settings,
            languageDetector: DanmakuFixedLanguageDetector(language: "en"),
            appleProvider: provider,
            llmProvider: provider,
            danmakuBroker: broker
        )
        #expect(try await titleService.testTranslation() == "标题测试成功")
        #expect(
            try await broker.translate(
                key: danmakuKey(text: "Retry message", revision: fixture.settings.revision),
                request: danmakuRequest(text: "Retry message"),
                provider: provider,
                timeout: .seconds(1)
            ) == "弹幕重试成功"
        )
        #expect(await provider.callCount == 3)
    }
}

@MainActor
private final class DanmakuSettingsFixture {
    let defaults: UserDefaults
    let secrets = DanmakuMemorySecretStorage()
    let settings: RoomTranslationSettings

    init() {
        let suite = "DanmakuTranslationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = RoomTranslationSettings(defaults: defaults, secretStorage: secrets)
    }
}

private final class DanmakuMemorySecretStorage: RoomTranslationSecretStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private struct DanmakuFixedLanguageDetector: RoomTitleLanguageDetecting {
    let language: String?
    func sourceLanguage(for text: String) -> String? { language }
}

private actor DanmakuPrefixProvider: RoomTranslationProvider {
    private(set) var requests: [RoomTranslationRequest] = []
    var callCount: Int { requests.count }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        requests.append(request)
        return "译:\(request.text)"
    }
}

private actor DanmakuControlledProvider: RoomTranslationProvider {
    enum Behavior: Sendable {
        case hold
        case value(String)
        case failure(RoomTranslationError)
    }

    private var behaviors: [String: Behavior]
    private var continuations: [String: CheckedContinuation<String, any Error>] = [:]
    private(set) var callCount = 0

    init(behaviors: [String: Behavior]) {
        self.behaviors = behaviors
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        callCount += 1
        switch behaviors[request.text] ?? .value("译:\(request.text)") {
        case .hold:
            return try await withCheckedThrowingContinuation {
                continuations[request.text] = $0
            }
        case .value(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func waitForCallCount(_ expected: Int) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while callCount < expected, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(callCount >= expected)
    }

    func resume(_ text: String, returning value: String) {
        continuations.removeValue(forKey: text)?.resume(returning: value)
    }

    func resume(_ text: String, throwing error: any Error) {
        continuations.removeValue(forKey: text)?.resume(throwing: error)
    }

    func resumeAll(returning value: String) {
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending { continuation.resume(returning: value) }
    }
}

private actor DanmakuSequenceProvider: RoomTranslationProvider {
    enum Outcome: Sendable {
        case success(String)
        case failure(RoomTranslationError)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        callCount += 1
        guard !outcomes.isEmpty else { throw RoomTranslationError.invalidResponse }
        switch outcomes.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

@MainActor
private final class DanmakuDeliveryLog {
    var messages: [DanmakuDisplayMessage] = []
}

@MainActor
private func makePipeline(
    fixture: DanmakuSettingsFixture,
    provider: any RoomTranslationProvider,
    detector: any RoomTitleLanguageDetecting = DanmakuFixedLanguageDetector(language: "en"),
    broker: DanmakuTranslationBroker = DanmakuTranslationBroker(cloudMinimumRequestInterval: .zero),
    maximumPending: Int? = nil,
    messageTimeout: Duration = .seconds(1)
) -> DanmakuTranslationPipeline {
    if let maximumPending {
        return DanmakuTranslationPipeline(
            settings: fixture.settings,
            languageDetector: detector,
            appleProvider: provider,
            llmProvider: provider,
            broker: broker,
            maximumPending: maximumPending,
            messageTimeout: messageTimeout
        )
    }
    return DanmakuTranslationPipeline(
        settings: fixture.settings,
        languageDetector: detector,
        appleProvider: provider,
        llmProvider: provider,
        broker: broker,
        messageTimeout: messageTimeout
    )
}

@MainActor
private func deliveredMessage(
    from pipeline: DanmakuTranslationPipeline,
    message: DanmakuDisplayMessage
) async -> DanmakuDisplayMessage {
    await withCheckedContinuation { continuation in
        pipeline.enqueue(message) { continuation.resume(returning: $0) }
    }
}

@MainActor
private func waitForDeliveryCount(_ count: Int, in log: DanmakuDeliveryLog) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while log.messages.count < count, clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(log.messages.count == count)
}

private func message(_ text: String) -> DanmakuDisplayMessage {
    DanmakuDisplayMessage(text: text, nickname: "viewer", color: 0xFFFFFF)
}

private func danmakuKey(text: String, revision: Int) -> RoomTranslationCacheKey {
    RoomTranslationCacheKey(
        original: text,
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        engine: .apple,
        endpoint: "",
        model: "",
        configurationRevision: revision,
        contentKind: .danmaku
    )
}

private func danmakuRequest(text: String) -> RoomTranslationRequest {
    RoomTranslationRequest(
        text: text,
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        baseURL: nil,
        model: nil,
        apiKey: nil,
        contentKind: .danmaku
    )
}
