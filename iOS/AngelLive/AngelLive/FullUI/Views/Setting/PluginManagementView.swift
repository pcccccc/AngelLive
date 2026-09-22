//
//  PluginManagementView.swift
//  AngelLive
//
//  插件管理页面：显示已安装插件、管理订阅源、安装新插件。
//

import SwiftUI
import AngelLiveCore

private enum PluginManagementScope: String, CaseIterable, Identifiable {
    case installed
    case available

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .installed: "已安装"
        case .available: "可安装"
        }
    }
}

struct PluginManagementView: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager

    @State private var searchText = ""
    @State private var selectedScope: PluginManagementScope = .installed
    @State private var showAddSource = false
    @State private var pendingUninstallPluginID: String?

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsUpdateOverview: Bool {
        let batch = pluginSourceManager.updateBatch
        return batch.isRunning
            || !batch.pluginIds.isEmpty
            || pluginSourceManager.isInstalling
            || pluginSourceManager.installTotalCount > 0
            || pluginAvailability.installedPluginIds.contains { pluginSourceManager.hasUpdate(for: $0) }
            || pluginSourceManager.sourceURLs.contains { pluginSourceManager.health(for: $0).isFailed }
    }

    private var isUninstallConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingUninstallPluginID != nil },
            set: { isPresented in
                if !isPresented { pendingUninstallPluginID = nil }
            }
        )
    }

    var body: some View {
        List {
            PluginManagementScopeSection(selection: $selectedScope)

            if showsUpdateOverview {
                Section {
                    if pluginSourceManager.isInstalling,
                       pluginSourceManager.installTotalCount == 0 {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在安装插件")
                        }
                        .frame(minHeight: 44)
                    } else {
                        PluginUpdateOverview(
                            manager: pluginSourceManager,
                            installedPluginIds: pluginAvailability.installedPluginIds,
                            update: updatePlugins,
                            check: checkUpdates
                        )
                    }
                }
            }

            if pluginSourceManager.errorMessage != nil, !showAddSource {
                Section {
                    PluginManagementOperationError(manager: pluginSourceManager)
                }
            }

            PluginManagementPluginListSection(
                selectedScope: $selectedScope,
                searchText: normalizedSearch,
                update: updatePlugins,
                installAll: installAllAvailablePlugins,
                requestUninstall: { pendingUninstallPluginID = $0 },
                addSource: { showAddSource = true }
            )

            PluginManagementToolsSection(
                installedPluginIDs: pluginAvailability.installedPluginIds,
                showsCheckAction: !showsUpdateOverview,
                check: checkUpdates
            )
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .contentMargins(.top, 8, for: .scrollContent)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索插件"
        )
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("添加订阅源", systemImage: "plus") {
                    showAddSource = true
                }
                .disabled(pluginSourceManager.isManagementBusy)
                .accessibilityIdentifier("plugins.addSource")
            }
        }
        .task { await reloadCatalog() }
        .refreshable { await reloadCatalog() }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                PluginSourceAddView()
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: pluginAvailability.installedPluginIds) { _, _ in
            guard !pluginSourceManager.isManagementBusy else { return }
            Task { await reloadCatalog() }
        }
        .confirmationDialog(
            "卸载插件",
            isPresented: isUninstallConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let pluginID = pendingUninstallPluginID {
                Button(
                    "卸载 \(pluginSourceManager.managementDisplayName(for: pluginID))",
                    role: .destructive
                ) {
                    pendingUninstallPluginID = nil
                    uninstallPlugin(pluginID)
                }
            }
            Button("取消", role: .cancel) {
                pendingUninstallPluginID = nil
            }
        } message: {
            if let pluginID = pendingUninstallPluginID {
                Text("将移除插件「\(pluginSourceManager.managementDisplayName(for: pluginID))」及其本地数据。")
            }
        }
    }

    // MARK: - Actions

    private func updatePlugins(_ ids: [String]) {
        guard !ids.isEmpty, !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: ids)
            await pluginAvailability.refresh()
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }

    private func installAllAvailablePlugins() {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.installAll()
            await pluginAvailability.refresh()
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }

    private func uninstallPlugin(_ pluginID: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        _ = pluginSourceManager.uninstallPlugin(pluginId: pluginID)
        Task {
            await pluginAvailability.refresh()
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
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
}

private struct PluginManagementScopeSection: View {
    @Binding var selection: PluginManagementScope

    var body: some View {
        Section {
            Picker("插件范围", selection: $selection) {
                ForEach(PluginManagementScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("plugins.scope")
        }
    }
}

private struct PluginManagementToolsSection: View {
    @Environment(PluginSourceManager.self) private var manager
    let installedPluginIDs: [String]
    let showsCheckAction: Bool
    let check: () -> Void

    private var updateSummary: LocalizedStringResource {
        if manager.isFetchingIndex || manager.isCheckingUpdates {
            return "正在检查更新…"
        }
        if manager.sourceURLs.isEmpty {
            return "添加订阅源以获取更新"
        }
        if manager.sourceURLs.contains(where: { manager.health(for: $0).isFailed }) {
            return "部分订阅源未能检查"
        }
        let allSourcesChecked = manager.sourceURLs.allSatisfy {
            if case .healthy = manager.health(for: $0) { return true }
            return false
        }
        guard allSourcesChecked else { return "尚未检查更新" }
        guard !installedPluginIDs.isEmpty else { return "前往可安装列表选择插件" }
        let allInstalledPluginsChecked = installedPluginIDs.allSatisfy {
            manager.latestVersion(for: $0) != nil
        }
        return allInstalledPluginsChecked ? "插件均为最新版本" : "已完成检查"
    }

    var body: some View {
        Section("管理") {
            NavigationLink {
                PluginSourceListView()
            } label: {
                PluginManagementToolLabel(content: .sources(count: manager.sourceURLs.count))
            }
            .accessibilityIdentifier("plugins.sources")

            if showsCheckAction {
                Button(action: check) {
                    PluginManagementToolLabel(content: .updates(
                        summary: updateSummary,
                        isChecking: manager.isFetchingIndex || manager.isCheckingUpdates
                    ))
                }
                .buttonStyle(.plain)
                .disabled(manager.sourceURLs.isEmpty || manager.isManagementBusy)
                .accessibilityIdentifier("plugins.checkUpdates")
            }
        }
    }
}

private struct PluginManagementToolLabel: View {
    enum Content {
        case sources(count: Int)
        case updates(summary: LocalizedStringResource, isChecking: Bool)
    }

    let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                switch content {
                case .sources(let count):
                    Text("订阅源")
                        .foregroundStyle(.primary)
                    Text("\(count) 个订阅源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .updates(let summary, _):
                    Text("检查更新")
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if case .updates(_, true) = content {
                ProgressView()
                    .accessibilityLabel("正在检查更新")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch content {
        case .sources: "link"
        case .updates: "arrow.clockwise"
        }
    }
}

private struct PluginManagementPluginListSection: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager

    @Binding var selectedScope: PluginManagementScope
    let searchText: String
    let update: ([String]) -> Void
    let installAll: () -> Void
    let requestUninstall: (String) -> Void
    let addSource: () -> Void

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredInstalledPluginIDs: [String] {
        guard !normalizedSearch.isEmpty else { return pluginAvailability.installedPluginIds }
        return pluginAvailability.installedPluginIds.filter { pluginId in
            pluginMatchesSearch(
                name: pluginSourceManager.managementDisplayName(for: pluginId),
                pluginId: pluginId
            )
        }
    }

    private var availablePluginItems: [RemotePluginDisplayItem] {
        pluginSourceManager.remotePlugins.filter { item in
            guard pluginSourceManager.installedVersion(for: item.id) == nil else { return false }
            guard !normalizedSearch.isEmpty else { return true }
            return pluginMatchesSearch(name: item.displayName, pluginId: item.id)
        }
    }

    private var hasAvailablePlugins: Bool {
        pluginSourceManager.remotePlugins.contains {
            pluginSourceManager.installedVersion(for: $0.id) == nil
        }
    }

    private var hasInstallablePlugins: Bool {
        pluginSourceManager.remotePlugins.contains {
            pluginSourceManager.catalogActionState(for: $0) == .install
        }
    }

    var body: some View {
        Section {
            if selectedScope == .installed {
                installedPluginRows
            } else {
                availablePluginRows
            }
        } header: {
            HStack {
                if !normalizedSearch.isEmpty {
                    Text("找到 \(visiblePluginCount) 个插件")
                } else {
                    Text("\(visiblePluginCount) 个插件")
                }
                Spacer()
                if selectedScope == .available,
                   normalizedSearch.isEmpty,
                   hasInstallablePlugins {
                    Button("全部安装", systemImage: "arrow.down.circle") {
                        installAll()
                    }
                    .labelStyle(.titleAndIcon)
                    .frame(minHeight: 44)
                    .disabled(pluginSourceManager.isManagementBusy)
                }
            }
        }
    }

    private var visiblePluginCount: Int {
        selectedScope == .installed ? filteredInstalledPluginIDs.count : availablePluginItems.count
    }

    @ViewBuilder
    private var installedPluginRows: some View {
        if pluginAvailability.installedPluginIds.isEmpty {
            PluginManagementEmptyState(
                title: "暂无已安装插件",
                message: "从订阅源中选择你需要的插件。",
                actionTitle: "浏览可安装插件",
                action: { selectedScope = .available }
            )
        } else if filteredInstalledPluginIDs.isEmpty {
            PluginManagementEmptyState(
                title: "没有匹配的插件",
                message: "请尝试其他搜索词。"
            )
        } else {
            ForEach(filteredInstalledPluginIDs, id: \.self) { pluginID in
                installedPluginRow(pluginID)
            }
        }
    }

    @ViewBuilder
    private var availablePluginRows: some View {
        if !hasAvailablePlugins,
           pluginSourceManager.isFetchingIndex || pluginSourceManager.isCheckingUpdates {
            HStack(spacing: 12) {
                ProgressView()
                Text("正在获取插件…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
        } else if !hasAvailablePlugins {
            if pluginSourceManager.sourceURLs.isEmpty {
                PluginManagementEmptyState(
                    title: "暂无可安装插件",
                    message: "先添加订阅源以获取插件。",
                    actionTitle: "添加订阅源",
                    action: addSource
                )
            } else if pluginSourceManager.sourceURLs.contains(where: {
                pluginSourceManager.health(for: $0).isFailed
            }) {
                PluginManagementEmptyState(
                    title: "暂时无法获取插件",
                    message: "部分订阅源未能加载，请检查订阅源状态后重试。"
                )
            } else {
                PluginManagementEmptyState(
                    title: "暂无可安装插件",
                    message: "订阅源中暂时没有可安装的插件。"
                )
            }
        } else if availablePluginItems.isEmpty {
            PluginManagementEmptyState(
                title: "没有匹配的插件",
                message: "请尝试其他搜索词。"
            )
        } else {
            ForEach(availablePluginItems) { displayItem in
                managedPluginRow(pluginId: displayItem.id, remote: displayItem)
            }
        }
    }

    private func installedPluginRow(_ pluginID: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            managedPluginRow(pluginId: pluginID)
            Menu {
                Button("卸载插件", systemImage: "trash", role: .destructive) {
                    requestUninstall(pluginID)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.secondary)
            .disabled(pluginSourceManager.isManagementBusy)
            .accessibilityLabel("管理 \(pluginSourceManager.managementDisplayName(for: pluginID))")
        }
        .frame(minHeight: 60)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                requestUninstall(pluginID)
            } label: {
                Label("卸载", systemImage: "trash")
            }
            .disabled(pluginSourceManager.isManagementBusy)
        }
        .contextMenu {
            Button("卸载插件", systemImage: "trash", role: .destructive) {
                requestUninstall(pluginID)
            }
            .disabled(pluginSourceManager.isManagementBusy)
        }
        .accessibilityAction(named: Text("卸载插件")) {
            requestUninstall(pluginID)
        }
    }

    private func pluginMatchesSearch(name: String, pluginId: String) -> Bool {
        name.localizedCaseInsensitiveContains(normalizedSearch)
            || pluginId.localizedCaseInsensitiveContains(normalizedSearch)
    }

    private func managedPluginRow(
        pluginId: String,
        remote: RemotePluginDisplayItem? = nil
    ) -> some View {
        let installed = pluginSourceManager.installedVersion(for: pluginId)
        let latest = pluginSourceManager.latestVersion(for: pluginId)
        let version: String
        if let installed {
            if pluginSourceManager.hasUpdate(for: pluginId) {
                version = "版本 \(installed) · 可更新至 \(latest ?? installed)"
            } else {
                version = "版本 \(installed)"
            }
        } else {
            version = "版本 \(remote?.item.version ?? "未知")"
        }

        let state = pluginSourceManager.managementActionState(for: pluginId, remote: remote)
        let platform = LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == pluginId }
        let icon = platform
            .flatMap { PlatformIconProvider.pluginManagementImage(for: $0.liveType) }
            .map { Image(uiImage: $0) }
        let name = remote?.displayName ?? pluginSourceManager.managementDisplayName(for: pluginId)

        return PluginManagementPluginRow(
            name: name,
            version: version,
            requiresLogin: pluginAvailability.requiresLogin(for: pluginId)
                || remote?.item.auth?.required == true,
            state: state,
            icon: icon,
            disabled: pluginSourceManager.isManagementBusy,
            isWaiting: pluginSourceManager.isWaitingForUpdate(for: pluginId)
        ) {
            performPluginAction(pluginId: pluginId, remote: remote)
        }
    }

    private func performPluginAction(
        pluginId: String,
        remote: RemotePluginDisplayItem?
    ) {
        guard !pluginSourceManager.isManagementBusy else { return }

        if pluginSourceManager.installedVersion(for: pluginId) != nil {
            update([pluginId])
        } else if let remote {
            Task {
                _ = await pluginSourceManager.installPlugin(remote)
                await pluginAvailability.refresh()
                await pluginSourceManager.refreshAvailableUpdates()
            }
        }
    }
}

// MARK: - Subscription sources

private struct PluginSourceListView: View {
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @State private var showAddSource = false

    var body: some View {
        List {
            if pluginSourceManager.sourceURLs.isEmpty {
                PluginManagementEmptyState(
                    title: "暂无订阅源",
                    message: "添加订阅源后，这里会显示来源地址和健康状态。"
                )
            } else {
                Section {
                    ForEach(pluginSourceManager.sourceURLs, id: \.self) { url in
                        NavigationLink {
                            PluginSourceDetailView(sourceURL: url)
                        } label: {
                            PluginSourceListRow(
                                sourceURL: url,
                                health: pluginSourceManager.health(for: url)
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .contentMargins(.top, 16, for: .scrollContent)
        .navigationTitle("订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("添加订阅源", systemImage: "plus") {
                    showAddSource = true
                }
                .disabled(pluginSourceManager.isManagementBusy)
            }
        }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                PluginSourceAddView()
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct PluginSourceListRow: View {
    let sourceURL: String
    let health: PluginSourceHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pluginSourceHost(sourceURL))
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(sourceURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            PluginSourceHealthLabel(health: health)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sourceURL)，\(sourceHealthAccessibilityText(health))")
    }
}

private struct PluginSourceDetailView: View {
    let sourceURL: String

    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false
    @State private var showDeleteConfirmation = false

    private var health: PluginSourceHealth {
        pluginSourceManager.health(for: sourceURL)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pluginSourceHost(sourceURL))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    PluginSourceHealthLabel(health: health)
                    if case .failed(let reason) = health {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("订阅地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sourceURL)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

                Button {
                    refreshSource()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(isRefreshing ? "正在刷新…" : "刷新订阅源")
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if isRefreshing {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(pluginSourceManager.isManagementBusy || isRefreshing)
            }

            Section {
                Button("删除订阅源", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(pluginSourceManager.isManagementBusy)
            } footer: {
                Text("删除订阅源会卸载仅由它提供、且未被其他订阅源覆盖的已安装插件。")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .contentMargins(.top, 16, for: .scrollContent)
        .navigationTitle("订阅源详情")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "删除订阅源？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除并卸载关联插件", role: .destructive) {
                deleteSource()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除「\(pluginSourceHost(sourceURL))」，并卸载仅由它提供、未被其他订阅源覆盖的插件。")
        }
    }

    private func refreshSource() {
        guard !pluginSourceManager.isManagementBusy, !isRefreshing else { return }
        isRefreshing = true
        Task {
            _ = await pluginSourceManager.refreshSource(sourceURL)
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
            isRefreshing = false
        }
    }

    private func deleteSource() {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            await pluginSourceManager.removeSourceAndAssociatedPlugins(sourceURL)
            await pluginAvailability.refresh()
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
            dismiss()
        }
    }
}

private struct PluginSourceAddView: View {
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss

    @State private var inputURL = ""
    @State private var isProcessing = false

    var body: some View {
        Form {
            Section {
                TextField("输入订阅源地址或兑换码", text: $inputURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .submitLabel(.done)
                    .onSubmit(addSource)

                Button {
                    addSource()
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                            Text("添加中…")
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("添加订阅源")
                        }
                    }
                }
                .disabled(
                    inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isProcessing
                        || pluginSourceManager.isManagementBusy
                )

                if let error = pluginSourceManager.errorMessage {
                    PluginSourceErrorCard(title: "插件源异常", message: error)
                }
            } footer: {
                Text("输入包含插件索引的 JSON 地址或兑换码，添加后会自动检查插件更新。")
            }
        }
        .navigationTitle("添加订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
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
                isProcessing = false
                dismiss()
                Task {
                    await pluginSourceManager.fetchAllSourceIndexes()
                    await pluginSourceManager.refreshAvailableUpdates()
                }
                return
            }
            isProcessing = false
        }
    }
}

// MARK: - Shared source/list helpers

private struct PluginManagementEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringResource
    let actionTitle: LocalizedStringKey?
    let action: (() -> Void)?

    init(
        title: LocalizedStringKey,
        message: LocalizedStringResource,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct PluginSourceHealthLabel: View {
    let health: PluginSourceHealth

    var body: some View {
        HStack(spacing: 5) {
            if case .checking = health {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: sourceHealthSymbol(for: health))
                    .foregroundStyle(sourceHealthColor(for: health))
                    .accessibilityHidden(true)
            }
            Text(statusText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sourceHealthAccessibilityText(health))
    }

    private var statusText: LocalizedStringResource {
        switch health {
        case .unknown: "尚未检查"
        case .checking: "正在检查…"
        case .healthy(let count): "正常 · \(count) 个插件"
        case .failed: "订阅源异常"
        }
    }
}

private func pluginSourceHost(_ sourceURL: String) -> String {
    URL(string: sourceURL)?.host() ?? sourceURL
}

private func sourceHealthSymbol(for health: PluginSourceHealth) -> String {
    switch health {
    case .unknown: "questionmark.circle"
    case .checking: "arrow.triangle.2.circlepath"
    case .healthy: "checkmark.circle"
    case .failed: "exclamationmark.triangle"
    }
}

private func sourceHealthColor(for health: PluginSourceHealth) -> Color {
    switch health {
    case .unknown, .checking: .secondary
    case .healthy: .green
    case .failed: .orange
    }
}

private func sourceHealthAccessibilityText(_ health: PluginSourceHealth) -> String {
    switch health {
    case .unknown: "未检查"
    case .checking: "检查中"
    case .healthy(let count): "正常，包含 \(count) 个插件"
    case .failed(let reason): "异常，\(reason)"
    }
}
