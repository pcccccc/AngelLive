import SwiftUI

extension EnvironmentValues {
    /// Opted into by the macOS FullUI sheet host, never by a shared view itself.
    @Entry public var usesMacSettingsPresentation = false
    #if os(macOS)
    @Entry var macSettingsCloseSheet: (@MainActor () -> Void)? = nil
    #endif
}

#if os(macOS)
private struct MacSettingsSheetPresentation: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesMacSettingsPresentation) private var enabled
    let inheriting: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !inheriting || enabled {
            content
                .environment(\.usesMacSettingsPresentation, true)
                .environment(\.macSettingsCloseSheet, { dismiss() })
        } else {
            content
        }
    }
}

private struct MacSettingsPageModifier<Actions: View>: ViewModifier {
    @Environment(\.usesMacSettingsPresentation) private var enabled
    @Environment(\.macSettingsCloseSheet) private var closeSheet
    @Environment(\.dismiss) private var dismiss
    let title: String
    let showsBackButton: Bool
    let closeTitle: String
    let closeDisabled: Bool
    let placesActionsAfterClose: Bool
    let actions: Actions

    func body(content: Content) -> some View {
        if enabled {
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                content
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                HStack(spacing: 12) {
                    if showsBackButton {
                        Button("返回", systemImage: "chevron.left") { dismiss() }
                            .keyboardShortcut("[", modifiers: .command)
                    }
                    Spacer(minLength: 12)
                    if !placesActionsAfterClose { actions }
                    Button(closeTitle) {
                        if let closeSheet { closeSheet() } else { dismiss() }
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(closeDisabled)
                    if placesActionsAfterClose { actions }
                }
                .controlSize(.regular)
                .labelStyle(.titleAndIcon)
                .padding(.leading, showsBackButton ? 30 : 20)
                .padding(.trailing, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbarVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}
#endif

public extension View {
    /// Apply at a FullUI sheet boundary, outside its NavigationStack. Each nested
    /// sheet establishes its own close action; pushed pages retain the root action.
    @ViewBuilder
    func macSettingsSheetPresentation(inheriting: Bool = false) -> some View {
        #if os(macOS)
        modifier(MacSettingsSheetPresentation(inheriting: inheriting))
        #else
        self
        #endif
    }

    func macSettingsPage(
        _ title: String,
        showsBackButton: Bool = false,
        closeTitle: String = "关闭",
        closeDisabled: Bool = false
    ) -> some View {
        macSettingsPage(title, showsBackButton: showsBackButton,
                        closeTitle: closeTitle, closeDisabled: closeDisabled) { EmptyView() }
    }

    @ViewBuilder
    func macSettingsPage<Actions: View>(
        _ title: String,
        showsBackButton: Bool = false,
        closeTitle: String = "关闭",
        closeDisabled: Bool = false,
        placesActionsAfterClose: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        #if os(macOS)
        modifier(MacSettingsPageModifier(title: title, showsBackButton: showsBackButton,
                                        closeTitle: closeTitle, closeDisabled: closeDisabled,
                                        placesActionsAfterClose: placesActionsAfterClose,
                                        actions: actions()))
        #else
        self
        #endif
    }
}
