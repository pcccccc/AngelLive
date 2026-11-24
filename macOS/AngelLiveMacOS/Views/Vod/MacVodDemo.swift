#if DEBUG
import AngelLiveCore
import SwiftUI
import SharedAssets

struct MacVodDemoAppRoot: View {
    let sandbox: VodDemoSandbox
    @State private var work: VodDemoWork?
    @State private var didLaunch = false
    @State private var toast = ToastManager()
    @State private var fullscreenPlayer = FullscreenPlayerManager()

    var body: some View {
        Group {
            if let work {
                MacRoomPlaybackDestination(room: work.room, presentation: .embedded(close: { self.work = nil }))
                    .id(work.id)
            } else {
                TabView {
                    Tab("演示", systemImage: "film") {
                        MediaShowcase(items: VodDemoWork.allCases, featured: .series, title: \.title, category: \.categoryTitle,
                                     synopsis: \.synopsis, artwork: \.featuredImage) { self.work = $0 }
                    }
                    Tab("设置", systemImage: "gearshape") {
                        SettingView()
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
            }
        }
        .task {
            guard !didLaunch else { return }
            await Task.yield()
            guard !Task.isCancelled, !didLaunch else { return }
            didLaunch = true
            if work == nil { work = .launchWork }
        }
        .environment(sandbox.pluginAvailability)
        .environment(sandbox.favorite)
        .environment(sandbox.history)
        .environment(toast)
        .environment(fullscreenPlayer)
        .environment(\.usesFullUI, true)
        .defaultAppStorage(.shared)
    }
}
#endif
