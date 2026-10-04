import Foundation

actor DanmakuTranslationBroker {
    static let shared = DanmakuTranslationBroker()

    private struct Consumer {
        let continuation: CheckedContinuation<String, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private struct Flight {
        let id: UUID
        var task: Task<Void, Never>?
        var consumers: [UUID: Consumer]
        var acceptsConsumers: Bool
    }

    private enum Completion: Sendable {
        case success(String)
        case failure(RoomTranslationError)
        case cancelled
    }

    private let cacheCapacity: Int
    private let nativeMaximumConcurrent: Int
    private let cloudMaximumConcurrent: Int
    private let cloudMinimumRequestInterval: Duration
    private let timeoutSleep: @Sendable (Duration) async throws -> Void
    private let clock = ContinuousClock()
    private var cache: [RoomTranslationCacheKey: String] = [:]
    private var cacheOrder: [RoomTranslationCacheKey] = []
    private var flights: [RoomTranslationCacheKey: Flight] = [:]
    private var lastCloudProviderStart: ContinuousClock.Instant?
    private var nativeSuppressedFailure: (revision: Int, error: RoomTranslationError)?
    private var cloudSuppressedFailure: (revision: Int, error: RoomTranslationError)?

    init(
        cacheCapacity: Int = 200,
        nativeMaximumConcurrent: Int = 64,
        cloudMaximumConcurrent: Int = 2,
        cloudMinimumRequestInterval: Duration = .seconds(1),
        timeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.cacheCapacity = max(1, cacheCapacity)
        self.nativeMaximumConcurrent = max(1, nativeMaximumConcurrent)
        self.cloudMaximumConcurrent = max(1, cloudMaximumConcurrent)
        self.cloudMinimumRequestInterval = cloudMinimumRequestInterval
        self.timeoutSleep = timeoutSleep
    }

    func translate(
        key: RoomTranslationCacheKey,
        request: RoomTranslationRequest,
        provider: any RoomTranslationProvider,
        timeout: Duration
    ) async throws -> String {
        let consumerID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                register(
                    consumerID: consumerID,
                    key: key,
                    request: request,
                    provider: provider,
                    timeout: timeout,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancel(consumerID: consumerID, key: key) }
        }
    }

    func prepareForExplicitRetry(revision: Int) {
        if nativeSuppressedFailure?.revision == revision {
            nativeSuppressedFailure = nil
        }
        if cloudSuppressedFailure?.revision == revision {
            cloudSuppressedFailure = nil
        }
    }

    private func register(
        consumerID: UUID,
        key: RoomTranslationCacheKey,
        request: RoomTranslationRequest,
        provider: any RoomTranslationProvider,
        timeout: Duration,
        continuation: CheckedContinuation<String, any Error>
    ) {
        if let cached = cache[key] {
            touch(key)
            continuation.resume(returning: cached)
            return
        }

        if var flight = flights[key] {
            guard flight.acceptsConsumers else {
                continuation.resume(throwing: RoomTranslationError.busy)
                return
            }
            flight.consumers[consumerID] = makeConsumer(
                id: consumerID,
                key: key,
                timeout: timeout,
                continuation: continuation
            )
            flights[key] = flight
            return
        }

        if let suppressedFailure = suppressedFailure(for: key.engine),
           suppressedFailure.revision == key.configurationRevision {
            continuation.resume(throwing: suppressedFailure.error)
            return
        }
        guard activeFlightCount(for: key.engine) < maximumConcurrent(for: key.engine) else {
            continuation.resume(throwing: RoomTranslationError.busy)
            return
        }

        let now = clock.now
        if key.engine == .llm {
            if let lastCloudProviderStart,
               lastCloudProviderStart.duration(to: now) < cloudMinimumRequestInterval {
                continuation.resume(throwing: RoomTranslationError.rateLimited)
                return
            }
            lastCloudProviderStart = now
        }

        let flightID = UUID()
        let consumer = makeConsumer(
            id: consumerID,
            key: key,
            timeout: timeout,
            continuation: continuation
        )
        flights[key] = Flight(
            id: flightID,
            task: nil,
            consumers: [consumerID: consumer],
            acceptsConsumers: true
        )
        let task = Task { [provider] in
            let completion: Completion
            do {
                let value = try await provider.translate(request)
                completion = Task.isCancelled ? .cancelled : .success(value)
            } catch is CancellationError {
                completion = .cancelled
            } catch let error as RoomTranslationError {
                completion = .failure(error)
            } catch {
                completion = Task.isCancelled ? .cancelled : .failure(.serviceUnavailable)
            }
            self.finish(key: key, flightID: flightID, completion: completion)
        }
        flights[key]?.task = task
    }

    private func makeConsumer(
        id: UUID,
        key: RoomTranslationCacheKey,
        timeout: Duration,
        continuation: CheckedContinuation<String, any Error>
    ) -> Consumer {
        let timeoutSleep = timeoutSleep
        let timeoutTask = Task {
            do {
                try await timeoutSleep(timeout)
                self.timeout(consumerID: id, key: key)
            } catch {
                // Completion or caller cancellation owns the continuation.
            }
        }
        return Consumer(continuation: continuation, timeoutTask: timeoutTask)
    }

    private func timeout(consumerID: UUID, key: RoomTranslationCacheKey) {
        guard var flight = flights[key],
              let consumer = flight.consumers.removeValue(forKey: consumerID) else {
            return
        }
        flights[key] = flight
        consumer.continuation.resume(throwing: RoomTranslationError.serviceUnavailable)
        retireIfUnobserved(key: key)
    }

    private func cancel(consumerID: UUID, key: RoomTranslationCacheKey) {
        guard var flight = flights[key],
              let consumer = flight.consumers.removeValue(forKey: consumerID) else {
            return
        }
        flights[key] = flight
        consumer.timeoutTask.cancel()
        consumer.continuation.resume(throwing: CancellationError())
        retireIfUnobserved(key: key)
    }

    private func finish(
        key: RoomTranslationCacheKey,
        flightID: UUID,
        completion: Completion
    ) {
        guard let flight = flights[key], flight.id == flightID else { return }
        flights.removeValue(forKey: key)
        guard flight.acceptsConsumers else { return }

        let result: Result<String, any Error>
        switch completion {
        case .success(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                result = .failure(RoomTranslationError.invalidResponse)
            } else {
                cache[key] = normalized
                touch(key)
                trimCacheIfNeeded()
                result = .success(normalized)
            }
        case .failure(let error):
            if error == .authentication || error == .rateLimited {
                setSuppressedFailure(
                    (key.configurationRevision, error),
                    for: key.engine
                )
            }
            result = .failure(error)
        case .cancelled:
            result = .failure(CancellationError())
        }

        for consumer in flight.consumers.values {
            consumer.timeoutTask.cancel()
            consumer.continuation.resume(with: result)
        }
    }

    private func retireIfUnobserved(key: RoomTranslationCacheKey) {
        guard var flight = flights[key], flight.consumers.isEmpty else { return }
        flight.acceptsConsumers = false
        flight.task?.cancel()
        flights[key] = flight
    }

    private func activeFlightCount(for engine: RoomTranslationEngine) -> Int {
        flights.keys.reduce(into: 0) { count, key in
            if key.engine == engine { count += 1 }
        }
    }

    private func maximumConcurrent(for engine: RoomTranslationEngine) -> Int {
        switch engine {
        case .apple: nativeMaximumConcurrent
        case .llm: cloudMaximumConcurrent
        }
    }

    private func suppressedFailure(
        for engine: RoomTranslationEngine
    ) -> (revision: Int, error: RoomTranslationError)? {
        switch engine {
        case .apple: nativeSuppressedFailure
        case .llm: cloudSuppressedFailure
        }
    }

    private func setSuppressedFailure(
        _ failure: (revision: Int, error: RoomTranslationError),
        for engine: RoomTranslationEngine
    ) {
        switch engine {
        case .apple: nativeSuppressedFailure = failure
        case .llm: cloudSuppressedFailure = failure
        }
    }

    private func touch(_ key: RoomTranslationCacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func trimCacheIfNeeded() {
        while cacheOrder.count > cacheCapacity, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}

@MainActor
public final class DanmakuTranslationPipeline {
    private struct TranslationPlan: Sendable {
        let message: DanmakuDisplayMessage
        let segments: [SegmentPlan]
        let engine: RoomTranslationEngine
        let targetLanguage: String
        let endpoint: String
        let model: String
        let baseURL: URL?
        let apiKey: String?
        let revision: Int
        let provider: any RoomTranslationProvider
    }

    private enum SegmentPlan: Sendable {
        case unchanged(DanmakuDisplaySegment)
        case translate(text: String, sourceLanguage: String)
    }

    private struct Pending {
        let original: DanmakuDisplayMessage
        let revision: Int
        let generation: Int
        let deliver: @MainActor (DanmakuDisplayMessage) -> Void
        var result: DanmakuDisplayMessage?
        var task: Task<Void, Never>?
    }

    private let settings: RoomTranslationSettings
    private let languageDetector: any RoomTitleLanguageDetecting
    private let appleProvider: any RoomTranslationProvider
    private let llmProvider: any RoomTranslationProvider
    private let broker: DanmakuTranslationBroker
    private let maximumPending: Int
    private let messageTimeout: Duration
    private let clock = ContinuousClock()
    private var generation = 0
    private var nextSequence = 0
    private var order: [Int] = []
    private var pending: [Int: Pending] = [:]
    private var observedRevision: Int

    public convenience init() {
        self.init(
            settings: .shared,
            languageDetector: NaturalDanmakuLanguageDetector(),
            appleProvider: liveAppleRoomTranslationProvider(),
            llmProvider: OpenAICompatibleTranslationProvider.live(),
            broker: .shared
        )
    }

    init(
        settings: RoomTranslationSettings,
        languageDetector: any RoomTitleLanguageDetecting,
        appleProvider: any RoomTranslationProvider,
        llmProvider: any RoomTranslationProvider,
        broker: DanmakuTranslationBroker,
        maximumPending: Int = 128,
        messageTimeout: Duration = .seconds(3)
    ) {
        self.settings = settings
        self.languageDetector = languageDetector
        self.appleProvider = appleProvider
        self.llmProvider = llmProvider
        self.broker = broker
        self.maximumPending = max(1, maximumPending)
        self.messageTimeout = messageTimeout
        observedRevision = settings.revision
    }

    public func enqueue(
        _ message: DanmakuDisplayMessage,
        deliver: @escaping @MainActor (DanmakuDisplayMessage) -> Void
    ) {
        reconcileConfiguration()
        makeRoomForNextMessage()

        let sequence = nextSequence
        nextSequence &+= 1
        let currentGeneration = generation
        let revision = settings.revision

        guard settings.isDanmakuEnabled,
              let plan = makePlan(message: message, revision: revision),
              plan.segments.contains(where: { segment in
                  if case .translate = segment { return true }
                  return false
              }) else {
            pending[sequence] = Pending(
                original: message,
                revision: revision,
                generation: currentGeneration,
                deliver: deliver,
                result: message,
                task: nil
            )
            order.append(sequence)
            drain()
            return
        }

        pending[sequence] = Pending(
            original: message,
            revision: revision,
            generation: currentGeneration,
            deliver: deliver,
            result: nil,
            task: nil
        )
        order.append(sequence)

        let broker = broker
        let timeout = messageTimeout
        let clock = clock
        let task = Task { [weak self] in
            let result: DanmakuDisplayMessage
            do {
                result = try await Self.translate(plan, broker: broker, timeout: timeout, clock: clock)
            } catch {
                result = message
            }
            guard !Task.isCancelled else { return }
            self?.complete(
                sequence: sequence,
                generation: currentGeneration,
                revision: revision,
                result: result
            )
        }
        pending[sequence]?.task = task
    }

    public func reset() {
        generation &+= 1
        for item in pending.values { item.task?.cancel() }
        pending.removeAll()
        order.removeAll()
        observedRevision = settings.revision
    }

    private func makePlan(message: DanmakuDisplayMessage, revision: Int) -> TranslationPlan? {
        let engine = settings.engine
        let target = settings.targetLanguage
        let segments = message.segments.map { segment -> SegmentPlan in
            guard case .text(let text) = segment,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let source = languageDetector.sourceLanguage(for: text),
                  RoomTranslationLanguageCatalog.supportsAutomaticTranslation(from: source),
                  !roomTranslationLanguagesMatch(source, target) else {
                return .unchanged(segment)
            }
            return .translate(text: text, sourceLanguage: source)
        }
        guard segments.contains(where: { segment in
            if case .translate = segment { return true }
            return false
        }) else { return nil }

        let endpoint: String
        let model: String
        let baseURL: URL?
        let apiKey: String?
        let provider: any RoomTranslationProvider

        if engine == .llm {
            guard let cloud = try? settings.cloudConfiguration() else { return nil }
            endpoint = settings.cloudBaseURL
            model = cloud.model
            baseURL = cloud.baseURL
            apiKey = cloud.apiKey
            provider = llmProvider
        } else {
            endpoint = ""
            model = ""
            baseURL = nil
            apiKey = nil
            provider = appleProvider
        }

        return TranslationPlan(
            message: message,
            segments: segments,
            engine: engine,
            targetLanguage: target,
            endpoint: endpoint,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            revision: revision,
            provider: provider
        )
    }

    private static func translate(
        _ plan: TranslationPlan,
        broker: DanmakuTranslationBroker,
        timeout: Duration,
        clock: ContinuousClock
    ) async throws -> DanmakuDisplayMessage {
        let deadline = clock.now.advanced(by: timeout)
        var translatedSegments: [DanmakuDisplaySegment] = []
        translatedSegments.reserveCapacity(plan.segments.count)

        for segment in plan.segments {
            try Task.checkCancellation()
            switch segment {
            case .unchanged(let original):
                translatedSegments.append(original)
            case .translate(let text, let sourceLanguage):
                let remaining = clock.now.duration(to: deadline)
                guard remaining > .zero else {
                    translatedSegments.append(.text(text))
                    continue
                }
                let key = RoomTranslationCacheKey(
                    original: text,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: plan.targetLanguage,
                    engine: plan.engine,
                    endpoint: plan.endpoint,
                    model: plan.model,
                    configurationRevision: plan.revision,
                    contentKind: .danmaku
                )
                let request = RoomTranslationRequest(
                    text: text,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: plan.targetLanguage,
                    baseURL: plan.baseURL,
                    model: plan.model.isEmpty ? nil : plan.model,
                    apiKey: plan.apiKey,
                    contentKind: .danmaku
                )
                do {
                    let value = try await broker.translate(
                        key: key,
                        request: request,
                        provider: plan.provider,
                        timeout: remaining
                    )
                    translatedSegments.append(.text(value))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    translatedSegments.append(.text(text))
                }
            }
        }

        let fallback = readableText(from: translatedSegments, original: plan.message.text)
        return DanmakuDisplayMessage(
            text: fallback,
            nickname: plan.message.nickname,
            color: plan.message.color,
            segments: translatedSegments
        )
    }

    private static func readableText(
        from segments: [DanmakuDisplaySegment],
        original: String
    ) -> String {
        let value = segments.map { segment in
            switch segment {
            case .text(let text): text
            case .image(let image): image.altText ?? ""
            }
        }.joined()
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original : value
    }

    private func complete(
        sequence: Int,
        generation: Int,
        revision: Int,
        result: DanmakuDisplayMessage
    ) {
        guard var item = pending[sequence], item.generation == generation else { return }
        item.task = nil
        if settings.revision == revision, settings.isDanmakuEnabled {
            item.result = result
        } else {
            item.result = item.original
        }
        pending[sequence] = item
        drain()
    }

    private func reconcileConfiguration() {
        guard observedRevision != settings.revision else { return }
        observedRevision = settings.revision
        for sequence in order {
            guard var item = pending[sequence], item.result == nil else { continue }
            item.task?.cancel()
            item.task = nil
            item.result = item.original
            pending[sequence] = item
        }
        drain()
    }

    private func makeRoomForNextMessage() {
        while order.count >= maximumPending, let oldest = order.first {
            guard var item = pending[oldest] else {
                order.removeFirst()
                continue
            }
            item.task?.cancel()
            item.task = nil
            item.result = item.original
            pending[oldest] = item
            drain()
        }
    }

    private func drain() {
        while let sequence = order.first,
              let item = pending[sequence],
              let result = item.result {
            order.removeFirst()
            pending.removeValue(forKey: sequence)
            item.task?.cancel()
            if item.revision == settings.revision {
                item.deliver(result)
            } else {
                item.deliver(item.original)
            }
        }
    }
}
