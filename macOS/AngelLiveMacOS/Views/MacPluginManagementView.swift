import AppKit
import SwiftUI
import AngelLiveCore

/// FullUI 的双栏管理界面；安装、更新和延迟卸载仍由共享服务持有。
struct MacPluginManagementView: View {
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: String?
    @State private var searchText = ""
    @State private var searchFocusRequest = 0
    @State private var showSources = false
    @State private var showAddSource = false
    @State private var loginPluginID: String?
    @State private var consentHostID = UUID()
    @State private var consentOrigin: MacPluginConsentOrigin?
    @State private var operationTask: Task<Void, Never>?
    @State private var refreshTask: Task<Void, Never>?
    @State private var lastChecked: Date?
    @State private var preparationError: String?
    @State private var pendingPreparationIDs: [String] = []
    @State private var recentSuccessIDs: Set<String> = []
    @State private var undoRegistration = MacPluginUndoRegistration()

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var installedIDs: [String] {
        availability.installedPluginIds.filter { $0 != manager.pendingUninstallPluginId }
    }
    private var installedItems: [MacManagedPlugin] {
        installedIDs.map { makeItem($0) }.filter(matches)
    }
    private var allDiscoveredItems: [MacManagedPlugin] {
        manager.remotePlugins.filter {
            manager.installedVersion(for: $0.id) == nil && $0.id != manager.pendingUninstallPluginId
        }.map { makeItem($0.id, remote: $0) }
    }
    private var discoveredItems: [MacManagedPlugin] { allDiscoveredItems.filter(matches) }
    private var discoverySourceLabels: [String: String] {
        let sources = Set(allDiscoveredItems.compactMap(\.sourceURL))
        guard sources.count > 1 else { return [:] }
        let byHost = Dictionary(grouping: sources) { URL(string: $0)?.host() ?? "" }
        var labels: [String: String] = [:]
        for source in sources {
            guard let url = URL(string: source), let host = url.host() else { continue }
            let tail = url.pathComponents.filter { $0 != "/" }.suffix(2).joined(separator: "/")
            labels[source] = byHost[host, default: []].count > 1 && !tail.isEmpty ? "\(host)/\(tail)" : host
        }
        let labelCounts = Dictionary(grouping: labels.values, by: { $0 }).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: allDiscoveredItems.compactMap { item in
            guard let source = item.sourceURL, let label = labels[source], labelCounts[label] == 1 else { return nil }
            return (item.id, label)
        })
    }
    private var visibleItems: [MacManagedPlugin] { installedItems + discoveredItems }
    private var selectedItem: MacManagedPlugin? { visibleItems.first { $0.id == selection } }
    private var updates: [String] { installedIDs.filter { manager.hasUpdate(for: $0) } }
    private var canOperate: Bool { operationTask == nil && !manager.isManagementBusy && !consent.isPresenting }
    private var successfulIDs: Set<String> {
        Set(manager.updateBatch.outcomes.compactMap { $0.value == .updated ? $0.key : nil })
            .union(manager.installBatch.outcomes.compactMap { $0.value == .installed ? $0.key : nil })
    }

    var body: some View {
        VStack(spacing: 0) {
            MacPluginManagementHeader(
                searchText: $searchText, searchFocusRequest: searchFocusRequest,
                showSources: $showSources, showAddSource: $showAddSource,
                canAdd: canOperate,
                lastChecked: lastChecked, preparationError: preparationError,
                installedIDs: installedIDs, update: { update(updates) },
                retry: retry, check: check, stop: stop,
                reloadCatalog: reloadCatalog, commitPending: commitPending
            )
            HSplitView {
                MacPluginSidebar(
                    selection: $selection, installed: installedItems, discovered: discoveredItems,
                    installedCount: installedIDs.count, query: query,
                    discoverySourceLabels: discoverySourceLabels,
                    canOperate: canOperate,
                    recentSuccessIDs: recentSuccessIDs,
                    clearSearch: { searchText = "" }, addSource: { showAddSource = true },
                    retrySources: check,
                    action: perform, uninstall: stageUninstall,
                    login: { loginPluginID = $0 }
                )
                .frame(
                    minWidth: MacPluginLayout.sidebarMinimumWidth,
                    idealWidth: MacPluginLayout.sidebarIdealWidth,
                    maxWidth: MacPluginLayout.sidebarMaximumWidth
                )
                .frame(maxHeight: .infinity)
                if let selectedItem {
                    MacPluginDetail(
                        item: selectedItem, canOperate: canOperate,
                        isSuccessful: recentSuccessIDs.contains(selectedItem.id),
                        action: { perform(selectedItem, $0) },
                        uninstall: { stageUninstall(selectedItem.id) },
                        login: { loginPluginID = selectedItem.id }
                    )
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    .id(selectedItem.id)
                } else {
                    MacPluginEmptyState(
                        title: query.isEmpty ? "选择一个插件" : "没有匹配的插件",
                        message: query.isEmpty ? "在左侧查看插件详情和可用操作。" : "请尝试其他名称或清除搜索。",
                        systemImage: query.isEmpty ? "puzzlepiece.extension" : "magnifyingglass",
                        actionTitle: query.isEmpty ? nil : "清除搜索",
                        action: query.isEmpty ? nil : { searchText = "" }
                    )
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            MacPluginManagementFooter(
                pendingName: manager.pendingUninstallPluginId.map { manager.managementDisplayName(for: $0) },
                deadline: manager.pendingUninstallDeadline,
                closeDisabled: consent.isPresenting, undo: undoUninstall, close: close
            )
        }
        .environment(\.macPluginConsentHost, consentHostID)
        .environment(\.macPluginConsentOrigin, $consentOrigin)
        .background(.background)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .frame(
            minWidth: MacPluginLayout.sheetMinimumWidth,
            idealWidth: MacPluginLayout.sheetIdealWidth,
            minHeight: MacPluginLayout.sheetMinimumHeight,
            idealHeight: MacPluginLayout.sheetIdealHeight
        )
        .interactiveDismissDisabled(consent.isPresenting)
        .focusedSceneValue(\.pluginManagementActions, MacPluginManagementActions(
            canUpdate: canOperate && !updates.isEmpty,
            canCheck: canOperate && !manager.sourceURLs.isEmpty,
            canAddSource: canOperate, canShowSources: !consent.isPresenting,
            canSearch: !consent.isPresenting,
            canUninstall: canOperate && selectedItem?.installed == true,
            update: { update(updates) }, check: check,
            addSource: { showSources = false; showAddSource = true },
            showSources: { showAddSource = false; showSources = true },
            search: { searchFocusRequest += 1 },
            uninstall: { if let selectedItem { stageUninstall(selectedItem.id) } }
        ))
        .onExitCommand(perform: escape)
        .sheet(isPresented: Binding(
            get: { loginPluginID != nil }, set: { if !$0 { loginPluginID = nil } }
        )) {
            NavigationStack { MacAccountManagementView(recoveryPluginIDs: loginPluginID.map { [$0] }) }
                .macSettingsSheetPresentation()
                .frame(minWidth: 600, minHeight: 480)
        }
        .onAppear { consent.presentationDidAppear(consentHostID) }
        .task { await reloadCatalog(); reconcileSelection() }
        .onChange(of: visibleItems.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: consent.isPresenting) { _, presenting in
            if presenting {
                showSources = false
                showAddSource = false
            }
        }
        .onChange(of: successfulIDs) { previous, current in
            recentSuccessIDs.formUnion(current.subtracting(previous))
        }
        .task(id: recentSuccessIDs) {
            guard !recentSuccessIDs.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            recentSuccessIDs = []
        }
        .onChange(of: manager.pendingUninstallPluginId) { previous, pending in
            if previous != nil && pending == nil {
                undoManager?.removeAllActions(withTarget: undoRegistration)
                undoRegistration.action = nil
                Task { await availability.refresh() }
            }
        }
        .onDisappear {
            _ = commitPending()
            undoManager?.removeAllActions(withTarget: undoRegistration)
            consent.presentationDidDisappear(consentHostID)
            operationTask?.cancel()
            refreshTask?.cancel()
        }
    }

    private func makeItem(_ id: String, remote: RemotePluginDisplayItem? = nil) -> MacManagedPlugin {
        let remote = remote ?? manager.remotePlugins.first { $0.id == id }
        let source = manager.sourceURLs.first { url in
            manager.catalogPlugins(forSourceURLs: [url]).contains { $0.id == id }
        }
        return MacManagedPlugin(
            id: id, name: manager.managementDisplayName(for: id), sourceURL: source,
            remote: remote, installed: manager.installedVersion(for: id) != nil
        )
    }

    private func matches(_ item: MacManagedPlugin) -> Bool {
        query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
            || item.id.localizedCaseInsensitiveContains(query)
    }

    private func reconcileSelection() {
        if !visibleItems.contains(where: { $0.id == selection }) { selection = visibleItems.first?.id }
    }

    private func perform(_ item: MacManagedPlugin, _ buttonID: UUID?) {
        if item.installed { update([item.id]); return }
        guard canOperate, commitPending() else { return }
        consentOrigin = buttonID.map { MacPluginConsentOrigin(buttonID: $0, pluginID: item.id) }
        preparationError = nil
        pendingPreparationIDs = []
        operationTask = Task {
            defer {
                consentOrigin = nil
                operationTask = nil
            }
            if item.remote == nil {
                await reloadCatalog()
                guard !Task.isCancelled else { return }
                guard manager.remotePlugins.contains(where: { $0.id == item.id }) else {
                    pendingPreparationIDs = [item.id]
                    preparationError = "当前来源没有这个插件，请刷新来源后重试。"
                    return
                }
            }
            _ = await manager.installPlugins(pluginIds: [item.id], sourceURLs: item.sourceURL.map { [$0] })
            await availability.refresh()
            guard !Task.isCancelled else { return }
            await manager.refreshAvailableUpdates()
        }
    }

    private func update(_ ids: [String]) {
        let ids = ids.filter { installedIDs.contains($0) && manager.hasUpdate(for: $0) }
        guard canOperate, !ids.isEmpty, commitPending() else { return }
        preparationError = nil
        pendingPreparationIDs = []
        operationTask = Task {
            defer { operationTask = nil }
            _ = await manager.updateAllPlugins(pluginIds: ids)
            await availability.refresh()
            guard !Task.isCancelled else { return }
            await manager.refreshAvailableUpdates()
        }
    }

    private func retry() {
        if !pendingPreparationIDs.isEmpty || !manager.installBatch.failedPluginIds.isEmpty {
            let ids = pendingPreparationIDs.isEmpty ? manager.installBatch.failedPluginIds : pendingPreparationIDs
            guard canOperate, commitPending() else { return }
            preparationError = nil
            operationTask = Task {
                defer { operationTask = nil }
                await manager.fetchAllSourceIndexes()
                guard !Task.isCancelled else { return }
                guard ids.allSatisfy({ id in manager.remotePlugins.contains { $0.id == id } }) else {
                    pendingPreparationIDs = ids
                    preparationError = "无法准备安装，部分插件已不在当前来源中。请刷新来源后重试。"
                    return
                }
                pendingPreparationIDs = []
                _ = await manager.installPlugins(pluginIds: ids)
                await availability.refresh()
            }
        } else if !manager.updateBatch.failedPluginIds.isEmpty {
            update(manager.updateBatch.failedPluginIds)
        } else { check() }
    }

    private func stop() {
        if consent.isPresenting { consent.resolve(false) }
        operationTask?.cancel()
    }

    private func check() {
        guard canOperate else { return }
        manager.errorMessage = nil
        preparationError = nil
        pendingPreparationIDs = []
        manager.updateBatch.clearResult()
        manager.installBatch.clearResult()
        refreshTask?.cancel()
        refreshTask = Task { await reloadCatalog(); refreshTask = nil }
    }

    private func reloadCatalog() async {
        guard !manager.isManagementBusy else { return }
        await manager.fetchAllSourceIndexes()
        guard !Task.isCancelled else { return }
        await manager.refreshAvailableUpdates()
        guard !Task.isCancelled else { return }
        lastChecked = Date()
    }

    private func stageUninstall(_ id: String) {
        guard canOperate else { return }
        let order = visibleItems.map(\.id)
        let index = order.firstIndex(of: id)
        guard manager.stageUninstall(pluginId: id) else { return }
        if selection == id, let index {
            selection = order.dropFirst(index + 1).first ?? order.prefix(index).last
        }
        undoRegistration.action = undoUninstall
        undoManager?.removeAllActions(withTarget: undoRegistration)
        undoManager?.registerUndo(withTarget: undoRegistration,
                                  selector: #selector(MacPluginUndoRegistration.undo(_:)), object: nil)
        undoManager?.setActionName("卸载插件")
    }

    private func undoUninstall() {
        guard let id = manager.pendingUninstallPluginId else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3)) {
            manager.undoPendingUninstall()
            selection = id
        }
        undoManager?.removeAllActions(withTarget: undoRegistration)
        undoRegistration.action = nil
    }

    @discardableResult private func commitPending() -> Bool {
        let success = manager.commitPendingUninstall()
        undoManager?.removeAllActions(withTarget: undoRegistration)
        undoRegistration.action = nil
        return success
    }

    private func close() {
        guard !consent.isPresenting, commitPending() else { return }
        dismiss()
    }

    private func escape() {
        if consent.isPresenting { consent.resolve(false) }
        else if showAddSource { showAddSource = false }
        else if showSources { showSources = false }
        else if !searchText.isEmpty { searchText = "" }
        else { close() }
    }
}

