import Foundation
import Synchronization
import Testing
@testable import AngelLiveCore

@Suite("Room title translation", .serialized)
struct RoomTitleTranslationTests {
    @Test @MainActor
    func cloudSettingsBindSecretToEndpointAndPreserveItOnlyForSameEndpoint() throws {
        let fixture = SettingsFixture()
        let settings = fixture.settings
        #expect(!settings.isEnabled)

        try settings.saveCloudConfiguration(
            baseURL: " https://api.example.invalid/openai/ ",
            model: " fixture-model ",
            apiKey: " fixture-secret "
        )
        #expect(settings.cloudBaseURL == "https://api.example.invalid/openai")
        #expect(settings.cloudModel == "fixture-model")
        #expect(settings.hasAPIKey)
        #expect(try settings.cloudConfiguration().apiKey == "fixture-secret")

        try settings.saveCloudConfiguration(
            baseURL: "https://api.example.invalid/openai",
            model: "fixture-model-2",
            apiKey: ""
        )
        #expect(try settings.cloudConfiguration().apiKey == "fixture-secret")
        #expect(throws: RoomTranslationError.apiKeyRequired) {
            try settings.saveCloudConfiguration(
                baseURL: "https://other.example.invalid/v4",
                model: "fixture-model",
                apiKey: ""
            )
        }
        #expect(settings.cloudBaseURL == "https://api.example.invalid/openai")
    }

    @Test @MainActor
    func mismatchedKeychainEndpointIsNeverReused() throws {
        let fixture = SettingsFixture()
        try fixture.settings.saveCloudConfiguration(
            baseURL: "https://first.example.invalid/v1",
            model: "fixture-model",
            apiKey: "fixture-secret"
        )
        fixture.defaults.set(
            "https://second.example.invalid/v1",
            forKey: "roomTranslation.cloudBaseURL"
        )

        let restored = RoomTranslationSettings(
            defaults: fixture.defaults,
            secretStorage: fixture.secrets
        )
        #expect(!restored.hasAPIKey)
        #expect(throws: RoomTranslationError.apiKeyRequired) {
            _ = try restored.cloudConfiguration()
        }
    }

    @Test @MainActor
    func settingsRejectUnsafeURLsAndNormalizeTargetLanguage() {
        let fixture = SettingsFixture()
        let settings = fixture.settings
        for rawURL in [
            "http://api.example.invalid/v1",
            "https://user:password@api.example.invalid/v1",
            "https://api.example.invalid/v1?token=secret",
            "https://api.example.invalid/v1#fragment"
        ] {
            #expect(throws: RoomTranslationError.invalidBaseURL) {
                try settings.saveCloudConfiguration(
                    baseURL: rawURL,
                    model: "fixture-model",
                    apiKey: "fixture-secret"
                )
            }
        }

        let revision = settings.revision
        settings.targetLanguage = "en-US"
        #expect(settings.targetLanguage == "en-US")
        #expect(settings.revision == revision + 1)
    }

    @Test @MainActor
    func sameLanguageAndUncertainTitlesNeverCallProvider() async {
        let fixture = SettingsFixture()
        fixture.settings.isEnabled = true
        fixture.settings.targetLanguage = "zh-Hans"
        let provider = RecordingTranslationProvider(result: "不应调用")
        let sameLanguage = RoomTitleTranslationService(
            settings: fixture.settings,
            languageDetector: FixedLanguageDetector(language: "zh-Hans"),
            appleProvider: provider,
            llmProvider: provider
        )
        await sameLanguage.translate("一个直播标题")

        let uncertain = RoomTitleTranslationService(
            settings: fixture.settings,
            languageDetector: FixedLanguageDetector(language: nil),
            appleProvider: provider,
            llmProvider: provider
        )
        await uncertain.translate("2026 !!!")
        #expect(await provider.callCount == 0)
    }

    @Test @MainActor
    func concurrentCardsShareWorkAndReuseCache() async {
        let fixture = SettingsFixture()
        fixture.settings.isEnabled = true
        let provider = SlowTranslationProvider(result: "已翻译")
        let service = makeService(fixture: fixture, provider: provider)

        async let first: Void = service.translate("A neutral room title")
        async let second: Void = service.translate("A neutral room title")
        _ = await (first, second)
        #expect(await provider.callCount == 1)
        #expect(service.displayTitle(for: "A neutral room title") == "已翻译")

        await service.translate("A neutral room title")
        #expect(await provider.callCount == 1)
    }

    @Test @MainActor
    func cacheIsIsolatedByConfigurationAndDisableShowsOriginalImmediately() async {
        let fixture = SettingsFixture()
        fixture.settings.isEnabled = true
        let provider = CountingTranslationProvider()
        let service = makeService(fixture: fixture, provider: provider)

        await service.translate("A neutral room title")
        #expect(service.displayTitle(for: "A neutral room title") == "zh-Hans-1")
        fixture.settings.targetLanguage = "ja"
        #expect(service.displayTitle(for: "A neutral room title") == "A neutral room title")
        await service.translate("A neutral room title")
        #expect(service.displayTitle(for: "A neutral room title") == "ja-2")

        fixture.settings.isEnabled = false
        #expect(service.displayTitle(for: "A neutral room title") == "A neutral room title")
        #expect(await provider.callCount == 2)
    }

    @Test @MainActor
    func disabledOldRequestCannotPublishLateResult() async {
        let fixture = SettingsFixture()
        fixture.settings.isEnabled = true
        let provider = ManualTranslationProvider()
        let service = makeService(fixture: fixture, provider: provider)
        let task = Task { await service.translate("A delayed room title") }
        await provider.waitForCallCount(1)

        fixture.settings.isEnabled = false
        await provider.resumeAll(returning: "过期译文")
        await task.value
        #expect(service.displayTitle(for: "A delayed room title") == "A delayed room title")
        #expect(service.lastErrorMessage == nil)
    }

    @Test @MainActor
    func testTranslationBypassesCacheUsesDifferentSourceAndRejectsStaleFailure() async throws {
        let fixture = SettingsFixture()
        fixture.settings.targetLanguage = "en"
        let recorder = RecordingTranslationProvider(result: "Test title")
        let service = makeService(fixture: fixture, provider: recorder)

        #expect(try await service.testTranslation() == "Test title")
        #expect(try await service.testTranslation() == "Test title")
        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.sourceLanguage == "zh-Hans" })
        #expect(requests.allSatisfy { $0.text == "这是一个测试直播标题" })

        let delayed = ManualTranslationProvider()
        let staleService = makeService(fixture: fixture, provider: delayed)
        let staleTask = Task { try await staleService.testTranslation() }
        await delayed.waitForCallCount(1)
        fixture.settings.targetLanguage = "fr"
        await delayed.resumeAll(throwing: RoomTranslationError.authentication)
        do {
            _ = try await staleTask.value
            Issue.record("A stale test request must not report success")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
        #expect(staleService.lastErrorMessage == nil)
    }

    @Test
    func coordinatorKeepsSharedFlightUntilLastConsumerCancels() async throws {
        let coordinator = TranslationWorkCoordinator(maximumConcurrent: 1)
        let probe = CancellationProbe()
        let key = translationKey(revision: 1)
        let first = try requireLease(try await coordinator.acquire(key: key) {
            try await probe.run()
        })
        let second = try requireLease(try await coordinator.acquire(key: key) {
            Issue.record("Duplicate operation must not start")
            return "duplicate"
        })
        await probe.waitUntilStarted()

        await coordinator.release(key: key, flightID: first.flightID, consumerID: first.consumerID)
        await Task.yield()
        #expect(!(await probe.wasCancelled))
        await coordinator.release(key: key, flightID: second.flightID, consumerID: second.consumerID)
        await probe.waitUntilCancelled()
        #expect(await probe.wasCancelled)
    }

    @Test
    func coordinatorRejectsLateCompletionFromRetiredFlight() async throws {
        let coordinator = TranslationWorkCoordinator(maximumConcurrent: 2)
        let oldProbe = ManualValueProbe()
        let key = translationKey(revision: 2)
        let old = try requireLease(try await coordinator.acquire(key: key) {
            await oldProbe.value()
        })
        await oldProbe.waitUntilStarted()
        await coordinator.release(key: key, flightID: old.flightID, consumerID: old.consumerID)

        let replacement = try requireLease(try await coordinator.acquire(key: key) { "new" })
        let replacementValue = try await replacement.task.value
        await coordinator.complete(key: key, flightID: replacement.flightID, value: replacementValue)
        await oldProbe.resume(returning: "old")
        let oldValue = try await old.task.value
        await coordinator.complete(key: key, flightID: old.flightID, value: oldValue)

        let cached = try await coordinator.acquire(key: key) { "unexpected" }
        switch cached {
        case let .cached(value): #expect(value == "new")
        case .lease: Issue.record("Replacement value should remain cached")
        }
    }

    @Test
    func chatCompletionParsingRejectsEmptyAndMalformedResponses() throws {
        let valid = Data(#"{"choices":[{"message":{"content":"  translated title  "}}]}"#.utf8)
        #expect(try OpenAICompatibleTranslationProvider.parseResponse(valid) == "translated title")
        for invalid in [
            Data(#"{"choices":[]}"#.utf8),
            Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8),
            Data("not-json".utf8)
        ] {
            #expect(throws: RoomTranslationError.invalidResponse) {
                try OpenAICompatibleTranslationProvider.parseResponse(invalid)
            }
        }
    }

    @Test
    func compatibleRequestPreservesBasePathAndMapsCredentialSafeErrors() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let provider = OpenAICompatibleTranslationProvider(
            session: URLSession(configuration: configuration)
        )
        let request = RoomTranslationRequest(
            text: "A neutral room title",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            baseURL: try #require(URL(string: "https://api.example.invalid/custom/base")),
            model: "fixture-model",
            apiKey: "fixture-secret"
        )

        TranslationURLProtocol.reset(statusCode: 200, body: #"{"choices":[{"message":{"content":"译文"}}]}"#)
        #expect(try await provider.translate(request) == "译文")
        let captured = TranslationURLProtocol.captured
        #expect(captured?.path == "/custom/base/chat/completions")
        #expect(captured?.authorization == "Bearer fixture-secret")
        #expect(captured?.cookie == nil)
        let body = try #require(captured?.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "fixture-model")
        #expect(json["stream"] as? Bool == false)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(messages.first?["content"]?.contains("room title") == true)
        #expect(messages.last?["content"] == "A neutral room title")

        let danmakuRequest = RoomTranslationRequest(
            text: "A neutral chat message",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            baseURL: request.baseURL,
            model: request.model,
            apiKey: request.apiKey,
            contentKind: .danmaku
        )
        TranslationURLProtocol.reset(statusCode: 200, body: #"{"choices":[{"message":{"content":"弹幕译文"}}]}"#)
        #expect(try await provider.translate(danmakuRequest) == "弹幕译文")
        let danmakuBody = try #require(TranslationURLProtocol.captured?.body)
        let danmakuJSON = try #require(JSONSerialization.jsonObject(with: danmakuBody) as? [String: Any])
        let danmakuMessages = try #require(danmakuJSON["messages"] as? [[String: String]])
        #expect(danmakuMessages.first?["content"]?.contains("live-chat message") == true)
        #expect(danmakuMessages.first?["content"]?.contains("room title") == false)
        #expect(danmakuMessages.last?["content"] == "A neutral chat message")

        for (status, expected) in [(401, RoomTranslationError.authentication), (429, .rateLimited)] {
            TranslationURLProtocol.reset(
                statusCode: status,
                body: #"{"error":"remote fixture-secret detail"}"#
            )
            do {
                _ = try await provider.translate(request)
                Issue.record("HTTP \(status) must fail")
            } catch let error as RoomTranslationError {
                #expect(error == expected)
                #expect(!error.localizedDescription.contains("fixture-secret"))
                #expect(!error.localizedDescription.contains("remote"))
                #expect(!error.localizedDescription.contains("api.example.invalid"))
            }
        }
    }

    @Test
    func hostOwnershipIgnoresRetiredGeneration() {
        var ownership = RoomTranslationHostOwnership()
        let owner = UUID()
        let first = UUID()
        let replacement = UUID()
        ownership.install(owner: owner, generation: first)
        ownership.install(owner: owner, generation: replacement)
        #expect(!ownership.isCurrent(owner: owner, generation: first))
        #expect(ownership.isCurrent(owner: owner, generation: replacement))
        ownership.remove(owner: owner)
        #expect(!ownership.isCurrent(owner: owner, generation: replacement))
    }

    @Test
    func nativeExecutionCanMoveToAnotherHostWithoutAcceptingRetiredResult() throws {
        var state = RoomTranslationNativeExecutionState()
        let departingOwner = UUID()
        let survivingOwner = UUID()
        let sharedRequest = UUID()
        let unrelatedRequest = UUID()
        let retiredExecution = state.assign(requestID: sharedRequest, owner: departingOwner)
        let unrelatedExecution = state.assign(requestID: unrelatedRequest, owner: survivingOwner)

        let retiredRequests = state.retire(owner: departingOwner)
        #expect(retiredRequests == [sharedRequest])
        #expect(!state.isCurrent(requestID: sharedRequest, executionID: retiredExecution))
        #expect(state.isCurrent(requestID: unrelatedRequest, executionID: unrelatedExecution))

        let replacementExecution = state.assign(requestID: sharedRequest, owner: survivingOwner)
        #expect(!state.isCurrent(requestID: sharedRequest, executionID: retiredExecution))
        #expect(state.isCurrent(requestID: sharedRequest, executionID: replacementExecution))
    }
}

