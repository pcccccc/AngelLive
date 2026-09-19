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
            Section {
                PluginUpdateOverview(
                    manager: pluginSourceManager,
                    installedPluginIds: pluginAvailability.installedPluginIds,
                    update: updatePlugins,
                    check: checkUpdates
                )
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
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索插件"
        )
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink {
                    PluginSourceListView()
                } label: {
                    Label("订阅源", systemImage: "link")
                }

                Button("添加订阅源", systemImage: "plus") {
                    showAddSource = true
                }
                .disabled(pluginSourceManager.isManagementBusy)
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
            Picker("插件范围", selection: $selectedScope) {
                ForEach(PluginManagementScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            if selectedScope == .installed {
                installedPluginRows
            } else {
                availablePluginRows
            }
        } header: {
            HStack {
                Text(selectedScope.title)
                Spacer()
                if selectedScope == .available,
                   normalizedSearch.isEmpty,
                   hasInstallablePlugins {
                    Button("全部安装", systemImage: "arrow.down.circle") {
                        installAll()
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(pluginSourceManager.isManagementBusy)
                }
            }
        } footer: {
            if !normalizedSearch.isEmpty {
                switch selectedScope {
                case .installed:
                    Text("找到 \(filteredInstalledPluginIDs.count) 个匹配的插件")
                case .available:
                    Text("找到 \(availablePluginItems.count) 个匹配的插件")
                }
            }
        }
    }

    @ViewBuilder
    private var installedPluginRows: some View {
        if pluginAvailability.installedPluginIds.isEmpty {
            PluginManagementEmptyState(
                title: "暂无已安装插件",
                message: "安装完成的插件会显示在这里。"
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
        if !hasAvailablePlugins {
            if pluginSourceManager.sourceURLs.isEmpty {
                PluginManagementEmptyState(
                    title: "暂无可安装插件",
                    message: "先添加订阅源以获取插件。",
                    actionTitle: "添加订阅源",
                    action: addSource
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
        managedPluginRow(pluginId: pluginID)
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
                } header: {
                    Text("已添加的订阅源")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("订阅源")
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sourceHealthSymbol(for: health))
                .font(.title3)
                .foregroundStyle(sourceHealthColor(for: health))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(pluginSourceHost(sourceURL))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)
            PluginSourceHealthLabel(health: health)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pluginSourceHost(sourceURL))，\(sourceHealthAccessibilityText(health))")
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
            Section("订阅源") {
                LabeledContent("主机", value: pluginSourceHost(sourceURL))
                LabeledContent("地址") {
                    Text(sourceURL)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("状态") {
                HStack {
                    Text("当前状态")
                    Spacer()
                    PluginSourceHealthLabel(health: health)
                }

                if case .failed(let reason) = health {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    refreshSource()
                } label: {
                    Label("刷新订阅源", systemImage: "arrow.clockwise")
                }
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
        .navigationTitle("订阅源详情")
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
    let message: String
    let actionTitle: LocalizedStringKey?
    let action: (() -> Void)?

    init(
        title: LocalizedStringKey,
        message: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct PluginSourceHealthLabel: View {
    let health: PluginSourceHealth

    var body: some View {
        switch health {
        case .unknown:
            Label("未检查", systemImage: "questionmark.circle")
        case .checking:
            Label("检查中", systemImage: "arrow.triangle.2.circlepath")
        case .healthy(let count):
            Label("\(count) 个插件", systemImage: "checkmark.circle")
        case .failed:
            Label("异常", systemImage: "exclamationmark.triangle")
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
