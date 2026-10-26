//
//  MacPluginManagementView.swift
//  AngelLiveMacOS
//
//  macOS FullUI 的插件管理：以紧凑列表、订阅源 sheet 和原生控件承载
//  插件安装、更新与卸载。业务状态仍由 PluginSourceManager 持有。
//

import AppKit
import SwiftUI
import AngelLiveCore

struct MacPluginManagementView: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(PluginInstallConsentService.self) private var consentService
    @Environment(\.dismiss) private var dismiss

    @State private var scope: MacPluginManagementScope = .installed
    @State private var searchText = ""
    @State private var searchFocusRequest = 0
    @State private var showSources = false
    @State private var showAddSource = false
    @State private var pluginPendingUninstall: MacPluginRemovalRequest?

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allInstalledPluginIds: [String] {
        pluginAvailability.installedPluginIds
    }

    private var filteredInstalledPluginIds: [String] {
        guard !normalizedSearchText.isEmpty else { return allInstalledPluginIds }
        return allInstalledPluginIds.filter { pluginMatchesSearch(pluginId: $0) }
    }

    private var allAvailablePlugins: [RemotePluginDisplayItem] {
        pluginSourceManager.remotePlugins.filter {
            pluginSourceManager.installedVersion(for: $0.id) == nil
        }
    }

    private var filteredAvailablePlugins: [RemotePluginDisplayItem] {
        guard !normalizedSearchText.isEmpty else { return allAvailablePlugins }
        return allAvailablePlugins.filter { pluginMatchesSearch(pluginId: $0.id, remote: $0) }
    }

    private var updateCandidates: [String] {
        allInstalledPluginIds.filter { pluginSourceManager.hasUpdate(for: $0) }
    }

    private var hasInstallablePlugins: Bool {
        allAvailablePlugins.contains {
            pluginSourceManager.catalogActionState(for: $0) == .install
        }
    }

    var body: some View {
        @Bindable var consent = consentService

        NavigationStack {
            Form {
                Section {
                    PluginUpdateOverview(
                        manager: pluginSourceManager,
                        installedPluginIds: allInstalledPluginIds,
                        update: updatePlugins,
                        check: checkUpdates
                    )
                }

                Section {
                    if pluginSourceManager.errorMessage != nil {
                        PluginManagementOperationError(manager: pluginSourceManager)
                    }

                    MacPluginManagementList(
                        scope: scope,
                        installedPluginIds: filteredInstalledPluginIds,
                        availablePlugins: filteredAvailablePlugins,
                        sourceCount: pluginSourceManager.sourceURLs.count,
                        isManagementBusy: pluginSourceManager.isManagementBusy,
                        hasInstallablePlugins: hasInstallablePlugins,
                        searchText: normalizedSearchText,
                        makeInstalledRow: { pluginId in
                            managedPluginRow(pluginId: pluginId)
                        },
                        makeAvailableRow: { item in
                            managedPluginRow(pluginId: item.id, remote: item)
                        },
                        displayNameForPlugin: { pluginSourceManager.managementDisplayName(for: $0) },
                        installAll: installAllPlugins,
                        openAddSource: { showAddSource = true },
                        requestUninstall: { pluginId in
                            pluginPendingUninstall = MacPluginRemovalRequest(
                                id: pluginId,
                                name: pluginSourceManager.managementDisplayName(for: pluginId)
                            )
                        }
                    )
                } header: {
                    HStack(spacing: 12) {
                        MacPluginManagementScopePicker(
                            scope: $scope,
                            installedCount: allInstalledPluginIds.count,
                            availableCount: allAvailablePlugins.count
                        )
                        MacPluginSearchField(text: $searchText, focusRequest: searchFocusRequest)
                            .frame(width: 220)
                    }
                }

                Section("管理") {
                    Button { showSources = true } label: {
                        PanelNavigationRow(
                            title: "订阅源",
                            subtitle: "管理插件来源与订阅状态"
                        ) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Text("\(pluginSourceManager.sourceURLs.count) 个")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button { showAddSource = true } label: {
                        PanelNavigationRow(title: "添加订阅源", showsChevron: false) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(pluginSourceManager.isManagementBusy)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("插件管理")
            .macSettingsPage("插件管理")
        }
        .macSettingsSheetPresentation()
        .focusedSceneValue(
            \.pluginManagementActions,
            MacPluginManagementActions(
                canUpdate: !showSources && !showAddSource && !pluginSourceManager.isManagementBusy && !updateCandidates.isEmpty,
                canCheck: !showSources && !showAddSource && !pluginSourceManager.isManagementBusy && !pluginSourceManager.sourceURLs.isEmpty,
                canAddSource: !showSources && !showAddSource && !pluginSourceManager.isManagementBusy,
                canShowSources: !showSources && !showAddSource,
                canSearch: !showSources && !showAddSource && pluginPendingUninstall == nil && !consent.isPresenting,
                update: { updatePlugins(allInstalledPluginIds) },
                check: checkUpdates,
                addSource: { showAddSource = true },
                showSources: { showSources = true },
                search: { searchFocusRequest += 1 }
            )
        )
        .sheet(isPresented: $showSources) {
            NavigationStack {
                MacPluginSourcesView(reloadCatalog: reloadCatalog)
            }
            .macSettingsSheetPresentation()
            .frame(minWidth: 620, idealWidth: 700, minHeight: 420, idealHeight: 520)
        }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                MacPluginAddSourceView(reloadCatalog: reloadCatalog)
            }
            .macSettingsSheetPresentation()
            .frame(minWidth: 460, idealWidth: 520, minHeight: 280, idealHeight: 320)
        }
        .confirmationDialog(
            "卸载插件？",
            isPresented: Binding(
                get: { pluginPendingUninstall != nil },
                set: { if !$0 { pluginPendingUninstall = nil } }
            ),
            titleVisibility: .visible,
            presenting: pluginPendingUninstall
        ) { request in
            Button("卸载“\(request.name)”", role: .destructive) {
                uninstallPlugin(request.id)
                pluginPendingUninstall = nil
            }
            Button("取消", role: .cancel) {
                pluginPendingUninstall = nil
            }
        } message: { request in
            Text("将从此设备移除插件“\(request.name)”。")
        }
        .task {
            await reloadCatalog()
        }
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
        .frame(minWidth: 600, minHeight: 520)
    }

    private func pluginMatchesSearch(pluginId: String, remote: RemotePluginDisplayItem? = nil) -> Bool {
        let displayName = remote?.displayName ?? pluginSourceManager.managementDisplayName(for: pluginId)
        return displayName.localizedCaseInsensitiveContains(normalizedSearchText)
            || pluginId.localizedCaseInsensitiveContains(normalizedSearchText)
    }

    // MARK: - Plugin rows and operations

    private func managedPluginRow(
        pluginId: String,
        remote: RemotePluginDisplayItem? = nil
    ) -> MacSettingsPluginRow {
        let installed = pluginSourceManager.installedVersion(for: pluginId)
        let latest = pluginSourceManager.latestVersion(for: pluginId)
        let version = installed.map { current in
            pluginSourceManager.hasUpdate(for: pluginId)
                ? "版本 \(current) → \(latest ?? current)"
                : "版本 \(current)"
        } ?? "版本 \(remote?.item.version ?? "未知")"
        let state = pluginSourceManager.managementActionState(for: pluginId, remote: remote)
        let platform = LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == pluginId }
        let icon = platform
            .flatMap { MacPlatformIconProvider.pluginManagementImage(for: $0.liveType) }
            .map { Image(nsImage: $0) }

        return MacSettingsPluginRow(
            name: pluginSourceManager.managementDisplayName(for: pluginId),
            version: version,
            requiresLogin: pluginAvailability.requiresLogin(for: pluginId) || remote?.item.auth?.required == true,
            state: state,
            icon: icon,
            disabled: pluginSourceManager.isManagementBusy,
            isWaiting: pluginSourceManager.isWaitingForUpdate(for: pluginId)
        ) {
            if installed != nil {
                updatePlugins([pluginId])
            } else if let remote {
                installPlugin(remote)
            }
        }
    }

    private func updatePlugins(_ ids: [String]) {
        guard !pluginSourceManager.isManagementBusy else { return }
        let installedIds = Set(allInstalledPluginIds)
        let candidates = ids.filter {
            installedIds.contains($0) && pluginSourceManager.hasUpdate(for: $0)
        }
        guard !candidates.isEmpty else { return }

        Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: candidates)
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

    private func installPlugin(_ item: RemotePluginDisplayItem) {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            let success = await pluginSourceManager.installPlugin(item)
            await pluginAvailability.refresh()
            if success {
                await reloadCatalog()
            }
        }
    }

    private func installAllPlugins() {
        guard !pluginSourceManager.isManagementBusy else { return }
        guard allAvailablePlugins.contains(where: {
            pluginSourceManager.catalogActionState(for: $0) == .install
        }) else { return }

        Task {
            _ = await pluginSourceManager.installAll()
            await pluginAvailability.refresh()
            await reloadCatalog()
        }
    }

    private func uninstallPlugin(_ pluginId: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        _ = pluginSourceManager.uninstallPlugin(pluginId: pluginId)
        Task { await pluginAvailability.refresh() }
    }
}

