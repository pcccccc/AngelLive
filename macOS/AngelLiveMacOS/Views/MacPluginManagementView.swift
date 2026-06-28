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

    var body: some View {
        @Bindable var consent = consentService

        Form {
            Section {
                PanelHintCard(
                    title: "统一管理扩展来源与版本",
                    message: "这里集中展示已安装扩展、远程可安装内容和订阅源地址，方便后续更新和清理。",
                    systemImage: "puzzlepiece.extension",
                    tint: .orange
                )
            }

            // 已安装插件
            installedPluginsSection

            // 可安装插件
            availablePluginsSection

            // 订阅源管理
            if !pluginSourceManager.sourceURLs.isEmpty {
                subscriptionSourcesSection
            }

            // 添加新订阅源
            addSourceSection
        }
        .formStyle(.grouped)
        .navigationTitle("插件管理")
        .task {
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
        }
        .onChange(of: pluginAvailability.installedPluginIds) { _, _ in
            Task {
                await pluginSourceManager.refreshAvailableUpdates()
            }
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
                    PanelNavigationRow(
                        title: pluginDisplayName(for: pluginId),
                        subtitle: installedSubtitle(for: pluginId),
                        showsChevron: false
                    ) {
                        pluginIconView(for: pluginId)
                    } titleAccessory: {
                        if pluginAvailability.requiresLogin(for: pluginId) {
                            RequiresLoginTag()
                        }
                    } trailing: {
                        HStack(spacing: 10) {
                            pluginStatusView(for: pluginId)

                            Button(role: .destructive) {
                                Task {
                                    _ = pluginSourceManager.uninstallPlugin(pluginId: pluginId)
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
                    .padding(.vertical, 2)
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
                    PanelNavigationRow(
                        title: displayItem.displayName,
                        subtitle: "版本 \(displayItem.item.version)",
                        showsChevron: false
                    ) {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.orange.gradient)
                    } titleAccessory: {
                        if displayItem.item.auth?.required == true
                            || pluginAvailability.requiresLogin(for: displayItem.id) {
                            RequiresLoginTag()
                        }
                    } trailing: {
                        remotePluginActionView(for: displayItem)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                HStack {
                    Text("可安装插件")
                    Spacer()
                    if notInstalled.contains(where: { $0.installState == .notInstalled }) {
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
                        .disabled(pluginSourceManager.isInstalling)
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
                    title: "订阅源",
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
            PanelHintCard(
                title: "添加新的订阅源",
                message: "输入 JSON 索引地址后，会自动检查远程扩展版本并同步到当前列表。",
                systemImage: "tray.and.arrow.down.fill",
                tint: .accentColor
            )

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
            .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)

            if let error = pluginSourceManager.errorMessage {
                PluginSourceErrorCard(title: "插件源异常", message: error)
            }
        } header: {
            Text("添加订阅源")
        } footer: {
            Text("输入包含插件索引的 JSON 地址，添加后会自动刷新可安装与可更新内容。")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pluginIconView(for pluginId: String) -> some View {
        if let platform = platformForPluginId(pluginId),
           let image = MacPlatformIconProvider.tabImage(for: platform.liveType) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
    }

    private func pluginDisplayName(for pluginId: String) -> String {
        guard let platform = platformForPluginId(pluginId) else { return pluginId }
        return LiveParseTools.getLivePlatformName(platform.liveType)
    }

    private func platformForPluginId(_ pluginId: String) -> LiveParseJSPlatform? {
        LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == pluginId }
    }

    private func installedSubtitle(for pluginId: String) -> String {
        let installed = pluginSourceManager.installedVersion(for: pluginId) ?? "未知"
        if let latest = pluginSourceManager.latestVersion(for: pluginId),
           pluginSourceManager.hasUpdate(for: pluginId) {
            return "版本 \(installed) · 可更新到 \(latest)"
        }
        return "版本 \(installed)"
    }

    @ViewBuilder
    private func pluginStatusView(for pluginId: String) -> some View {
        if pluginSourceManager.updatingPluginIds.contains(pluginId) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                PanelStatusBadge("更新中")
            }
        } else if pluginSourceManager.hasUpdate(for: pluginId) {
            Button {
                Task {
                    let success = await pluginSourceManager.updatePlugin(pluginId: pluginId)
                    if success {
                        await pluginAvailability.refresh()
                    }
                    await pluginSourceManager.refreshAvailableUpdates()
                }
            } label: {
                Label("更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            PanelStatusBadge("已安装", tint: AppConstants.Colors.success)
        }
    }

    private func addSource() {
        let input = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isProcessing = true
        Task {
            let addedURLs = await pluginSourceManager.addSourceFromInput(input)
            if !addedURLs.isEmpty {
                inputURL = ""
                await pluginSourceManager.fetchAllSourceIndexes()
                await pluginSourceManager.refreshAvailableUpdates()
            }
            isProcessing = false
        }
    }

    // MARK: - 远程插件操作

    @ViewBuilder
    private func remotePluginActionView(for displayItem: RemotePluginDisplayItem) -> some View {
        switch displayItem.installState {
        case .notInstalled:
            Button {
                Task {
                    let success = await pluginSourceManager.installPlugin(displayItem)
                    if success {
                        await pluginAvailability.refresh()
                        await pluginSourceManager.refreshAvailableUpdates()
                    }
                }
            } label: {
                Text("安装")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppConstants.Colors.success)
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}
