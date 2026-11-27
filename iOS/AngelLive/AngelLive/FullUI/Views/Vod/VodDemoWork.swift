#if DEBUG && canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SharedAssets
import SwiftUI

struct VodDemoAppRoot: View {
    let sandbox: VodDemoSandbox
    @State private var selection: TabSelection = .home

    var body: some View {
        tabs
            .fullUIWindowContext(isEnabled: true)
            .fullUINavigationStyle(enabled: true)
            .fullUIArcLoadingStyle(isEnabled: true)
            .installToast(position: .top)
            .environment(sandbox.pluginAvailability)
            .environment(sandbox.history)
            .environment(sandbox.favorite)
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                Tab("演示", systemImage: "film", value: .home) { demo }
                Tab("设置", systemImage: "gearshape.fill", value: .settings) { settings }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $selection) {
                demo.tabItem { Label("演示", systemImage: "film") }.tag(TabSelection.home)
                settings.tabItem { Label("设置", systemImage: "gearshape.fill") }.tag(TabSelection.settings)
            }
        }
    }

    private var demo: some View {
        VodDemoRoot()
            .fullUITabBarSelection(tab: .home, selection: $selection)
    }

    private var settings: some View {
        NavigationStack {
            GeneralSettingView()
                .fullUITabBarVisibilityRoot()
        }
        .fullUITabBarSelection(tab: .settings, selection: $selection)
    }
}

private struct VodDemoRoot: View {
    @State private var path: [VodDemoWork] = []
    @State private var didLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            MediaShowcase(items: VodDemoWork.allCases, featured: .series, title: \.title, category: \.categoryTitle,
                         synopsis: \.synopsis, artwork: \.featuredImage) { path.append($0) }
            .toolbar(.hidden, for: .navigationBar)
            .fullUITabBarVisibilityRoot()
            .navigationDestination(for: VodDemoWork.self) { work in
                if VodRouting.usesDirectPlayer(work.room) {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: work.room))
                        .environment(\.fullUIRoomPlayerPushed, true)
                } else {
                    VodWorkDetailView(room: work.room, presentsOverSource: false)
                        .environment(\.fullUIRoomPlayerPushed, true)
                        .environment(\.finishRoomPlayerSwipe, { if path.last == work { path.removeLast() } })
                        .fullUIWindowContext()
                        .interactivePopGestureEnabled(false, edgeOnly: true)
                        .interactiveDismissDisabled()
                }
            }
        }
        .task {
            guard !didLaunch else { return }
            await Task.yield()
            guard !Task.isCancelled, !didLaunch else { return }
            didLaunch = true
            if path.isEmpty { path = [.launchWork] }
        }
    }
}
#endif