private enum MacPluginManagementScope: String, CaseIterable, Identifiable {
    case installed
    case available

    var id: String { rawValue }
}

private struct MacPluginRemovalRequest: Identifiable {
    let id: String
    let name: String
}

private struct MacPluginSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "搜索插件"
        field.controlSize = .regular
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setAccessibilityLabel("搜索插件")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusRequest != focusRequest,
           let window = field.window {
            context.coordinator.lastFocusRequest = focusRequest
            window.makeFirstResponder(field)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 220, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>
        var lastFocusRequest = 0

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func searchChanged(_ field: NSSearchField) {
            text.wrappedValue = field.stringValue
        }
    }
}

private struct MacPluginManagementScopePicker: View {
    @Binding var scope: MacPluginManagementScope
    let installedCount: Int
    let availableCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Picker("插件范围", selection: $scope) {
                Text("已安装").tag(MacPluginManagementScope.installed)
                Text("可安装").tag(MacPluginManagementScope.available)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("插件范围")

            Text(scope == .installed ? "\(installedCount) 个插件" : "\(availableCount) 个插件")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("插件范围")
    }
}

private struct MacPluginManagementList: View {
    let scope: MacPluginManagementScope
    let installedPluginIds: [String]
    let availablePlugins: [RemotePluginDisplayItem]
    let sourceCount: Int
    let isManagementBusy: Bool
    let hasInstallablePlugins: Bool
    let searchText: String
    let makeInstalledRow: (String) -> MacSettingsPluginRow
    let makeAvailableRow: (RemotePluginDisplayItem) -> MacSettingsPluginRow
    let displayNameForPlugin: (String) -> String
    let installAll: () -> Void
    let openAddSource: () -> Void
    let requestUninstall: (String) -> Void

