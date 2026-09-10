//
//  MacPluginManagementView.swift
//  AngelLiveMacOS
//
//  macOS 插件管理页：显示已安装插件、管理订阅源、安装/更新插件。
//

import SwiftUI
import AngelLiveCore

struct MacPluginManagementView: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(PluginInstallConsentService.self) private var consentService

    @State private var inputURL = ""
    @State private var isProcessing = false
    @State private var showAddSource = false

    var body: some View {
        @Bindable var consent = consentService

        Form {
            Section {
                PluginUpdateOverview(manager: pluginSourceManager,
                                     installedPluginIds: pluginAvailability.installedPluginIds,
                                     update: updatePlugins, check: checkUpdates)
            }

            if !showAddSource, pluginSourceManager.errorMessage != nil {
                Section { PluginManagementOperationError(manager: pluginSourceManager) }
            }

            installedPluginsSection

            // 可安装插件
            availablePluginsSection

            // 订阅源管理
            if !pluginSourceManager.sourceURLs.isEmpty {
                subscriptionSourcesSection
            }

            if pluginSourceManager.sourceURLs.isEmpty {
                Section {
                    Button("添加订阅源", systemImage: "plus") { showAddSource = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("插件管理")
        .focusedSceneValue(\.pluginManagementActions, MacPluginManagementActions(
            canUpdate: !showAddSource && !pluginSourceManager.isManagementBusy && pluginAvailability.installedPluginIds.contains {
                pluginSourceManager.hasUpdate(for: $0)
            },
            canCheck: !showAddSource && !pluginSourceManager.isManagementBusy && !pluginSourceManager.sourceURLs.isEmpty,
            update: { updatePlugins(pluginAvailability.installedPluginIds) }, check: checkUpdates
        ))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加订阅源", systemImage: "plus") { showAddSource = true }
                    .disabled(pluginSourceManager.isManagementBusy)
            }
        }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                Form { addSourceSection }
                    .formStyle(.grouped)
                    .navigationTitle("添加订阅源")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showAddSource = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
            }
            .frame(minWidth: 440, minHeight: 260)
        }
        .task { await reloadCatalog() }
        .onChange(of: pluginAvailability.installedPluginIds) { _, _ in
            guard !pluginSourceManager.isManagementBusy else { return }
            Task { await reloadCatalog() }
        }
        .alert(consent.alertTitle, isPresented: $consent.isPresenting) {
            Button(consent.continueButtonTitle) { consent.resolve(true) }
            Button("取消", role: .cancel) { consent.resolve(false) }
        } message: {
            Text(consent.alertMessage)
        }
    }

    // MARK: - 已安装插件

    private var installedPluginsSection: some View {
        Section {
            if pluginAvailability.installedPluginIds.isEmpty {
                ErrorView.empty(
                    title: "暂无已安装插件",
                    message: "安装完成的扩展会显示在这里，后续也会在这里管理更新与卸载。",
                    symbolName: "puzzlepiece.extension",
                    tint: .secondary,
                    layout: .compact(minHeight: 180)
                )
            } else {
                ForEach(pluginAvailability.installedPluginIds, id: \.self) { pluginId in
                    HStack(spacing: 12) {
                        managedPluginRow(pluginId: pluginId)
                        Menu {
                            Button("卸载插件", role: .destructive) {
                                Task {
                                    _ = pluginSourceManager.uninstallPlugin(pluginId: pluginId)
                                    await pluginAvailability.refresh()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("插件操作")
                        .disabled(pluginSourceManager.isManagementBusy)
                    }
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

    // MARK: - 可安装插件

    @ViewBuilder
    private var availablePluginsSection: some View {
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
                    if notInstalled.contains(where: {
                        pluginSourceManager.catalogActionState(for: $0) == .install
                    }) {
                        Button {
                            Task {
                                _ = await pluginSourceManager.installAll()
                                await pluginAvailability.refresh()
                                await pluginSourceManager.refreshAvailableUpdates()
                            }
                        } label: {
                            Text("全部安装")
                                .font(.caption)
                        }
                        .disabled(pluginSourceManager.isManagementBusy)
                    }
                }
            }
        }
    }

    // MARK: - 订阅源管理

    private var subscriptionSourcesSection: some View {
        Section {
            ForEach(pluginSourceManager.sourceURLs, id: \.self) { url in
                let health = pluginSourceManager.health(for: url)
                PanelNavigationRow(
                    title: URL(string: url)?.host() ?? "订阅源",
                    subtitle: url,
                    showsChevron: false
                ) {
                    Image(systemName: health.isFailed ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(macSourceTint(health))
                        .help(macSourceReason(health))
                } trailing: {
                    HStack(spacing: 12) {
                        macSourceBadge(health)

                        if health.isFailed {
                            Button {
                                Task { await pluginSourceManager.refreshSource(url) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("重试")
                        }

                        Button(role: .destructive) {
                            Task {
                                await pluginSourceManager.removeSourceAndAssociatedPlugins(url)
                                await pluginAvailability.refresh()
                                await pluginSourceManager.fetchAllSourceIndexes()
                                await pluginSourceManager.refreshAvailableUpdates()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .disabled(pluginSourceManager.isManagementBusy)
            }
        } header: {
            Text("已添加的订阅源")
        }
    }

    // MARK: - 订阅源健康状态展示

    private func macSourceTint(_ health: PluginSourceHealth) -> Color {
        switch health {
        case .failed: return .orange
        case .healthy: return .green
        case .checking, .unknown: return .blue
        }
    }

    private func macSourceReason(_ health: PluginSourceHealth) -> String {
        if case .failed(let reason) = health { return reason }
        return ""
    }

    @ViewBuilder
    private func macSourceBadge(_ health: PluginSourceHealth) -> some View {
        switch health {
        case .unknown:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .healthy(let count):
            Text("\(count) 个插件")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        case .failed:
            Text("异常")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - 添加订阅源

    private var addSourceSection: some View {
        Section {
            TextField("输入订阅源地址 (.json)", text: $inputURL)

            Button {
                addSource()
            } label: {
                HStack(spacing: 6) {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("添加订阅源")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing || pluginSourceManager.isManagementBusy)

            if let error = pluginSourceManager.errorMessage {
                PluginSourceErrorCard(title: "插件源异常", message: error)
            }
        } header: {
            Text("添加订阅源")
        } footer: {
            Text("输入包含插件索引的 JSON 地址，添加后会自动刷新可安装与可更新内容。")
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
        let icon = platform.flatMap { MacPlatformIconProvider.tabImage(for: $0.liveType) }.map { Image(nsImage: $0) }
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

    private func addSource() {
        guard !pluginSourceManager.isManagementBusy, !isProcessing else { return }
        let input = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isProcessing = true
        Task {
            let addedURLs = await pluginSourceManager.addSourceFromInput(input)
            if !addedURLs.isEmpty {
                inputURL = ""
                showAddSource = false
                await pluginSourceManager.fetchAllSourceIndexes()
                await pluginSourceManager.refreshAvailableUpdates()
            }
            isProcessing = false
        }
    }

}