@MainActor
private final class SettingsFixture {
    let defaults: UserDefaults
    let secrets = MemoryTranslationSecretStorage()
    let settings: RoomTranslationSettings

    init() {
        let suite = "RoomTitleTranslationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = RoomTranslationSettings(defaults: defaults, secretStorage: secrets)
    }
}

private final class MemoryTranslationSecretStorage: RoomTranslationSecretStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private struct FixedLanguageDetector: RoomTitleLanguageDetecting {
    let language: String?
    func sourceLanguage(for text: String) -> String? { language }
}

private actor RecordingTranslationProvider: RoomTranslationProvider {
    let result: String
    private(set) var requests: [RoomTranslationRequest] = []
    var callCount: Int { requests.count }

    init(result: String) { self.result = result }
    func translate(_ request: RoomTranslationRequest) async throws -> String {
        requests.append(request)
        return result
    }
}

private actor SlowTranslationProvider: RoomTranslationProvider {
    let result: String
    private(set) var callCount = 0
    init(result: String) { self.result = result }
    func translate(_ request: RoomTranslationRequest) async throws -> String {
        callCount += 1
        try await Task.sleep(for: .milliseconds(50))
        return result
    }
}

private actor CountingTranslationProvider: RoomTranslationProvider {
    private(set) var callCount = 0
    func translate(_ request: RoomTranslationRequest) async throws -> String {
        callCount += 1
        return "\(request.targetLanguage)-\(callCount)"
    }
}

