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

    var body: some View {
        List {
            // 已安装插件
            installedPluginsSection

            // 可安装插件（内联显示）
            availablePluginsInlineSection

            // 订阅源管理
            subscriptionSourcesSection

            // 添加新订阅源
            addSourceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
        }
        .onChange(of: pluginAvailability.installedPluginIds) { _, _ in
            Task {
                await pluginSourceManager.refreshAvailableUpdates()
            }
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
                    HStack {
                        pluginIconView(for: pluginId)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(pluginDisplayName(for: pluginId))
                                    .font(.body)
                                    .foregroundStyle(AppConstants.Colors.primaryText)
                                if pluginAvailability.requiresLogin(for: pluginId) {
                                    RequiresLoginTag()
                                }
                            }

                            versionSubtitleView(for: pluginId)
                        }

                        Spacer()

                        pluginStatusView(for: pluginId)
                    }
                    .padding(.vertical, AppConstants.Spacing.xs)
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
                    HStack {
                        pluginIconView(for: displayItem.id)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(displayItem.displayName)
                                    .font(.body)
                                    .foregroundStyle(AppConstants.Colors.primaryText)
                                if displayItem.item.auth?.required == true {
                                    RequiresLoginTag()
                                }
                            }
                            Text("版本 \(displayItem.item.version)")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }

                        Spacer()

                        remotePluginActionView(for: displayItem)
                    }
                    .padding(.vertical, AppConstants.Spacing.xs)
                }
            } header: {
                Text("可安装插件")
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

                Text(url)
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.primaryText)
                    .lineLimit(1)

                Spacer()

                sourceHealthBadge(health)
            }

            if case .failed(let reason) = health {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
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
            .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)

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
        let input = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isProcessing = true
        Task {
            let addedURLs = await pluginSourceManager.addSourceFromInput(input)
            if !addedURLs.isEmpty {
                inputURL = ""
                await pluginSourceManager.refreshAvailableUpdates()
                showAvailablePlugins = true
            }
            isProcessing = false
        }
    }

    // MARK: - Helpers

    private func pluginDisplayName(for pluginId: String) -> String {
        guard let platform = platformForPluginId(pluginId) else {
            return pluginId
        }
        return LiveParseTools.getLivePlatformName(platform.liveType)
    }

    private func platformForPluginId(_ pluginId: String) -> LiveParseJSPlatform? {
        LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == pluginId }
    }

    @ViewBuilder
    private func pluginIconView(for pluginId: String) -> some View {
        if let platform = platformForPluginId(pluginId),
           let image = PlatformIconProvider.pluginManagementImage(for: platform.liveType) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "puzzlepiece.extension")
                .frame(width: 32, height: 32)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
    }

    @ViewBuilder
    private func versionSubtitleView(for pluginId: String) -> some View {
        let installed = pluginSourceManager.installedVersion(for: pluginId) ?? "未知"
        if let latest = pluginSourceManager.latestVersion(for: pluginId),
           pluginSourceManager.hasUpdate(for: pluginId) {
            (
                Text(installed).foregroundStyle(Color.red) +
                Text(" → ").foregroundStyle(AppConstants.Colors.secondaryText) +
                Text(latest).foregroundStyle(Color.green)
            )
            .font(.caption)
        } else {
            Text("版本 \(installed)")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
    }

    @ViewBuilder
    private func pluginStatusView(for pluginId: String) -> some View {
        if pluginSourceManager.updatingPluginIds.contains(pluginId) {
            HStack(spacing: AppConstants.Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("更新中")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
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
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(AppConstants.Colors.link)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更新插件")
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppConstants.Colors.success)
        }
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
                            HStack {
                                pluginIconView(for: displayItem.id)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(displayItem.displayName)
                                            .font(.body)
                                            .foregroundStyle(AppConstants.Colors.primaryText)
                                        if displayItem.item.auth?.required == true
                                            || pluginAvailability.requiresLogin(for: displayItem.id) {
                                            RequiresLoginTag()
                                        }
                                    }
                                    Text("版本 \(displayItem.item.version)")
                                        .font(.caption)
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }

                                Spacer()

                                remotePluginActionView(for: displayItem)
                            }
                            .padding(.vertical, AppConstants.Spacing.xs)
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
                    if pluginSourceManager.remotePlugins.contains(where: { $0.installState == .notInstalled }) {
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
                        .disabled(pluginSourceManager.isInstalling)
                    }
                }
            }
        }
    }

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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.link, in: Capsule())
            }
            .buttonStyle(.plain)
        case .installing:
            ProgressView()
                .scaleEffect(0.8)
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppConstants.Colors.success)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
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
