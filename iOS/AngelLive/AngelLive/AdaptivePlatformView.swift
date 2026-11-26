//
//  AdaptivePlatformView.swift
//  AngelLive
//
//  根据插件安装状态自适应显示平台网格或配置页。
//  有插件时显示平台卡片 + 底部订阅管理，无插件时显示完整配置页。
//

import SwiftUI
import AngelLiveCore

struct AdaptivePlatformView: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @State private var showAddSheet = false
    @State private var navigationPath: [AdaptivePlatformRoute] = []
    @State private var pendingPluginSourceURLs: [String]?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if pluginAvailability.hasAvailablePlugins {
                    IOSPlatformPage(open: { navigationPath.append(.platform($0)) }, addContent: { showAddSheet = true })
                        .sheet(isPresented: $showAddSheet, onDismiss: openPendingPluginSources) {
                            AddContentSheet { sourceURLs in
                                pendingPluginSourceURLs = sourceURLs
                                showAddSheet = false
                            }
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                        }
                } else {
                    ShellConfigView(onOpenPluginSources: openPluginSources)
                }
            }
            .navigationDestination(for: AdaptivePlatformRoute.self) { route in
                switch route {
                case .platform(let platform):
                    platformDestination(platform)
                case .pluginSources(let sourceURLs):
                    PluginManagementView(entry: .sources(sourceURLs))
                        .fullUITabBarHidden()
                }
            }
        }
    }

    private func platformDestination(_ platform: Platformdescription) -> some View {
        PlatformDetailViewControllerWrapper()
            .environment(PlatformDetailViewModel(platform: platform))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(platform.title)
            .fullUITabBarHidden()
    }

    private func openPluginSources(_ sourceURLs: [String]) {
        navigationPath.append(.pluginSources(sourceURLs))
    }

    private func openPendingPluginSources() {
        guard let sourceURLs = pendingPluginSourceURLs else { return }
        pendingPluginSourceURLs = nil
        openPluginSources(sourceURLs)
    }

    private enum AdaptivePlatformRoute: Hashable {
        case platform(Platformdescription)
        case pluginSources([String])
    }

}

// MARK: - 平台网格

struct IOSPlatformPage: View {
    let open: (Platformdescription) -> Void
    var addContent: (() -> Void)?

    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PlatformViewModel.self) private var viewModel
    @State private var showAppearance = false
    @State private var customPlatform: Platformdescription?
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        IOSPlatformGrid(platforms: viewModel.platformInfo, catalogRevision: pluginAvailability.catalogRevision) {
            open($0)
        } customize: {
            customPlatform = $0
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .fullUITabBarVisibilityRoot()
        .navigationTitle("配置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("配置页外观", systemImage: "slider.horizontal.3") {
                    showAppearance = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("配置页外观")
                .accessibilityIdentifier("platform.appearance.open")
                if let addContent {
                    Button(action: addContent) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加视频或订阅")
                    .accessibilityIdentifier("platform.add")
                }
            }
        }
        .sheet(isPresented: $showAppearance) {
            NavigationStack { IOSPlatformAppearancePage(showsDone: true, gridWidth: gridWidth) }
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $customPlatform) { platform in
            NavigationStack { IOSPlatformAppearanceCardEditor(platform: platform, showsDone: true, gridWidth: gridWidth) }
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - 添加内容 Sheet

private struct AddContentSheet: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss

    let onOpenPluginSources: ([String]) -> Void

    @State private var inputURL = ""
    @State private var inputTitle = ""
    @State private var isProcessing = false

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubscriptionURL: Bool {
        guard !trimmedURL.isEmpty else { return false }
        if let url = URL(string: trimmedURL) {
            return url.pathExtension.lowercased() == "json"
        }
        return trimmedURL.lowercased().hasSuffix(".json")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("标题（可选）", text: $inputTitle)

                    TextField("输入地址", text: $inputURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    Button {
                        handleAdd()
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppConstants.Colors.success.gradient)
                            }
                            Text("添加")
                        }
                    }
                    .disabled(trimmedURL.isEmpty || isProcessing)

                    if let error = pluginSourceManager.errorMessage {
                        PluginSourceErrorCard(title: "插件源异常", message: error)
                    }
                } header: {
                    Text("添加视频或订阅")
                } footer: {
                    Text("输入视频地址添加到收藏，可在收藏页直接播放")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
        .interactiveDismissDisabled(isProcessing)
    }

    private func handleAdd() {
        let url = trimmedURL
        let title = inputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldTreatAsSubscription = isSubscriptionURL
        guard !url.isEmpty else { return }

        isProcessing = true
        Task {
            if shouldTreatAsSubscription {
                let addedURLs = await pluginSourceManager.addSourceFromInput(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    isProcessing = false
                    onOpenPluginSources(addedURLs)
                    dismiss()
                    return
                }
            } else {
                let addedURLs = await pluginSourceManager.addSourceWithKeyResolution(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    isProcessing = false
                    onOpenPluginSources(addedURLs)
                    dismiss()
                    return
                } else if pluginSourceManager.errorMessage == nil {
                    await bookmarkService.add(title: title.isEmpty ? url : title, url: url)
                    inputURL = ""
                    inputTitle = ""
                }
            }
            isProcessing = false
        }
    }
}