private actor ManualTranslationProvider: RoomTranslationProvider {
    private var continuations: [CheckedContinuation<String, any Error>] = []
    private(set) var callCount = 0

    func translate(_ request: RoomTranslationRequest) async throws -> String {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func waitForCallCount(_ expected: Int) async {
        while callCount < expected { await Task.yield() }
    }

    func resumeAll(returning value: String) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume(returning: value) }
    }

    func resumeAll(throwing error: any Error) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: error) }
    }
}

private actor CancellationProbe {
    private(set) var started = false
    private(set) var wasCancelled = false

    func run() async throws -> String {
        started = true
        do {
            try await Task.sleep(for: .seconds(60))
            return "unexpected"
        } catch {
            wasCancelled = true
            throw error
        }
    }

    func waitUntilStarted() async { while !started { await Task.yield() } }
    func waitUntilCancelled() async { while !wasCancelled { await Task.yield() } }
}

private actor ManualValueProbe {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var started = false

    func value() async -> String {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async { while !started { await Task.yield() } }
    func resume(returning value: String) { continuation?.resume(returning: value); continuation = nil }
}

private final class TranslationURLProtocol: URLProtocol {
    struct Captured: Sendable {
        let path: String
        let authorization: String?
        let cookie: String?
        let body: Data?
    }

    private struct State: Sendable {
        var statusCode = 200
        var body = Data()
        var captured: Captured?
    }

    // URLSession invokes URLProtocol on arbitrary threads. Every fixture-state
    // access goes through this mutex, and the containing suite runs serialized.
    private static let state = Mutex(State())

    static var captured: Captured? {
        state.withLock { $0.captured }
    }

    static func reset(statusCode: Int, body: String) {
        state.withLock {
            $0.statusCode = statusCode
            $0.body = Data(body.utf8)
            $0.captured = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let snapshot = Self.state.withLock { state -> (Int, Data) in
            state.captured = Captured(
                path: url.path,
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                cookie: request.value(forHTTPHeaderField: "Cookie"),
                body: requestBody(request)
            )
            return (state.statusCode, state.body)
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: snapshot.0,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: snapshot.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else {
                return nil
            }
            guard count > 0 else {
                break
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

@MainActor
private func makeService(
    fixture: SettingsFixture,
    provider: any RoomTranslationProvider
) -> RoomTitleTranslationService {
    RoomTitleTranslationService(
        settings: fixture.settings,
        languageDetector: FixedLanguageDetector(language: "en"),
        appleProvider: provider,
        llmProvider: provider
    )
}

private func translationKey(revision: Int) -> RoomTranslationCacheKey {
    RoomTranslationCacheKey(
        original: "A neutral room title",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        engine: .apple,
        endpoint: "",
        model: "",
        configurationRevision: revision
    )
}

private func requireLease(_ acquisition: TranslationWorkCoordinator.Acquisition) throws -> TranslationWorkCoordinator.Lease {
    switch acquisition {
    case let .lease(lease): lease
    case .cached:
        throw RoomTranslationError.invalidResponse
    }
}
