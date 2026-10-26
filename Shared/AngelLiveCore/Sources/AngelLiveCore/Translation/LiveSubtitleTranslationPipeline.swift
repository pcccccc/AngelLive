import Foundation
import Observation

@MainActor @Observable
public final class LiveSubtitleTranslationPipeline {
    public private(set) var text = ""
    public private(set) var lastError: RoomTranslationError?
    public var errorMessage: String? { lastError?.recoveryMessage(for: settings.engine) }

    @ObservationIgnored private let settings: RoomTranslationSettings
    @ObservationIgnored private let appleProvider: any RoomTranslationProvider
    @ObservationIgnored private let llmProvider: any RoomTranslationProvider
    @ObservationIgnored private let minimumRequestInterval: Duration

    @ObservationIgnored private var observedRevision: Int
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var currentSegmentID: String?
    @ObservationIgnored private var activeInput: Input?
    @ObservationIgnored private var pendingInput: Input?
    @ObservationIgnored private var lastProcessedInput: Input?
    @ObservationIgnored private var activeExecutionID: UUID?
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var lastRequestInstant: ContinuousClock.Instant?

    public convenience init() {
        self.init(
            settings: .shared,
            appleProvider: liveAppleRoomTranslationProvider(),
            llmProvider: OpenAICompatibleTranslationProvider.live()
        )
    }

    init(
        settings: RoomTranslationSettings,
        appleProvider: any RoomTranslationProvider,
        llmProvider: any RoomTranslationProvider,
        minimumRequestInterval: Duration = .milliseconds(600)
    ) {
        self.settings = settings
        self.appleProvider = appleProvider
        self.llmProvider = llmProvider
        self.minimumRequestInterval = max(minimumRequestInterval, .zero)
        observedRevision = settings.revision
        observeConfigurationRevision()
    }

    public func enqueue(
        _ original: String,
        sourceLanguage: String,
        segmentID: String
    ) {
        reconcileConfigurationRevision()

        let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOriginal.isEmpty, !segmentID.isEmpty else { return }

        if currentSegmentID != segmentID {
            invalidateWork(keepingSegmentID: segmentID)
        }

        let input = Input(
            original: normalizedOriginal,
            sourceLanguage: sourceLanguage,
            segmentID: segmentID,
            configurationRevision: observedRevision
        )
        guard input != activeInput,
              input != pendingInput,
              input != lastProcessedInput else {
            return
        }

        pendingInput = input
        startNextIfNeeded()
    }

    public func reset() {
        invalidateWork(keepingSegmentID: nil)
    }

    /// Checks local prerequisites without sending recognized text or testing
    /// the service. Same-language captions never need a translation engine.
    public func availabilityError(sourceLanguage: String) -> RoomTranslationError? {
        if roomTranslationLanguagesMatch(sourceLanguage, settings.targetLanguage) {
            return nil
        }
        guard normalizedSourceLanguage(sourceLanguage) != nil else {
            return .unsupportedSourceLanguage
        }
        return settings.availabilityError
    }

    private func startNextIfNeeded() {
        guard activeExecutionID == nil, let input = pendingInput else { return }
        pendingInput = nil

        guard input.configurationRevision == settings.revision,
              input.segmentID == currentSegmentID else {
            startNextIfNeeded()
            return
        }

        switch preparation(for: input) {
        case let .passthrough(original):
            lastProcessedInput = input
            text = original
            lastError = nil
            startNextIfNeeded()
        case .unsupported:
            lastProcessedInput = input
            text = ""
            lastError = .unsupportedSourceLanguage
            startNextIfNeeded()
        case let .failure(error):
            lastProcessedInput = input
            text = ""
            lastError = error
            startNextIfNeeded()
        case let .request(request, provider):
            let executionID = UUID()
            let executionGeneration = generation
            activeInput = input
            activeExecutionID = executionID
            activeTask = Task { [weak self] in
                guard let self else { return }
                await self.perform(
                    request: request,
                    provider: provider,
                    input: input,
                    executionID: executionID,
                    generation: executionGeneration
                )
            }
        }
    }

    private func preparation(for input: Input) -> Preparation {
        let targetLanguage = settings.targetLanguage
        if roomTranslationLanguagesMatch(input.sourceLanguage, targetLanguage) {
            return .passthrough(input.original)
        }
        guard let sourceLanguage = normalizedSourceLanguage(input.sourceLanguage) else {
            return .unsupported
        }

        let request: RoomTranslationRequest
        if settings.engine == .llm {
            do {
                let cloud = try settings.cloudConfiguration()
                request = RoomTranslationRequest(
                    text: input.original,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    baseURL: cloud.baseURL,
                    model: cloud.model,
                    apiKey: cloud.apiKey,
                    contentKind: .subtitle,
                    purpose: .automatic
                )
            } catch let error as RoomTranslationError {
                return .failure(error)
            } catch {
                return .failure(.serviceUnavailable)
            }
            return .request(request, llmProvider)
        }

        request = RoomTranslationRequest(
            text: input.original,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            baseURL: nil,
            model: nil,
            apiKey: nil,
            contentKind: .subtitle,
            purpose: .automatic
        )
        return .request(request, appleProvider)
    }

