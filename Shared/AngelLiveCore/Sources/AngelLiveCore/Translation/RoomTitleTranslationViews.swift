import SwiftUI

#if !os(tvOS)
import Translation
#endif

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
        return TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguage),
            target: Locale.Language(identifier: settings.targetLanguage)
        )
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