@MainActor
private final class MacPluginUndoRegistration: NSObject {
    var action: (() -> Void)?
    @objc func undo(_ object: Any?) { action?() }
}

/// 添加或编辑播放列表。添加前必须解析成功；名称必填，图标可选。
struct MacPlaylistEditorView: View {
    enum Mode {
        case add(sourceURL: String)
        case edit(PlaylistInstance)
    }

    enum IconState: Equatable { case none, loading, loaded, failed }

    let mode: Mode

    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.dismiss) private var dismiss

    @State private var sourceURL: String
    @State private var name: String
    @State private var iconURL: String
    @State private var preview: PlaylistPreview?
    @State private var previewError: String?
    @State private var isLoadingPreview = false
    @State private var iconState: IconState = .none
    @State private var isSaving = false
    @State private var saveError: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add(let url):
            _sourceURL = State(initialValue: url)
            _name = State(initialValue: "")
            _iconURL = State(initialValue: "")
        case .edit(let instance):
            _sourceURL = State(initialValue: instance.sourceURL)
            _name = State(initialValue: instance.name)
            _iconURL = State(initialValue: instance.iconURL ?? "")
        }
    }

    private var editingInstance: PlaylistInstance? {
        if case .edit(let instance) = mode { return instance }
        return nil
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedIcon: String { iconURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSource: String { sourceURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var sourceChanged: Bool {
        guard let editingInstance else { return true }
        return trimmedSource != editingInstance.sourceURL
    }

    private var hasChanges: Bool {
        guard let editingInstance else { return true }
        return trimmedName != editingInstance.name
            || trimmedIcon != (editingInstance.iconURL ?? "")
            || sourceChanged
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges && !isSaving && !isLoadingPreview
            && (!sourceChanged || preview != nil)
    }

    private var iconFileURL: URL? {
        guard !trimmedIcon.isEmpty, iconState == .loaded else { return nil }
        return PlaylistIconCache.cachedFileURL(
            for: PlaylistInstance(name: trimmedName, iconURL: trimmedIcon, sourceURL: trimmedSource)
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    PanelIconTile {
                        MacPlaylistIcon(
                            instance: nil,
                            name: trimmedName.isEmpty ? (preview?.title ?? "播") : trimmedName,
                            iconFileURL: iconFileURL,
                            size: 20
                        )
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trimmedName.isEmpty ? (preview?.title ?? "播放列表") : trimmedName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(previewSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isLoadingPreview {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            Section {
                TextField("地址", text: $sourceURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await loadPreview() } }
                TextField("平台名称", text: $name, prompt: Text("必填,例如:我的电视"))
                    .textFieldStyle(.roundedBorder)
                TextField("图标地址(可选)", text: $iconURL)
                    .textFieldStyle(.roundedBorder)
            } footer: {
                Text(iconFooter)
            }

            if let previewError {
                Section {
                    PluginSourceErrorCard(title: "无法读取播放列表", message: previewError)
                    Button("重试", systemImage: "arrow.clockwise") {
                        Task { await loadPreview() }
                    }
                    .disabled(isLoadingPreview)
                }
            }

            if let saveError {
                Section {
                    PluginSourceErrorCard(title: "无法保存", message: saveError)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editingInstance == nil ? "添加播放列表" : "编辑播放列表")
        .macSettingsPage(
            editingInstance == nil ? "添加播放列表" : "编辑播放列表",
            closeTitle: "取消",
            closeDisabled: isSaving,
            placesActionsAfterClose: true
        ) {
            Button(editingInstance == nil ? "添加" : "保存") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .task {
            if editingInstance == nil { await loadPreview() }
        }
        .task(id: trimmedIcon) { await loadIcon() }
        .onChange(of: sourceURL) { _, _ in
            preview = nil
            previewError = nil
        }
    }

    private var previewSummary: String {
        if isLoadingPreview { return "正在读取播放列表…" }
        if let preview { return "\(preview.channelCount) 个频道 · \(preview.groupCount) 个分组" }
        if previewError != nil { return "未能读取播放列表" }
        return "m3u 播放列表"
    }

    private var iconFooter: String {
        switch iconState {
        case .failed: "图标无法加载，将使用默认图标。内容由你添加的播放列表提供。"
        case .loading: "正在加载图标…"
        default: "图标留空时使用名称首字。内容由你添加的播放列表提供。"
        }
    }

    private func loadPreview() async {
        guard !trimmedSource.isEmpty else { return }
        isLoadingPreview = true
        previewError = nil
        defer { isLoadingPreview = false }
        do {
            preview = try await PlaylistPlatformService.shared.preview(sourceURL: trimmedSource)
        } catch {
            preview = nil
            previewError = PlaylistPlatformService.userMessage(for: error)
        }
    }

    private func loadIcon() async {
        guard !trimmedIcon.isEmpty else {
            iconState = .none
            return
        }
        iconState = .loading
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        iconState = await PlaylistIconCache.fetch(iconURL: trimmedIcon) ? .loaded : .failed
    }

    private func save() {
        guard canSave else { return }
        saveError = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            if sourceChanged, preview == nil {
                await loadPreview()
                guard preview != nil else { return }
            }
            do {
                let store = PlaylistInstanceStore.shared
                let reserved = Set(LiveParseJSPlatformManager.availablePlatforms
                    .filter { !PlaylistPlatformIdentity.isPlaylist($0.pluginId) }
                    .map(\.displayName))
                let instance: PlaylistInstance
                if let editingInstance {
                    instance = try store.update(
                        id: editingInstance.id, name: trimmedName, iconURL: trimmedIcon,
                        sourceURL: trimmedSource, reservedNames: reserved
                    )
                } else {
                    instance = try store.add(
                        name: trimmedName, iconURL: trimmedIcon,
                        sourceURL: trimmedSource, reservedNames: reserved
                    )
                }
                if sourceChanged, let preview {
                    await PlaylistPlatformService.shared.seed(preview, for: instance)
                }
                await pluginAvailability.checkAvailability()
                dismiss()
            } catch {
                saveError = (error as? LocalizedError)?.errorDescription ?? "无法保存播放列表。"
            }
        }
    }
}