    private func perform(
        request: RoomTranslationRequest,
        provider: any RoomTranslationProvider,
        input: Input,
        executionID: UUID,
        generation executionGeneration: UInt
    ) async {
        do {
            try await waitForRequestInterval()
            try Task.checkCancellation()
            guard isCurrent(
                input: input,
                executionID: executionID,
                generation: executionGeneration
            ) else {
                return
            }
            lastRequestInstant = .now

            let translated = try await provider.translate(request)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else { throw RoomTranslationError.invalidResponse }
            try Task.checkCancellation()
            complete(
                .success(translated),
                input: input,
                executionID: executionID,
                generation: executionGeneration
            )
        } catch is CancellationError {
            completeCancellation(
                input: input,
                executionID: executionID,
                generation: executionGeneration
            )
        } catch let error as RoomTranslationError {
            complete(
                .failure(error),
                input: input,
                executionID: executionID,
                generation: executionGeneration
            )
        } catch {
            complete(
                .failure(.serviceUnavailable),
                input: input,
                executionID: executionID,
                generation: executionGeneration
            )
        }
    }

    private func waitForRequestInterval() async throws {
        guard let lastRequestInstant else { return }
        let elapsed = lastRequestInstant.duration(to: .now)
        guard elapsed < minimumRequestInterval else { return }
        try await Task.sleep(for: minimumRequestInterval - elapsed)
    }

    private func complete(
        _ result: Result<String, RoomTranslationError>,
        input: Input,
        executionID: UUID,
        generation executionGeneration: UInt
    ) {
        guard isCurrent(
            input: input,
            executionID: executionID,
            generation: executionGeneration
        ) else {
            return
        }

        activeTask = nil
        activeExecutionID = nil
        activeInput = nil
        lastProcessedInput = input
        switch result {
        case let .success(translated):
            text = translated
            lastError = nil
        case let .failure(error):
            text = ""
            lastError = error
        }
        startNextIfNeeded()
    }

    private func completeCancellation(
        input: Input,
        executionID: UUID,
        generation executionGeneration: UInt
    ) {
        guard isCurrent(
            input: input,
            executionID: executionID,
            generation: executionGeneration
        ) else {
            return
        }
        activeTask = nil
        activeExecutionID = nil
        activeInput = nil
        startNextIfNeeded()
    }

    private func isCurrent(
        input: Input,
        executionID: UUID,
        generation executionGeneration: UInt
    ) -> Bool {
        generation == executionGeneration
            && activeExecutionID == executionID
            && activeInput == input
            && currentSegmentID == input.segmentID
            && settings.revision == input.configurationRevision
    }

    private func invalidateWork(keepingSegmentID segmentID: String?) {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
        activeExecutionID = nil
        activeInput = nil
        pendingInput = nil
        lastProcessedInput = nil
        currentSegmentID = segmentID
        text = ""
        lastError = nil
    }

    private func reconcileConfigurationRevision() {
        guard observedRevision != settings.revision else { return }
        observedRevision = settings.revision
        invalidateWork(keepingSegmentID: currentSegmentID)
    }

    private func observeConfigurationRevision() {
        withObservationTracking {
            _ = settings.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reconcileConfigurationRevision()
                self.observeConfigurationRevision()
            }
        }
    }

    private func normalizedSourceLanguage(_ identifier: String) -> String? {
        let baseLanguage = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased()
        // The audio detector and Speech supply language identifiers. Let the
        // selected translation service check its actual language coverage.
        guard let baseLanguage,
              (2...3).contains(baseLanguage.utf8.count),
              baseLanguage.utf8.allSatisfy({ (97...122).contains($0) }),
              !["und", "mul"].contains(baseLanguage) else {
            return nil
        }
        if baseLanguage == "zh" {
            let language = Locale.Language(identifier: identifier)
            if let script = language.script?.identifier, ["Hans", "Hant"].contains(script) {
                return "zh-\(script)"
            }
        }
        return baseLanguage
    }
}

private extension LiveSubtitleTranslationPipeline {
    struct Input: Equatable, Sendable {
        let original: String
        let sourceLanguage: String
        let segmentID: String
        let configurationRevision: Int
    }

    enum Preparation {
        case passthrough(String)
        case unsupported
        case failure(RoomTranslationError)
        case request(RoomTranslationRequest, any RoomTranslationProvider)
    }
}