    var body: some View {
        Group {
            switch scope {
            case .installed:
                MacInstalledPluginSection(
                    pluginIds: installedPluginIds,
                    searchText: searchText,
                    makeRow: makeInstalledRow,
                    isManagementBusy: isManagementBusy,
                    displayNameForPlugin: displayNameForPlugin,
                    requestUninstall: requestUninstall
                )
            case .available:
                MacAvailablePluginSection(
                    plugins: availablePlugins,
                    sourceCount: sourceCount,
                    isManagementBusy: isManagementBusy,
                    searchText: searchText,
                    makeRow: makeAvailableRow,
                    installAll: installAll,
                    openAddSource: openAddSource,
                    hasInstallablePlugin: hasInstallablePlugins
                )
            }
        }
    }
}

private struct MacInstalledPluginSection: View {
    let pluginIds: [String]
    let searchText: String
    let makeRow: (String) -> MacSettingsPluginRow
    let isManagementBusy: Bool
    let displayNameForPlugin: (String) -> String
    let requestUninstall: (String) -> Void

    var body: some View {
        Group {
            if pluginIds.isEmpty {
                MacPluginEmptyState(
                    title: searchText.isEmpty ? "暂无已安装插件" : "没有匹配的插件",
                    message: searchText.isEmpty
                        ? "安装完成的插件会显示在这里，并可从插件菜单中卸载。"
                        : "请尝试其他名称或插件标识。",
                    systemImage: "puzzlepiece.extension"
                )
            } else {
                ForEach(pluginIds, id: \.self) { pluginId in
                    MacInstalledPluginRow(
                        pluginName: displayNameForPlugin(pluginId),
                        row: makeRow(pluginId),
                        isManagementBusy: isManagementBusy,
                        requestUninstall: { requestUninstall(pluginId) }
                    )
                }
            }
        }
    }
}

private struct MacAvailablePluginSection: View {
    let plugins: [RemotePluginDisplayItem]
    let sourceCount: Int
    let isManagementBusy: Bool
    let searchText: String
    let makeRow: (RemotePluginDisplayItem) -> MacSettingsPluginRow
    let installAll: () -> Void
    let openAddSource: () -> Void

    let hasInstallablePlugin: Bool

