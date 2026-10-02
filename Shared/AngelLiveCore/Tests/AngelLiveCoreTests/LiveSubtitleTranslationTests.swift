import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Live subtitle translation")
struct LiveSubtitleTranslationTests {
    @Test @MainActor
    func usesSharedCloudConfigurationWithoutTitleOrDanmakuSwitches() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .llm
        try fixture.settings.saveCloudConfiguration(
            baseURL: "https://translation.example.invalid/v1",
            model: "fixture-model",
            apiKey: "fixture-secret"
        )
        #expect(!fixture.settings.isEnabled)
        #expect(!fixture.settings.isDanmakuEnabled)

        let provider = SubtitleImmediateProvider(result: "translated")
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        pipeline.enqueue("A progressive caption", sourceLanguage: "en-US", segmentID: "segment-a")
        #expect(await provider.waitForCallCount(1))
        await waitUntil { pipeline.text == "translated" }

        let request = try #require(await provider.requests.first)
        #expect(request.sourceLanguage == "en")
        #expect(request.contentKind == .subtitle)
        #expect(request.purpose == .automatic)
        #expect(request.baseURL?.absoluteString == "https://translation.example.invalid/v1")
        #expect(request.model == "fixture-model")
        #expect(request.apiKey == "fixture-secret")
    }

    @Test @MainActor
    func keepsOneFlightAndOverwritesPendingTextWithLatestUpdate() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )

        pipeline.enqueue("first", sourceLanguage: "en-US", segmentID: "segment-a")
        #expect(await provider.waitForCallCount(1))
        pipeline.enqueue("second", sourceLanguage: "en-US", segmentID: "segment-a")
        pipeline.enqueue("latest", sourceLanguage: "en-US", segmentID: "segment-a")
        #expect(await provider.callCount == 1)

        await provider.resolve(call: 0, returning: "older translation")
        #expect(await provider.waitForCallCount(2))
        await waitUntil { pipeline.text == "older translation" }
        #expect(await provider.requests.map(\.text) == ["first", "latest"])

        await provider.resolve(call: 1, returning: "latest translation")
        await waitUntil { pipeline.text == "latest translation" }
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func lateResultFromPreviousSegmentNeverReplacesCurrentSegment() async {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )

        pipeline.enqueue("old segment", sourceLanguage: "en-US", segmentID: "segment-old")
        #expect(await provider.waitForCallCount(1))
        pipeline.enqueue("new segment", sourceLanguage: "en-US", segmentID: "segment-new")
        #expect(await provider.waitForCallCount(2))

        await provider.resolve(call: 1, returning: "new translation")
        await waitUntil { pipeline.text == "new translation" }
        await provider.resolve(call: 0, returning: "late old translation")
        await Task.yield()
        await Task.yield()

        #expect(pipeline.text == "new translation")
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func resetAndConfigurationRevisionRejectRetiredResults() async {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )

        pipeline.enqueue("before reset", sourceLanguage: "en-US", segmentID: "segment-a")
        #expect(await provider.waitForCallCount(1))
        pipeline.reset()
        await provider.resolve(call: 0, returning: "retired reset result")
        await Task.yield()
        #expect(pipeline.text.isEmpty)

        pipeline.enqueue("before revision", sourceLanguage: "ja-JP", segmentID: "segment-b")
        #expect(await provider.waitForCallCount(2))
        fixture.settings.targetLanguage = "en-US"
        await waitUntil { pipeline.text.isEmpty && pipeline.errorMessage == nil }
        await provider.resolve(call: 1, returning: "retired revision result")
        await Task.yield()
        await Task.yield()

        #expect(pipeline.text.isEmpty)
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func sameLanguagePassesThroughAndMissingNativeResourcesSurfaceError() async {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        fixture.settings.targetLanguage = "en-US"
        let provider = SubtitleFailingProvider(error: .languageResourcesRequired)
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )

        pipeline.enqueue("Already English", sourceLanguage: "en-GB", segmentID: "segment-a")
        #expect(pipeline.text == "Already English")
        #expect(await provider.callCount == 0)

        fixture.settings.targetLanguage = "zh-Hans"
        pipeline.enqueue("Needs resources", sourceLanguage: "en-US", segmentID: "segment-b")
        #expect(await provider.waitForCallCount(1))
        await waitUntil { pipeline.errorMessage != nil }

        #expect(pipeline.text.isEmpty)
        #expect(pipeline.errorMessage == RoomTranslationError.languageResourcesRequired.localizedDescription)
        let request = await provider.lastRequest
        #expect(request?.contentKind == .subtitle)
        #expect(request?.purpose == .automatic)
    }
}

@MainActor
private final class SubtitleTranslationSettingsFixture {
    let defaults: UserDefaults
    let secrets = SubtitleMemorySecretStorage()
    let settings: RoomTranslationSettings

    init() {
        let suite = "LiveSubtitleTranslationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = RoomTranslationSettings(defaults: defaults, secretStorage: secrets)
    }
}

private final class SubtitleMemorySecretStorage: RoomTranslationSecretStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private actor SubtitleImmediateProvider: RoomTranslationProvider {
    let result: String
    private(set) var requests: [RoomTranslationRequest] = []

    init(result: String) {
        self.result = result
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        requests.append(request)
        return result
    }

    func waitForCallCount(_ expected: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while requests.count < expected, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return requests.count >= expected
    }
}

private actor SubtitleControlledProvider: RoomTranslationProvider {
    private(set) var requests: [RoomTranslationRequest] = []
    private var continuations: [Int: CheckedContinuation<String, Never>] = [:]

    var callCount: Int { requests.count }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        let call = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ expected: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while requests.count < expected, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return requests.count >= expected
    }

    func resolve(call: Int, returning value: String) {
        continuations.removeValue(forKey: call)?.resume(returning: value)
    }
}

private actor SubtitleFailingProvider: RoomTranslationProvider {
    let error: RoomTranslationError
    private(set) var callCount = 0
    private(set) var lastRequest: RoomTranslationRequest?

    init(error: RoomTranslationError) {
        self.error = error
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        callCount += 1
        lastRequest = request
        throw error
    }

    func waitForCallCount(_ expected: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while callCount < expected, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return callCount >= expected
    }
}

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition(), ContinuousClock.now < deadline {
        await Task.yield()
    }
    #expect(condition())
}
