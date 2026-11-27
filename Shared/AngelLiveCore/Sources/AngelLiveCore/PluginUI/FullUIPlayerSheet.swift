import SwiftUI

extension EnvironmentValues {
    /// Enabled only by the iOS FullUI room player. Nested sheets inherit the presentation style.
    @Entry public var usesFullUIPlayerSheets = false
}

#if os(iOS)
private var playerSheetBackground: Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 28.0 / 255, alpha: 1)
            : .systemGroupedBackground
    })
}

extension View {
    public func playerSheetSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(playerSheetBackground.ignoresSafeArea())
            .presentationBackground(playerSheetBackground)
            .presentationDragIndicator(.visible)
    }
}

private struct PlayerSheetDetents: ViewModifier {
    let initial: PresentationDetent
    let externalSelection: Binding<PresentationDetent>?
    @State private var selected: PresentationDetent

    init(initial: PresentationDetent, selection: Binding<PresentationDetent>?) {
        self.initial = initial
        externalSelection = selection
        _selected = State(initialValue: initial)
    }

    func body(content: Content) -> some View {
        content.presentationDetents([initial, .large], selection: externalSelection ?? $selected)
    }
}

extension View {
    /// Set on the sheet root so navigation and scrolling never replace its detents.
    public func playerSheetDetents(
        initial: PresentationDetent, selection: Binding<PresentationDetent>? = nil
    ) -> some View {
        modifier(PlayerSheetDetents(initial: initial, selection: selection))
    }
}

private struct PlayerSheetAppearance: ViewModifier {
    @Environment(\.usesFullUIPlayerSheets) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityHidden(false)
                .preferredColorScheme(.dark)
                .presentationBackground(playerSheetBackground)
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

private struct PlayerSheetCloseButton: View {
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}

extension View {
    /// Apply to the destination inside the sheet's NavigationStack.
    public func playerSheetNavigation(_ title: Text, closeDisabled: Bool = false, close: @escaping () -> Void) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        PlayerSheetCloseButton(close: close).disabled(closeDisabled)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        PlayerSheetCloseButton(close: close).disabled(closeDisabled)
                    }
                }
            }
            .modifier(PlayerSheetAppearance())
    }
}
#endif

private struct PlayerSheetNavigationWhenPresented: ViewModifier {
    let title: Text
    let closeDisabled: Bool
    @Environment(\.usesFullUIPlayerSheets) private var enabled
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            content.playerSheetNavigation(title, closeDisabled: closeDisabled) { dismiss() }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Apply to the root content inside a shared sheet's navigation stack.
    public func playerSheetNavigationWhenPresented(_ title: Text, closeDisabled: Bool = false) -> some View {
        modifier(PlayerSheetNavigationWhenPresented(title: title, closeDisabled: closeDisabled))
    }
}