    var body: some View {
        Group {
            if searchText.isEmpty, hasInstallablePlugin {
                LabeledContent("安装当前订阅源中的全部插件") {
                    Button("全部安装", systemImage: "arrow.down.circle", action: installAll)
                        .disabled(isManagementBusy)
                }
            }

            if plugins.isEmpty {
                MacPluginEmptyState(
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: sourceCount == 0 ? "tray.and.arrow.down" : "magnifyingglass",
                    actionTitle: sourceCount == 0 && searchText.isEmpty ? "添加订阅源" : nil,
                    action: sourceCount == 0 && searchText.isEmpty ? openAddSource : nil,
                    actionDisabled: isManagementBusy
                )
            } else {
                ForEach(plugins) { item in
                    makeRow(item)
                }
            }
        }
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "没有匹配的插件" }
        return sourceCount == 0 ? "暂无订阅源" : "暂无可安装插件"
    }

    private var emptyMessage: String {
        if !searchText.isEmpty { return "请尝试其他名称或插件标识。" }
        return sourceCount == 0
            ? "添加订阅源后，这里会显示可安装的插件。"
            : "当前订阅源没有新的插件可安装。"
    }
}

private struct MacInstalledPluginRow: View {
    let pluginName: String
    let row: MacSettingsPluginRow
    let isManagementBusy: Bool
    let requestUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            row
            Menu {
                Button("卸载插件", role: .destructive, action: requestUninstall)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("插件操作")
            .accessibilityLabel("插件操作：\(pluginName)")
            .disabled(isManagementBusy)
        }
        .contentShape(Rectangle())
    }
}

/// Matches the existing settings/account rows while retaining catalog action semantics.
private struct MacSettingsPluginRow: View {
    let name: String
    let version: String
    let requiresLogin: Bool
    let state: RemotePluginCatalogActionState
    let icon: Image?
    let disabled: Bool
    let isWaiting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PanelIconTile {
                if let icon {
                    icon.resizable().scaledToFit().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(requiresLogin ? "\(version) · 需登录" : version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let reason) = state {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Spacer(minLength: 12)

            MacSettingsPluginAction(
                name: name, state: state, disabled: disabled,
                isWaiting: isWaiting, action: action
            )
        }
    }
}

private struct MacSettingsPluginAction: View {
    let name: String
    let state: RemotePluginCatalogActionState
    let disabled: Bool
    let isWaiting: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isWaiting {
                Text("等待更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                switch state {
                case .installed:
                    EmptyView()
                case .installing, .updating:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(state == .updating ? "更新中" : "安装中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .install, .update, .failed:
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(disabled)
                        .accessibilityLabel("\(actionTitle) \(name)")
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var actionTitle: String {
        switch state {
        case .install: "安装"
        case .failed: "重试"
        default: "更新"
        }
    }
}

private struct MacPluginEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var actionDisabled = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .disabled(actionDisabled)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.vertical, 10)
    }
}

private struct MacPluginSourcesView: View {
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.dismiss) private var dismiss

    let reloadCatalog: () async -> Void

    @State private var showAddSource = false
    @State private var pendingDeletion: MacSourceRemovalRequest?

