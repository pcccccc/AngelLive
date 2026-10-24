#if DEBUG
import SwiftUI
import AngelLiveCore

/// Resolves the isolated scenario before any production scene or delegate services are created.
@MainActor
enum MacUITestBootstrap {
    static let context: UITestHistoryContext? = {
        do {
            guard let configuration = try UITestLaunchConfiguration.current() else { return nil }
            return try UITestHistoryContext.prepare(configuration: configuration)
        } catch {
            // A malformed test launch must never fall back to the user's production stores.
            fatalError("UI test history setup failed: \(error)")
        }
    }()
}

/// The production history view receives the same observable dependencies through its normal seams.
struct MacHistoryUITestRoot: View {
    let context: UITestHistoryContext
    @State private var toast = ToastManager()
    @State private var player = FullscreenPlayerManager()

    var body: some View {
        NavigationStack {
            MacHistoryView(progressStore: context.progress)
        }
        .environment(context.history)
        .environment(context.favorite)
        .environment(toast)
        .environment(player)
        .frame(minWidth: 800, minHeight: 450)
    }
}

#endif
