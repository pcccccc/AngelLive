//
//  PluginManagementView.swift
//  AngelLive
//
//  插件管理页面：显示已安装插件、管理订阅源、安装新插件。
//

import SwiftUI
import AngelLiveCore

struct PluginManagementView: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager

    @State private var inputURL = ""
    @State private var isProcessing = false
    @State private var showAvailablePlugins = false
    @State private var showAddSource = false

    var body: some View {
        List {
            Section {
                PluginUpdateOverview(manager: pluginSourceManager,
                                     installedPluginIds: pluginAvailability.installedPluginIds,
                                     update: updatePlugins, check: checkUpdates)
            }

            if !showAddSource, pluginSourceManager.errorMessage != nil {
                Section { PluginManagementOperationError(manager: pluginSourceManager) }
            }

            installedPluginsSection

            // 可安装插件（内联显示）
            availablePluginsInlineSection

            // 订阅源管理
            subscriptionSourcesSection

            if pluginSourceManager.sourceURLs.isEmpty {
                Section {
                    Button("添加订阅源", systemImage: "plus") { showAddSource = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加订阅源", systemImage: "plus") { showAddSource = true }
                    .disabled(pluginSourceManager.isManagementBusy)
            }
        }
        .task { await reloadCatalog() }
        .refreshable { await reloadCatalog() }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                List { addSourceSection }
                    .navigationTitle("添加订阅源")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showAddSource = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: pluginAvailability.installedPluginIds) { _, _ in
            guard !pluginSourceManager.isManagementBusy else { return }
            Task { await reloadCatalog() }
        }
        .sheet(isPresented: $showAvailablePlugins) {
            availablePluginsSheet
        }
    }

    // MARK: - 已安装插件

    private var installedPluginsSection: some View {
        Section {
            if pluginAvailability.installedPluginIds.isEmpty {
                Text("暂无已安装的插件")
                    .font(.body)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            } else {
                ForEach(pluginAvailability.installedPluginIds, id: \.self) { pluginId in
                    managedPluginRow(pluginId: pluginId)
                    #if !os(tvOS)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                _ = pluginSourceManager.uninstallPlugin(pluginId: pluginId)
                                await pluginAvailability.refresh()
                                await pluginSourceManager.fetchAllSourceIndexes()
                                await pluginSourceManager.refreshAvailableUpdates()
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(pluginSourceManager.isManagementBusy)
                    }
                    #endif
                }
            }
        } header: {
            Text("已安装插件")
        } footer: {
            if !pluginAvailability.installedPluginIds.isEmpty {
                Text("共 \(pluginAvailability.installedPluginIds.count) 个插件")
            }
        }
    }

    // MARK: - 可安装插件（内联）

    @ViewBuilder
    private var availablePluginsInlineSection: some View {
        let notInstalled = pluginSourceManager.remotePlugins.filter {
            pluginSourceManager.installedVersion(for: $0.id) == nil
        }
        if !notInstalled.isEmpty {
            Section {
                ForEach(notInstalled) { displayItem in
                    managedPluginRow(pluginId: displayItem.id, remote: displayItem)
                }
            } header: {
                HStack {
                    Text("可安装插件")
                    Spacer()
                    Button("查看全部") { showAvailablePlugins = true }
                }
            }
        }
    }

    // MARK: - 订阅源管理

    @ViewBuilder
    private var subscriptionSourcesSection: some View {
        if !pluginSourceManager.sourceURLs.isEmpty {
            Section {
                ForEach(pluginSourceManager.sourceURLs, id: \.self) { url in
                    sourceRow(url)
                }
            } header: {
                Text("已添加的订阅源")
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ url: String) -> some View {
        let health = pluginSourceManager.health(for: url)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: sourceHealthIcon(health))
                    .font(.caption)
                    .foregroundStyle(sourceHealthTint(health))

                Text(URL(string: url)?.host() ?? url)
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.primaryText)
                    .lineLimit(1)

                Spacer()

                sourceHealthBadge(health)
            }

            Text(url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if case .failed(let reason) = health {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .disabled(pluginSourceManager.isManagementBusy)
        .swipeActions(edge: .leading) {
            if health.isFailed {
                Button {
                    Task { await pluginSourceManager.refreshSource(url) }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await pluginSourceManager.removeSourceAndAssociatedPlugins(url)
                    await pluginAvailability.refresh()
                    await pluginSourceManager.fetchAllSourceIndexes()
                    await pluginSourceManager.refreshAvailableUpdates()
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func sourceHealthIcon(_ health: PluginSourceHealth) -> String {
        health.isFailed ? "exclamationmark.triangle.fill" : "link"
    }

    private func sourceHealthTint(_ health: PluginSourceHealth) -> Color {
        switch health {
        case .failed: return .orange
        case .healthy: return .green
        case .checking, .unknown: return AppConstants.Colors.secondaryText
        }
    }

    @ViewBuilder
    private func sourceHealthBadge(_ health: PluginSourceHealth) -> some View {
        switch health {
        case .unknown:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.mini)
        case .healthy(let count):
            Text("\(count) 个插件")
                .font(.caption2)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        case .failed:
            Text("异常")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - 添加订阅源

    private var addSourceSection: some View {
        Section {
            TextField("输入订阅源地址 (.json)", text: $inputURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)

            Button {
                addSource()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppConstants.Colors.success.gradient)
                    }
                    Text("添加订阅源")
                }
            }
            .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing || pluginSourceManager.isManagementBusy)

            if let error = pluginSourceManager.errorMessage {
                PluginSourceErrorCard(title: "插件源异常", message: error)
            }
        } header: {
            Text("添加订阅源")
        } footer: {
            Text("输入包含插件索引的 JSON 地址，添加后将自动检查插件更新")
        }
    }

    // MARK: - Actions

    private func addSource() {
        guard !pluginSourceManager.isManagementBusy, !isProcessing else { return }
        let input = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isProcessing = true
        Task {
            let addedURLs = await pluginSourceManager.addSourceFromInput(input)
            if !addedURLs.isEmpty {
                inputURL = ""
                await pluginSourceManager.refreshAvailableUpdates()
                showAddSource = false
                await pluginSourceManager.fetchAllSourceIndexes()
            }
            isProcessing = false
        }
    }

    // MARK: - Plugin rows and operations

    private func managedPluginRow(pluginId: String, remote: RemotePluginDisplayItem? = nil) -> some View {
        let installed = pluginSourceManager.installedVersion(for: pluginId)
        let latest = pluginSourceManager.latestVersion(for: pluginId)
        let version = installed.map { current in
            pluginSourceManager.hasUpdate(for: pluginId) ? "版本 \(current) → \(latest ?? current)" : "版本 \(current)"
        } ?? "版本 \(remote?.item.version ?? "未知")"
        let state = pluginSourceManager.managementActionState(for: pluginId, remote: remote)
        let platform = LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == pluginId }
        let icon = platform.flatMap { PlatformIconProvider.pluginManagementImage(for: $0.liveType) }.map { Image(uiImage: $0) }
        return PluginManagementPluginRow(
            name: pluginSourceManager.managementDisplayName(for: pluginId),
            version: version,
            requiresLogin: pluginAvailability.requiresLogin(for: pluginId) || remote?.item.auth?.required == true,
            state: state, icon: icon, disabled: pluginSourceManager.isManagementBusy,
            isWaiting: pluginSourceManager.isWaitingForUpdate(for: pluginId)
        ) {
            if installed != nil {
                updatePlugins([pluginId])
            } else if let remote {
                Task {
                    _ = await pluginSourceManager.installPlugin(remote)
                    await pluginAvailability.refresh()
                }
            }
        }
    }

    private func updatePlugins(_ ids: [String]) {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: ids)
            await pluginAvailability.refresh()
        }
    }

    private func checkUpdates() {
        guard !pluginSourceManager.isManagementBusy else { return }
        pluginSourceManager.updateBatch.clearResult()
        Task { await reloadCatalog() }
    }

    private func reloadCatalog() async {
        guard !pluginSourceManager.isManagementBusy else { return }
        await pluginSourceManager.fetchAllSourceIndexes()
        await pluginSourceManager.refreshAvailableUpdates()
    }

    // MARK: - 可安装插件 Sheet

    private var availablePluginsSheet: some View {
        NavigationStack {
            List {
                if pluginSourceManager.remotePlugins.isEmpty {
                    Text("没有可用的插件")
                        .font(.body)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                } else {
                    Section {
                        ForEach(pluginSourceManager.remotePlugins) { displayItem in
                            managedPluginRow(pluginId: displayItem.id, remote: displayItem)
                        }
                    } header: {
                        Text("共 \(pluginSourceManager.remotePlugins.count) 个插件")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("可安装插件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showAvailablePlugins = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if pluginSourceManager.remotePlugins.contains(where: {
                        pluginSourceManager.catalogActionState(for: $0) == .install
                    }) {
                        Button {
                            Task {
                                _ = await pluginSourceManager.installAll()
                                await pluginAvailability.refresh()
                                await pluginSourceManager.refreshAvailableUpdates()
                            }
                        } label: {
                            if pluginSourceManager.isInstalling {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("全部安装")
                            }
                        }
                        .disabled(pluginSourceManager.isManagementBusy)
                    }
                }
            }
        }

    }

}