    var body: some View {
        Form {
            Section {
                if pluginSourceManager.sourceURLs.isEmpty {
                    MacPluginEmptyState(
                        title: "暂无订阅源",
                        message: "添加订阅源后，会在这里显示健康状态与关联插件。",
                        systemImage: "dot.radiowaves.left.and.right",
                        actionTitle: "添加订阅源",
                        action: { showAddSource = true },
                        actionDisabled: pluginSourceManager.isManagementBusy
                    )
                } else {
                    ForEach(pluginSourceManager.sourceURLs, id: \.self) { url in
                        MacPluginSourceRow(
                            url: url,
                            health: pluginSourceManager.health(for: url),
                            retry: {
                                Task { await pluginSourceManager.refreshSource(url) }
                            },
                            remove: {
                                pendingDeletion = MacSourceRemovalRequest(url: url)
                            }
                        )
                        .disabled(pluginSourceManager.isManagementBusy)
                    }
                }
            } footer: {
                Text("展开可查看完整订阅地址。删除订阅源会同时移除它关联的插件。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("订阅源")
        .macSettingsPage("订阅源") {
            Button("添加订阅源", systemImage: "plus") {
                showAddSource = true
            }
            .disabled(pluginSourceManager.isManagementBusy)
        }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                MacPluginAddSourceView(reloadCatalog: reloadCatalog)
            }
            .macSettingsSheetPresentation()
            .frame(minWidth: 460, idealWidth: 520, minHeight: 280, idealHeight: 320)
        }
        .confirmationDialog(
            "删除订阅源？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { request in
            Button("删除“\(request.hostName)”", role: .destructive) {
                removeSource(request.url)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { request in
            Text("将删除 \(request.url)，并卸载该订阅源关联的插件。")
        }
    }

    private func removeSource(_ url: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            await pluginSourceManager.removeSourceAndAssociatedPlugins(url)
            await pluginAvailability.refresh()
            await reloadCatalog()
        }
    }
}

private struct MacSourceRemovalRequest: Identifiable {
    let url: String

    var id: String { url }

    var hostName: String {
        URL(string: url)?.host() ?? url
    }
}

private struct MacPluginSourceRow: View {
    let url: String
    let health: PluginSourceHealth
    let retry: () -> Void
    let remove: () -> Void

    private var hostName: String {
        URL(string: url)?.host() ?? url
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("订阅地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(url)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack {
                    Button("刷新订阅源", systemImage: "arrow.clockwise", action: retry)
                    Spacer()
                    Button("删除订阅源", role: .destructive, action: remove)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 12) {
                PanelIconTile {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hostName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    MacPluginSourceHealthText(health: health)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MacPluginSourceHealthText: View {
    let health: PluginSourceHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch health {
            case .unknown:
                Text("尚未检查")
                    .foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("检查中")
                }
                .foregroundStyle(.secondary)
            case .healthy(let count):
                Text("正常 · \(count) 个插件")
                    .foregroundStyle(.secondary)
            case .failed(let reason):
                Label("异常 · \(reason)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
    }
}

private struct MacPluginAddSourceView: View {
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss

    let reloadCatalog: () async -> Void

    @State private var inputURL = ""
    @State private var isAdding = false
    @State private var localError: String?

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                TextField("订阅源地址或兑换码", text: $inputURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSource)
            } footer: {
                Text("支持订阅源地址或兑换码。添加后可在订阅源列表中查看状态。")
            }
            if let localError {
                Section {
                    PluginSourceErrorCard(title: "添加失败", message: localError)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("添加订阅源")
        .macSettingsPage("添加订阅源", closeTitle: "取消", placesActionsAfterClose: true) {
                Button {
                    addSource()
                } label: {
                    HStack(spacing: 6) {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在添加…")
                        } else {
                            Image(systemName: "plus")
                            Text("添加")
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedURL.isEmpty || isAdding || pluginSourceManager.isManagementBusy)
        }
    }

    private func addSource() {
        guard !trimmedURL.isEmpty, !isAdding, !pluginSourceManager.isManagementBusy else { return }

        localError = nil
        isAdding = true
        let input = trimmedURL

        Task {
            let addedURLs = await pluginSourceManager.addSourceFromInput(input)
            if !addedURLs.isEmpty {
                inputURL = ""
                isAdding = false
                dismiss()
                Task { await reloadCatalog() }
            } else {
                localError = pluginSourceManager.errorMessage ?? "无法添加订阅源。"
                isAdding = false
            }
        }
    }
}

// Pure display inputs: previews never read installed plugins, credentials, or the network.
#Preview("插件设置行 · 原生表单基准") {
    Form {
        Section("已有设置行基准") {
            PanelNavigationRow(title: "账号管理", subtitle: "管理平台登录信息") {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        Section("插件行") {
            MacSettingsPluginRow(
                name: "示例插件", version: "版本 1.0.0", requiresLogin: true,
                state: .installed, icon: nil, disabled: false, isWaiting: false, action: {}
            )
            MacSettingsPluginRow(
                name: "较长的插件名称用于检查文字换行与控件对齐",
                version: "版本 1.0.0 → 1.1.0", requiresLogin: true,
                state: .update, icon: nil, disabled: false, isWaiting: false, action: {}
            )
            MacSettingsPluginRow(
                name: "正在更新的插件", version: "版本 1.0.0", requiresLogin: false,
                state: .updating, icon: nil, disabled: true, isWaiting: false, action: {}
            )
            MacSettingsPluginRow(
                name: "更新失败的插件", version: "版本 1.0.0", requiresLogin: false,
                state: .failed("无法连接订阅源，请检查网络连接后重试。"),
                icon: nil, disabled: false, isWaiting: false, action: {}
            )
        }
        Section("订阅源") {
            MacPluginSourceRow(
                url: "https://source.example.invalid/subscriptions/index.json",
                health: .healthy(pluginCount: 4), retry: {}, remove: {}
            )
        }
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 650)
}
