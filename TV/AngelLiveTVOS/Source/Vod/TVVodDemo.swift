#if DEBUG
import AngelLiveCore
import SwiftUI
import SharedAssets

struct TVVodDemoRootView: View {
    let appViewModel: AppState
    let sandbox: VodDemoSandbox

    @State private var work: VodDemoWork?
    @State private var lastWork: VodDemoWork?
    @State private var didLaunch = false
    @FocusState private var focusedWork: VodDemoWork?

    var body: some View {
        tabs
            .environment(appViewModel)
            .defaultAppStorage(UserDefaults.shared)
            .fullScreenCover(item: $work, onDismiss: { focusedWork = lastWork }) { item in
                TVVodContainerView(room: item.room, settings: appViewModel.generalSettingsViewModel) {
                    work = nil
                }
            }
            .onChange(of: work) { _, item in
                if let item { lastWork = item }
            }
            .task {
                guard !didLaunch, sandbox.pluginAvailability.hasAvailablePlugins else { return }
                await Task.yield()
                guard !Task.isCancelled, !didLaunch else { return }
                didLaunch = true
                work = VodDemoWork.launchWork
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(tvOS 18.0, *) {
            TabView {
                Tab("演示", systemImage: "film") { demo }
                Tab("设置", systemImage: "gearshape") { settings }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView {
                demo.tabItem { Label("演示", systemImage: "film") }
                settings.tabItem { Label("设置", systemImage: "gearshape") }
            }
        }
    }

    private var demo: some View {
        MediaShowcase(items: VodDemoWork.allCases, featured: .series, title: \.title, category: \.categoryTitle,
                     synopsis: \.synopsis, artwork: \.featuredImage, focus: $focusedWork) { work = $0 }
    }

    private var settings: some View {
        GeneralSettingView().padding(.horizontal, TVFullUIPlayerControlMetrics.screenInset)
    }
}
#endif
