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
    @Environment(PlatformViewModel.self) private var viewModel
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showAddSheet = false
    @State private var navigationPath: [Platformdescription] = []
    @State private var showCapabilitySheet = false
    private let gridSpacing = AppConstants.Spacing.lg

    var body: some View {
        if pluginAvailability.hasAvailablePlugins {
            platformContent
        } else {
            ShellConfigView()
        }
    }

    // MARK: - 有插件时的平台内容

    private var platformContent: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                let metrics = layoutMetrics(for: proxy.size)

                ScrollView {
                    // 平台卡片网格
                    LazyVGrid(
                        columns: metrics.columns,
                        spacing: gridSpacing
                    ) {
                        ForEach(viewModel.platformInfo) { platform in
                            NavigationLink(value: platform) {
                                PlatformCard(platform: platform)
                                    .frame(width: metrics.itemWidth, height: metrics.itemHeight)
                            }
                            .buttonStyle(PlatformCardButtonStyle())
                        }
                    }
                    .padding(.horizontal, gridSpacing)
                    .padding(.vertical, gridSpacing)
                    .animation(.smooth(duration: 0.3), value: metrics.columns.count)

                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("配置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddContentSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(for: Platformdescription.self) { platform in
                PlatformDetailViewControllerWrapper()
                    .environment(PlatformDetailViewModel(platform: platform))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(platform.title)
                    .fullUITabBarHidden()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showCapabilitySheet = true
                            } label: {
                                Image(systemName: "info.circle")
                            }
                        }
                    }
                    .sheet(isPresented: $showCapabilitySheet) {
                        PlatformCapabilitySheet(liveType: platform.liveType)
                    }
            }
        }
    }

    // MARK: - 布局计算

    private func columnCount(for size: CGSize) -> Int {
        guard size.width > 0 else { return 2 }
        return horizontalSizeClass == .regular ? 3 : 2
    }

    private func layoutMetrics(for size: CGSize) -> GridMetrics {
        let columnsCount = max(1, columnCount(for: size))
        let horizontalPadding = gridSpacing * 2
        let interItemSpacing = gridSpacing * CGFloat(max(0, columnsCount - 1))
        let availableWidth = max(0, size.width - horizontalPadding - interItemSpacing)
        let itemWidth = columnsCount > 0 ? availableWidth / CGFloat(columnsCount) : 0
        let itemHeight = itemWidth * 0.6
        let gridColumns = Array(
            repeating: GridItem(.fixed(itemWidth), spacing: gridSpacing),
            count: columnsCount
        )
        return GridMetrics(columns: gridColumns, itemWidth: itemWidth, itemHeight: itemHeight)
    }
}

// MARK: - 添加内容 Sheet

private struct AddContentSheet: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.dismiss) private var dismiss

    @State private var inputURL = ""
    @State private var inputTitle = ""
    @State private var isProcessing = false
    @State private var showPluginList = false

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
                }
            }
            .sheet(isPresented: $showPluginList) {
                SubscriptionContentSheet(
                    pluginSourceManager: pluginSourceManager,
                    pluginAvailability: pluginAvailability
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
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
                    showPluginList = true
                }
            } else {
                let addedURLs = await pluginSourceManager.addSourceWithKeyResolution(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    showPluginList = true
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

// GridMetrics 复用（与 PlatformView 相同结构）
private struct GridMetrics {
    let columns: [GridItem]
    let itemWidth: CGFloat
    let itemHeight: CGFloat
}
