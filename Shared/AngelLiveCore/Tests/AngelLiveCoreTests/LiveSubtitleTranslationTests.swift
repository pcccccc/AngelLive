import Foundation
import Observation
import Synchronization
import Testing
@testable import AngelLiveCore

@Suite("Live subtitle translation", .timeLimit(.minutes(1)))
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
        defer { pipeline.reset() }
        pipeline.enqueue("A progressive caption", sourceLanguage: "en-US", segmentID: "segment-a")
        try await waitUntil { pipeline.text == "translated" }

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
        defer {
            pipeline.reset()
            provider.finish()
        }

        pipeline.enqueue("first", sourceLanguage: "en-US", segmentID: "segment-a")
        try await provider.waitForCallCount(1)
        pipeline.enqueue("second", sourceLanguage: "en-US", segmentID: "segment-a")
        pipeline.enqueue("latest", sourceLanguage: "en-US", segmentID: "segment-a")
        #expect(provider.callCount == 1)

        provider.resolve(call: 0, returning: "older translation")
        try await provider.waitForCallCount(2)
        try await waitUntil { pipeline.text == "older translation" }
        #expect(provider.requests.map(\.text) == ["first", "latest"])

        provider.resolve(call: 1, returning: "latest translation")
        try await waitUntil { pipeline.text == "latest translation" }
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func defaultIntervalKeepsOnlyLatestPendingSubtitle() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider
        )
        defer {
            pipeline.reset()
            provider.finish()
        }

        let firstEnqueueInstant = ContinuousClock.now
        pipeline.enqueue("first", sourceLanguage: "en-US", segmentID: "segment-a")
        try await provider.waitForCallCount(1)

        pipeline.enqueue("partial two", sourceLanguage: "en-US", segmentID: "segment-a")
        pipeline.enqueue("partial three", sourceLanguage: "en-US", segmentID: "segment-a")
        pipeline.enqueue("latest", sourceLanguage: "en-US", segmentID: "segment-a")
        #expect(provider.callCount == 1)

        provider.resolve(call: 0, returning: "first translation")
        try await provider.waitForCallCount(2)

        let arrivals = provider.arrivalInstants
        try #require(arrivals.count == 2)
        // The pipeline records its request instant immediately before invoking the
        // provider, so the first enqueue is the stable lower-bound baseline.
        #expect(firstEnqueueInstant.duration(to: arrivals[1]) >= .milliseconds(600))
        #expect(provider.requests.map(\.text) == ["first", "latest"])

        provider.resolve(call: 1, returning: "latest translation")
        try await waitUntil { pipeline.text == "latest translation" }
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func resetDropsActivePendingAndScheduledDefaultIntervalInput() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider
        )
        defer {
            pipeline.reset()
            provider.finish()
        }

        let firstEnqueueInstant = ContinuousClock.now
        pipeline.enqueue("first", sourceLanguage: "en-US", segmentID: "segment-a")
        try await provider.waitForCallCount(1)
        pipeline.enqueue("retired pending", sourceLanguage: "en-US", segmentID: "segment-a")

        // The subtitle host calls reset when it stops or is disabled. A new
        // session must discard both in-flight and pending input. Retire one
        // more scheduled input synchronously before the MainActor can run it;
        // this avoids assuming when a sleeping task will be rescheduled.
        pipeline.reset()
        pipeline.enqueue("retired gate", sourceLanguage: "en-US", segmentID: "segment-b")
        #expect(provider.callCount == 1)
        pipeline.reset()
        pipeline.enqueue("new session", sourceLanguage: "en-US", segmentID: "segment-c")
        try await provider.waitForCallCount(2)
        #expect(provider.requests.map(\.text) == ["first", "new session"])

        let arrivals = provider.arrivalInstants
        try #require(arrivals.count == 2)
        #expect(firstEnqueueInstant.duration(to: arrivals[1]) >= .milliseconds(600))

        provider.resolve(call: 1, returning: "new translation")
        try await waitUntil { pipeline.text == "new translation" }
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func lateResultFromPreviousSegmentNeverReplacesCurrentSegment() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer {
            pipeline.reset()
            provider.finish()
        }

        pipeline.enqueue("old segment", sourceLanguage: "en-US", segmentID: "segment-old")
        try await provider.waitForCallCount(1)
        pipeline.enqueue("new segment", sourceLanguage: "en-US", segmentID: "segment-new")
        try await provider.waitForCallCount(2)

        provider.resolve(call: 1, returning: "new translation")
        try await waitUntil { pipeline.text == "new translation" }
        provider.resolve(call: 0, returning: "late old translation")
        await Task.yield()
        await Task.yield()

        #expect(pipeline.text == "new translation")
        #expect(pipeline.errorMessage == nil)
    }

    @Test @MainActor
    func configurationRevisionDropsActiveAndPendingWork() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleControlledProvider()
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer {
            pipeline.reset()
            provider.finish()
        }

        pipeline.enqueue("old active", sourceLanguage: "en-US", segmentID: "segment-a")
        try await provider.waitForCallCount(1)
        pipeline.enqueue("old pending", sourceLanguage: "en-US", segmentID: "segment-a")

        fixture.settings.targetLanguage = "en-US"
        pipeline.enqueue("current revision", sourceLanguage: "ja-JP", segmentID: "segment-a")
        try await provider.waitForCallCount(2)
        #expect(provider.requests.map(\.text) == ["old active", "current revision"])
        let currentRequest = try #require(provider.requests.last)
        #expect(currentRequest.targetLanguage == "en-US")

        provider.resolve(call: 1, returning: "current translation")
        try await waitUntil { pipeline.text == "current translation" }
        provider.resolve(call: 0, returning: "retired translation")
        await Task.yield()
        await Task.yield()

        #expect(pipeline.text == "current translation")
        #expect(pipeline.errorMessage == nil)
    }

    @Test(arguments: SubtitleLanguageScenario.cases)
    @MainActor
    func routesSupportedMatchingAndUnsupportedLanguages(
        _ scenario: SubtitleLanguageScenario
    ) async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        fixture.settings.targetLanguage = scenario.targetLanguage
        let provider = SubtitleImmediateProvider(result: "translated")
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer { pipeline.reset() }

        pipeline.enqueue(
            scenario.text,
            sourceLanguage: scenario.sourceLanguage,
            segmentID: "segment-a"
        )
        if scenario.expectedRequestSource != nil {
            try await waitUntil { pipeline.text == scenario.expectedText }
        }

        #expect(pipeline.text == scenario.expectedText)
        #expect(pipeline.errorMessage == nil)
        let requests = await provider.requests
        let expectedRequestSources = scenario.expectedRequestSource.map { [$0] } ?? []
        #expect(requests.map(\.sourceLanguage) == expectedRequestSources)
    }

    @Test @MainActor
    func missingNativeResourcesSurfaceError() async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .apple
        let provider = SubtitleFailingProvider(error: .languageResourcesRequired)
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer { pipeline.reset() }

        pipeline.enqueue("Needs resources", sourceLanguage: "en-US", segmentID: "segment-b")
        try await waitUntil { pipeline.errorMessage != nil }

        #expect(pipeline.text.isEmpty)
        #expect(pipeline.errorMessage == RoomTranslationError.languageResourcesRequired.localizedDescription)
        let request = try #require(await provider.lastRequest)
        #expect(request.contentKind == .subtitle)
        #expect(request.purpose == .automatic)
    }

    @Test(arguments: SubtitleLLMFailureScenario.cases)
    @MainActor
    func llmFailureSurfacesThenNextPartialRecovers(
        _ scenario: SubtitleLLMFailureScenario
    ) async throws {
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .llm
        try fixture.settings.saveCloudConfiguration(
            baseURL: "https://translation.example.invalid/v1",
            model: "fixture-model",
            apiKey: "fixture-secret"
        )
        let provider = SubtitleScriptedProvider(
            outcomes: [scenario.outcome, .success("recovered translation")]
        )
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer { pipeline.reset() }

        pipeline.enqueue("failing partial", sourceLanguage: "en-US", segmentID: "segment-a")
        try await waitUntil {
            pipeline.errorMessage == scenario.expectedError.localizedDescription
        }
        #expect(pipeline.text.isEmpty)
        #expect(await provider.requests.count == 1)

        pipeline.enqueue("recovery partial", sourceLanguage: "en-US", segmentID: "segment-a")
        try await waitUntil {
            pipeline.text == "recovered translation" && pipeline.errorMessage == nil
        }
        let requests = await provider.requests
        #expect(requests.map(\.text) == ["failing partial", "recovery partial"])
        #expect(requests.allSatisfy { $0.contentKind == .subtitle })
    }

    @Test @MainActor
    func llmTransportTimeoutMapsToServiceUnavailableThenRecovers() async throws {
        SubtitleTranslationURLProtocol.reset(outcomes: [
            .failure(.timedOut),
            .success(#"{"choices":[{"message":{"content":"network recovery"}}]}"#)
        ])
        defer { SubtitleTranslationURLProtocol.reset(outcomes: []) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubtitleTranslationURLProtocol.self]
        let provider = OpenAICompatibleTranslationProvider(
            session: URLSession(configuration: configuration)
        )
        let fixture = SubtitleTranslationSettingsFixture()
        fixture.settings.engine = .llm
        try fixture.settings.saveCloudConfiguration(
            baseURL: "https://subtitle-translation.example.invalid/v1",
            model: "fixture-model",
            apiKey: "fixture-secret"
        )
        let pipeline = LiveSubtitleTranslationPipeline(
            settings: fixture.settings,
            appleProvider: provider,
            llmProvider: provider,
            minimumRequestInterval: .zero
        )
        defer { pipeline.reset() }

        pipeline.enqueue("timeout partial", sourceLanguage: "en-US", segmentID: "segment-a")
        try await waitUntil {
            pipeline.errorMessage == RoomTranslationError.serviceUnavailable.localizedDescription
        }

        pipeline.enqueue("network recovery partial", sourceLanguage: "en-US", segmentID: "segment-a")
        try await waitUntil {
            pipeline.text == "network recovery" && pipeline.errorMessage == nil
        }
        #expect(SubtitleTranslationURLProtocol.requestCount == 2)
    }
}

