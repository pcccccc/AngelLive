import SwiftUI

public extension View {
    /// FullUI owns the opt-in recording lifecycle; ShellUI never enables it.
    func supportDiagnosticsHost(enabled: Bool) -> some View {
        modifier(SupportDiagnosticsHostModifier(enabled: enabled))
    }
}

private struct SupportDiagnosticsHostModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .supportDiagnosticsEnabled(enabled)
            .onChange(of: enabled) { _, enabled in
                if !enabled, SupportDiagnosticsService.shared.isRecording {
                    SupportDiagnosticsService.shared.stopRecording()
                }
            }
            .onChange(of: scenePhase) { previous, current in
                guard enabled else { return }
                if current == .background {
                    SupportDiagnosticsService.shared.recordAction(.enteredBackground)
                } else if current == .active, previous != .active {
                    SupportDiagnosticsService.shared.recordAction(.returnedForeground)
                }
            }
    }
}
