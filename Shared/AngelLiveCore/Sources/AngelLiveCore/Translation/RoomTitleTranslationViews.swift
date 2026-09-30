import SwiftUI

#if !os(tvOS)
import Translation
#endif

public struct NativeTranslationLanguageDownloadRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let pair: NativeTranslationLanguagePair

    public init(id: UUID, pair: NativeTranslationLanguagePair) {
        self.id = id
        self.pair = pair
    }
}

public struct TranslatedRoomTitle: View {
    private let original: String
    private let service = RoomTitleTranslationService.shared

    public init(_ original: String) {
        self.original = original
    }

    public var body: some View {
        Text(service.displayTitle(for: original))
            .roomTitleTranslationTask(original)
    }
}

public extension View {
    @MainActor func roomTitleTranslationTask(
        _ original: String,
        enabled: Bool = true
    ) -> some View {
        modifier(RoomTitleTranslationTaskModifier(original: original, enabled: enabled))
    }

    @ViewBuilder
    @MainActor func roomTitleTranslationHost(enabled: Bool = true) -> some View {
#if os(tvOS)
        self
#else
        modifier(RoomTitleTranslationHostAvailabilityModifier(enabled: enabled))
#endif
    }

    @MainActor func nativeTranslationLanguageDownloadTask(
        _ request: NativeTranslationLanguageDownloadRequest?,
        onCompletion: @escaping @MainActor (
            NativeTranslationLanguageDownloadRequest,
            Result<Void, RoomTranslationError>
        ) async -> Void
    ) -> some View {
#if os(tvOS)
        modifier(NativeTranslationLanguageDownloadUnavailableModifier(
            request: request,
            onCompletion: onCompletion
        ))
#else
        modifier(NativeTranslationLanguageDownloadAvailabilityModifier(
            request: request,
            onCompletion: onCompletion
        ))
#endif
    }
}

private struct NativeTranslationLanguageDownloadUnavailableModifier: ViewModifier {
    let request: NativeTranslationLanguageDownloadRequest?
    let onCompletion: @MainActor (
        NativeTranslationLanguageDownloadRequest,
        Result<Void, RoomTranslationError>
    ) async -> Void

    func body(content: Content) -> some View {
        content.task(id: request?.id) {
            guard let request, !Task.isCancelled else { return }
            await onCompletion(request, .failure(.unavailable))
        }
    }
}

private struct RoomTitleTranslationTaskModifier: ViewModifier {
    let original: String
    let enabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    private let service = RoomTitleTranslationService.shared

    private var lifecycleEnabled: Bool {
        enabled && scenePhase != .background
    }

    func body(content: Content) -> some View {
        content.task(id: service.requestIdentity(for: original, lifecycleEnabled: lifecycleEnabled)) {
            guard lifecycleEnabled else { return }
            await service.translate(original)
        }
    }
}

#if !os(tvOS)
@available(iOS 18.0, macOS 15.0, *)
private nonisolated func nativeTranslationLanguageDownloadAction(
    request: NativeTranslationLanguageDownloadRequest?,
    isCurrent: @escaping @MainActor (NativeTranslationLanguageDownloadRequest) -> Bool,
    onCompletion: @escaping @MainActor (
        NativeTranslationLanguageDownloadRequest,
        Result<Void, RoomTranslationError>
    ) async -> Void
) -> (TranslationSession) async -> Void {
    { session in
        guard let request,
              !Task.isCancelled,
              await isCurrent(request) else {
            return
        }

        let result: Result<Void, RoomTranslationError>
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard await isCurrent(request) else { return }

            let status = await AppleRoomTranslationProvider.shared
                .nativeLanguageStatus(for: request.pair)
            try Task.checkCancellation()
            guard await isCurrent(request) else { return }
            result = status == .installed
                ? .success(())
                : .failure(.languageResourcesRequired)
        } catch is CancellationError {
            guard !Task.isCancelled, await isCurrent(request) else { return }
            result = .failure(.unavailable)
        } catch {
            guard !Task.isCancelled, await isCurrent(request) else { return }
            result = .failure(.unavailable)
        }

        guard !Task.isCancelled, await isCurrent(request) else { return }
        await onCompletion(request, result)
    }
}