struct SubtitleLanguageScenario: Sendable {
    let text: String
    let sourceLanguage: String
    let targetLanguage: String
    let expectedText: String
    let expectedRequestSource: String?

    static let cases = [
        Self(
            text: "English partial",
            sourceLanguage: "en_US",
            targetLanguage: "zh-Hans",
            expectedText: "translated",
            expectedRequestSource: "en"
        ),
        Self(
            text: "Japanese partial",
            sourceLanguage: "ja-JP",
            targetLanguage: "zh-Hans",
            expectedText: "translated",
            expectedRequestSource: "ja"
        ),
        Self(
            text: "Korean partial",
            sourceLanguage: "ko-KR",
            targetLanguage: "en-US",
            expectedText: "translated",
            expectedRequestSource: "ko"
        ),
        Self(
            text: "English passthrough",
            sourceLanguage: "en-GB",
            targetLanguage: "en-US",
            expectedText: "English passthrough",
            expectedRequestSource: nil
        ),
        Self(
            text: "Japanese passthrough",
            sourceLanguage: "ja-JP",
            targetLanguage: "ja",
            expectedText: "Japanese passthrough",
            expectedRequestSource: nil
        ),
        Self(
            text: "Korean passthrough",
            sourceLanguage: "ko_KR",
            targetLanguage: "ko-KR",
            expectedText: "Korean passthrough",
            expectedRequestSource: nil
        ),
        Self(
            text: "Unsupported source",
            sourceLanguage: "fr-FR",
            targetLanguage: "zh-Hans",
            expectedText: "",
            expectedRequestSource: nil
        )
    ]
}