private struct NativeTranslationLanguageDownloadAvailabilityModifier: ViewModifier {
    let request: NativeTranslationLanguageDownloadRequest?
    let onCompletion: @MainActor (
        NativeTranslationLanguageDownloadRequest,
        Result<Void, RoomTranslationError>
    ) async -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.modifier(NativeTranslationLanguageDownloadModifier(
                request: request,
                onCompletion: onCompletion
            ))
        } else {
            content.modifier(NativeTranslationLanguageDownloadUnavailableModifier(
                request: request,
                onCompletion: onCompletion
            ))
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct NativeTranslationLanguageDownloadModifier: ViewModifier {
    let request: NativeTranslationLanguageDownloadRequest?
    let onCompletion: @MainActor (
        NativeTranslationLanguageDownloadRequest,
        Result<Void, RoomTranslationError>
    ) async -> Void

    @State private var activeRequest: NativeTranslationLanguageDownloadRequest?
    @State private var configuration: TranslationSession.Configuration?

    init(
        request: NativeTranslationLanguageDownloadRequest?,
        onCompletion: @escaping @MainActor (
            NativeTranslationLanguageDownloadRequest,
            Result<Void, RoomTranslationError>
        ) async -> Void
    ) {
        self.request = request
        self.onCompletion = onCompletion
        _activeRequest = State(initialValue: request)
        _configuration = State(initialValue: request.map { Self.configuration(for: $0.pair) })
    }

    func body(content: Content) -> some View {
        let action = nativeTranslationLanguageDownloadAction(
            request: activeRequest,
            isCurrent: { activeRequest == $0 },
            onCompletion: onCompletion
        )
        content
            .background {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .translationTask(configuration, action: action)
                    .id(activeRequest?.id)
            }
            .onChange(of: request) { _, request in
                update(for: request)
            }
    }

    private func update(for request: NativeTranslationLanguageDownloadRequest?) {
        activeRequest = request
        configuration = request.map { Self.configuration(for: $0.pair) }
    }

    private static func configuration(
        for pair: NativeTranslationLanguagePair
    ) -> TranslationSession.Configuration {
        let source = Locale.Language(identifier: pair.sourceLanguage)
        let target = Locale.Language(identifier: pair.targetLanguage)
        if #available(iOS 26.4, macOS 26.4, *) {
            return TranslationSession.Configuration(
                source: source,
                target: target,
                preferredStrategy: .lowLatency
            )
        }
        return TranslationSession.Configuration(source: source, target: target)
    }
}

@available(iOS 18.0, macOS 15.0, *)
private nonisolated func roomTranslationHostAction(
    owner: UUID,
    sourceLanguage: String,
    targetLanguage: String
) -> (TranslationSession) async -> Void {
    AppleRoomTranslationProvider.hostAction(
        owner: owner,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage
    )
}

private struct RoomTitleTranslationHostAvailabilityModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.modifier(RoomTitleTranslationHostModifier(enabled: enabled))
        } else {
            content
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct RoomTitleTranslationHostModifier: ViewModifier {
    let enabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var owner = UUID()
    private let settings = RoomTranslationSettings.shared
    private let provider = AppleRoomTranslationProvider.shared

    private var isActive: Bool {
        enabled && scenePhase != .background && settings.engine == .apple
    }

    private var sourceLanguage: String? {
        provider.preferredSourceLanguage(targetLanguage: settings.targetLanguage)
    }

    private var configuration: TranslationSession.Configuration? {
        guard isActive, let sourceLanguage else { return nil }
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: settings.targetLanguage)
        if #available(iOS 26.4, macOS 26.4, *) {
            return TranslationSession.Configuration(
                source: source,
                target: target,
                preferredStrategy: .lowLatency
            )
        }
        return TranslationSession.Configuration(source: source, target: target)
    }

    func body(content: Content) -> some View {
        let capturedSourceLanguage = sourceLanguage
        let capturedTargetLanguage = settings.targetLanguage
        let capturedConfiguration = configuration
        let action: (TranslationSession) async -> Void = capturedSourceLanguage.map {
            roomTranslationHostAction(
                owner: owner,
                sourceLanguage: $0,
                targetLanguage: capturedTargetLanguage
            )
        } ?? { _ in }
        content
            .translationTask(capturedConfiguration, action: action)
            .onAppear {
                provider.setHostExpected(owner: owner, expected: isActive)
            }
            .onChange(of: isActive) { _, active in
                provider.setHostExpected(owner: owner, expected: active)
            }
            .onDisappear {
                provider.setHostExpected(owner: owner, expected: false)
            }
    }
}
#endif