struct SubtitleLLMFailureScenario: Sendable {
    let outcome: SubtitleProviderOutcome
    let expectedError: RoomTranslationError

    static let cases = [
        Self(outcome: .failure(.serviceUnavailable), expectedError: .serviceUnavailable),
        Self(outcome: .failure(.authentication), expectedError: .authentication),
        Self(outcome: .failure(.rateLimited), expectedError: .rateLimited),
        Self(outcome: .success("   "), expectedError: .invalidResponse)
    ]
}

enum SubtitleProviderOutcome: Sendable {
    case success(String)
    case failure(RoomTranslationError)
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
}

@MainActor
private final class SubtitleControlledProvider: RoomTranslationProvider {
    private(set) var requests: [RoomTranslationRequest] = []
    private(set) var arrivalInstants: [ContinuousClock.Instant] = []
    private var continuations: [Int: CheckedContinuation<String, any Error>] = [:]
    private let callEvents: AsyncStream<Int>
    private let callEventContinuation: AsyncStream<Int>.Continuation

    var callCount: Int { requests.count }

    init() {
        (callEvents, callEventContinuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        let call = requests.count
        requests.append(request)
        arrivalInstants.append(.now)
        callEventContinuation.yield(requests.count)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ expected: Int) async throws {
        guard requests.count < expected else { return }
        // Each provider has exactly one sequential event consumer per test.
        for await count in callEvents {
            try Task.checkCancellation()
            if count >= expected { return }
        }
        try Task.checkCancellation()
        throw SubtitleTestError.callEventsFinished
    }

    func resolve(call: Int, returning value: String) {
        continuations.removeValue(forKey: call)?.resume(returning: value)
    }

    func finish() {
        callEventContinuation.finish()
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(throwing: CancellationError())
        }
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
}

private actor SubtitleScriptedProvider: RoomTranslationProvider {
    private var outcomes: [SubtitleProviderOutcome]
    private(set) var requests: [RoomTranslationRequest] = []

    init(outcomes: [SubtitleProviderOutcome]) {
        self.outcomes = outcomes
    }

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        requests.append(request)
        guard !outcomes.isEmpty else { throw RoomTranslationError.invalidResponse }
        switch outcomes.removeFirst() {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

private final class SubtitleTranslationURLProtocol: URLProtocol {
    enum Outcome: Sendable {
        case success(String)
        case failure(URLError.Code)
    }

    private struct State: Sendable {
        var outcomes: [Outcome] = []
        var requestCount = 0
    }

    // URLSession can invoke URLProtocol callbacks concurrently. This mutex
    // protects the fixture state; a dedicated hostname keeps it isolated to
    // this one transport test even when the test runner executes in parallel.
    private static let state = Mutex(State())

    static var requestCount: Int {
        state.withLock { $0.requestCount }
    }

    static func reset(outcomes: [Outcome]) {
        state.withLock {
            $0.outcomes = outcomes
            $0.requestCount = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "subtitle-translation.example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let outcome = Self.state.withLock { state -> Outcome in
            state.requestCount += 1
            guard !state.outcomes.isEmpty else { return .failure(.badServerResponse) }
            return state.outcomes.removeFirst()
        }

        switch outcome {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .success(let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private enum SubtitleTestError: Error {
    case callEventsFinished
    case observationEnded
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    while !condition() {
        let (changes, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        withObservationTracking {
            _ = condition()
        } onChange: {
            continuation.yield()
            continuation.finish()
        }
        if condition() {
            continuation.finish()
            return
        }

        var iterator = changes.makeAsyncIterator()
        guard await iterator.next() != nil else {
            try Task.checkCancellation()
            throw SubtitleTestError.observationEnded
        }
        try Task.checkCancellation()
    }
}
