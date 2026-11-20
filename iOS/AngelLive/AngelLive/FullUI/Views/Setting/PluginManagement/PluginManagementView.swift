import SwiftUI
import AngelLiveCore

struct PluginManagementView: View {
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginInstallationCoordinator.self) private var installation
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let entry: PluginInstallationEntry
    private let isPresentedModally: Bool
    @State private var searchText = ""
    @State private var showAddSource = false
    @State private var showSources = false
    @State private var detail: ManagedPluginItem?
    @State private var loginPluginID: String?
    @State private var didPrepare = false
    @State private var context = PluginInstallationContext()
    @State private var consentHostID = UUID()
    @State private var operationTask: Task<Void, Never>?
    @State private var installedItems: [ManagedPluginItem] = []
    @State private var discoveredItems: [ManagedPluginItem] = []
    @State private var installedInventory: [ManagedPluginItem] = []
    @State private var discoveredInventory: [ManagedPluginItem] = []
    @State private var catalog = PluginManagementCatalog()
    @State private var stagedUninstallID: String?
    @State private var hiddenInstalledIDs: Set<String> = []
    @State private var highlightedIDs: Set<String> = []
    @State private var feedback = PluginManagementFeedback()
    @State private var recordedInstallSuccessIDs: Set<String>?
    @State private var lastChecked: Date?
    @State private var refreshTask: Task<Void, Never>?
    @State private var playlistCount = PlaylistInstanceStore.shared.all().count
    @ScaledMetric(relativeTo: .subheadline) private var undoTextLineHeight: CGFloat = 20

    init(entry: PluginInstallationEntry = .management, isPresentedModally: Bool = false) {
        self.entry = entry
        self.isPresentedModally = isPresentedModally
    }
    private var canOperate: Bool { operationTask == nil && !manager.isManagementBusy && !installation.isPreparing && !installation.isInstalling }
    private var consentLocked: Bool { consent.isPresenting(for: consentHostID) }
    private var consentButtonID: UUID? {
        guard consentLocked, let origin = feedback.consentOrigin, origin.matches(consent.pendingReason) else { return nil }
        switch origin.surface {
        case .row:
            guard detail == nil,
                  installedItems.contains(where: { $0.id == origin.itemID }) || discoveredItems.contains(where: { $0.id == origin.itemID }) else { return nil }
        case .detail:
            guard detail?.id == origin.itemID else { return nil }
        }
        return origin.buttonID
    }
    private var installSuccessfulIDs: Set<String> { Set(manager.installBatch.pluginIds.filter { manager.installBatch.outcomes[$0] == .installed }) }
    private var updateSuccessfulIDs: Set<String> { Set(manager.updateBatch.pluginIds.filter { manager.updateBatch.outcomes[$0] == .updated }) }
    private var itemAnimation: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4) }

    private var observedItems: [ManagedPluginItem] {
        let items = installedInventory + discoveredInventory
        guard let detail, !items.contains(where: { $0.id == detail.id }) else { return items }
        return items + [detail]
    }

    var body: some View {
        List {
            Section {
                PluginManagementStatusCard(
                    manager: manager, installedItems: installedInventory, hiddenInstalledIDs: hiddenInstalledIDs,
                    isPreparing: installation.isPreparing, preparationTitle: context.preparationTitle,
                    preparationError: context.errorMessage, lastChecked: lastChecked, canStop: operationTask != nil,
                    update: { update($0) }, retryInstall: retryInstall, check: check,
                    retryPreparation: retryPreparation, stop: stop
                )
            }.listRowInsets(PluginManagementLayout.zeroInsets)
            if let urls = context.sourceURLs {
                PluginInstallationScopeNotice(sourceURLs: urls, showAll: showAllSources, retry: retrySource)
            }
            PluginInstalledSection(
                items: installedItems, highlightedIDs: highlightedIDs, searchIsEmpty: searchText.isEmpty,
                canOperate: canOperate,
                open: { detail = $0 }, action: { perform($0, buttonID: $1) },
                uninstall: stageUninstall, login: { if canOperate { loginPluginID = $0 } }
            )
            Section {
                PluginDiscoveryShelf(
                    items: discoveredItems, isLoading: installation.isPreparing || manager.isFetchingIndex,
                    hasSources: !(context.sourceURLs ?? manager.sourceURLs).isEmpty,
                    sourcesVerified: !(context.sourceURLs ?? manager.sourceURLs).isEmpty && (context.sourceURLs ?? manager.sourceURLs).allSatisfy { if case .healthy = manager.health(for: $0) { true } else { false } },
                    searchIsEmpty: searchText.isEmpty, canOperate: canOperate,
                    open: { detail = $0 }, action: { perform($0, buttonID: $1) }, addSource: { showAddSource = true }
                )
            } header: {
                PluginManagementSectionHeading(
                    title: "发现", subtitle: "来自你的订阅源",
                    actionTitle: searchText.isEmpty && discoveredItems.count > 1 ? "全部安装" : nil,
                    actionDisabled: !canOperate, action: installAll, includesSectionSpacing: true
                )
            }
            .listRowInsets(PluginManagementLayout.zeroInsets).listRowBackground(Color.clear)
            Section {
                Button { showSources = true } label: {
                    HStack(spacing: PluginManagementLayout.iconTextSpacing) {
                        PluginManagementToolIcon(symbol: "link", color: .gray)
                        Text("来源").foregroundStyle(.primary)
                        Spacer()
                        Text("\(manager.sourceURLs.count + playlistCount)").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }.frame(minHeight: PluginManagementLayout.minimumTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("plugins.sources")
                .disabled(!canOperate)
                .listRowInsets(EdgeInsets(top: PluginManagementLayout.itemSpacing, leading: PluginManagementLayout.contentInset, bottom: PluginManagementLayout.itemSpacing, trailing: PluginManagementLayout.contentInset))
            } header: { PluginManagementSectionGap() }
              footer: { PluginManagementFooter(text: "下拉页面检查更新") }
            .listRowInsets(PluginManagementLayout.zeroInsets)
        }
        .listStyle(.insetGrouped).listSectionSpacing(0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .tint(PluginManagementLayout.primaryAction)
        .environment(feedback)
        .environment(\.pluginConsentButtonID, consentButtonID)
        .contentMargins(.horizontal, PluginManagementLayout.pageInset, for: .scrollContent)
        .contentMargins(.top, PluginManagementLayout.itemSpacing, for: .scrollContent)
        .contentMargins(.bottom, max(44, undoTextLineHeight * 2) + 8 + PluginManagementLayout.itemSpacing,
                        for: .scrollContent)
        // Background content sits outside the list's environment modifiers, so inject explicitly.
        .background { PluginManagementRowUpdates(items: observedItems).environment(feedback) }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索插件")
        .navigationTitle("插件").navigationBarTitleDisplayMode(.large).fullUITabBarHidden()
        .navigationBarBackButtonHidden(consentLocked).interactiveDismissDisabled(consentLocked)
        .pluginInstallConsentAlert(consent, isActive: { consentLocked && detail == nil && consentButtonID == nil })
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { commitPending(); dismiss() }.disabled(consentLocked)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加来源", systemImage: "plus") { showAddSource = true }
                    .disabled(!canOperate).accessibilityIdentifier("plugins.addSource")
            }
        }
        .overlay(alignment: .bottom) {
            PluginPendingUninstallOverlay(animation: itemAnimation, reduceMotion: reduceMotion, undo: undoUninstall)
        }
        .task {
            consent.presentationDidAppear(consentHostID)
            await prepareIfNeeded()
            guard !Task.isCancelled else { return }
            refreshCatalog()
        }
        .onDisappear {
            commitPending(); consent.presentationDidDisappear(consentHostID)
            operationTask?.cancel()
            refreshTask?.cancel(); refreshTask = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { commitPending() } }
        .onChange(of: searchText) { _, _ in applySearch() }
        .onChange(of: context.sourceURLs) { _, _ in refreshCatalog() }
        .onChange(of: manager.sourceURLs) { _, _ in refreshCatalog() }
        .onChange(of: manager.sourceHealth) { _, _ in
            if !manager.isFetchingIndex { refreshCatalog() }
        }
        .onChange(of: manager.remotePlugins.map(ObjectIdentifier.init)) { _, _ in refreshCatalog() }
        .onChange(of: availability.installedPluginIds) { old, new in
            let previous = Set(old)
            let current = Set(new)
            highlightedIDs.formUnion(current.subtracting(previous))
            reconcileInventory(ids: current.symmetricDifference(previous))
        }
        .task(id: highlightedIDs) {
            guard !highlightedIDs.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(1800)) } catch { return }
            highlightedIDs = []
        }
        .onChange(of: installSuccessfulIDs) { _, _ in recordInstallSuccess() }
        .onChange(of: updateSuccessfulIDs) { old, new in feedback.recentSuccessIDs.formUnion(new.subtracting(old)) }
        .task(id: feedback.recentSuccessIDs) {
            guard !feedback.recentSuccessIDs.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            feedback.recentSuccessIDs = []
            feedback.recentInstallIDs = []
            refreshItems()
        }
        .onChange(of: manager.pendingUninstallPluginId) { old, _ in
            guard let old, old == stagedUninstallID else { return }
            stagedUninstallID = nil
            refreshAfterUninstall(old)
        }
        .onChange(of: canOperate) { _, ready in
            if ready && !didPrepare {
                refreshTask = Task { await prepareIfNeeded(); guard !Task.isCancelled else { return }; refreshCatalog() }
            }
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showAddSource) {
            NavigationStack {
                PluginSourceAddView { urls in
                    manager.installBatch.clearResult(); context.useSources(urls); searchText = ""
                    check()
                }
            }
            .environment(feedback)
        }
        .sheet(isPresented: $showSources) {
            NavigationStack { PluginSourceListView() }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $detail) { item in
            NavigationStack {
                PluginManagementDetailView(
                    item: item, canOperate: canOperate,
                    consentHostID: consentHostID, action: { perform(item, buttonID: $0, surface: .detail) },
                    uninstall: { stageUninstall($0); detail = nil }
                )
            }
            .pluginInstallConsentAlert(consent, isActive: { consentLocked && detail?.id == item.id && consentButtonID == nil })
            .environment(feedback)
            .environment(\.pluginConsentButtonID, consentButtonID)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .interactiveDismissDisabled(consentLocked)
        }
        .sheet(isPresented: Binding(get: { loginPluginID != nil }, set: { if !$0 { loginPluginID = nil } })) {
            NavigationStack { PlatformAccountLoginView(recoveryPluginIDs: loginPluginID.map { [$0] }) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in
            playlistCount = PlaylistInstanceStore.shared.all().count
        }
    }

    private func prepareIfNeeded() async {
        guard !didPrepare, canOperate else { return }
        didPrepare = true; commitPending()
        await installation.prepare(entry, context: context, manager: manager)
        if !Task.isCancelled { lastChecked = Date() }
    }
    private func refreshItems() {
        recordInstallSuccess()
        let installed = Set(availability.installedPluginIds)
        let retained = retainedDiscoveryIDs
        let installedSnapshot = availability.installedPluginIds.map(makeInstalledItem)
        let discoveredSnapshot = catalog.items.filter {
            retained.contains($0.pluginID) || (!installed.contains($0.pluginID) && manager.installedVersion(for: $0.pluginID) == nil)
        }
        if installedInventory != installedSnapshot { installedInventory = installedSnapshot }
        if discoveredInventory != discoveredSnapshot { discoveredInventory = discoveredSnapshot }
        applySearch()
    }

    private func refreshCatalog() {
        catalog = PluginManagementCatalog(manager: manager, scope: context.sourceURLs, feedback: feedback)
        refreshItems()
    }

    private func makeInstalledItem(_ id: String) -> ManagedPluginItem {
        let remote = catalog.item(for: id)
        return ManagedPluginItem(pluginID: id, name: manager.managementDisplayName(for: id),
                                 sourceURL: remote?.sourceURL, remote: remote?.remote, namespace: .installed,
                                 row: feedback.row(for: id, namespace: .installed))
    }

    private var retainedDiscoveryIDs: Set<String> {
        let batch = manager.installBatch
        let waiting = batch.isRunning ? batch.pluginIds.filter { batch.outcomes[$0] == nil } : []
        return feedback.recentInstallIDs.union(waiting)
    }

    private func reconcileInventory(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        recordInstallSuccess()
        let installed = Set(availability.installedPluginIds)
        let retained = retainedDiscoveryIDs
        var local = installedInventory
        var remote = discoveredInventory
        for id in ids {
            let isInstalled = installed.contains(id)
            local.replacePlugin(id, with: isInstalled ? makeInstalledItem(id) : nil) { $0.pluginID < $1.pluginID }
            let appearsInDiscovery = retained.contains(id) || (!isInstalled && manager.installedVersion(for: id) == nil)
            remote.replacePlugin(id, with: appearsInDiscovery ? catalog.item(for: id) : nil) {
                catalog.positions[$0.pluginID, default: .max] < catalog.positions[$1.pluginID, default: .max]
            }
        }
        if installedInventory != local { installedInventory = local }
        if discoveredInventory != remote { discoveredInventory = remote }
        applySearch()
    }

    private func applySearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ item: ManagedPluginItem) -> Bool {
            query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.pluginID.localizedCaseInsensitiveContains(query)
        }
        let pending = manager.pendingUninstallPluginId
        let installed = installedInventory.filter { $0.pluginID != pending && !hiddenInstalledIDs.contains($0.pluginID) && matches($0) }
        let discovered = discoveredInventory.filter(matches)
        withAnimation(itemAnimation) {
            if installedItems != installed { installedItems = installed }
            if discoveredItems != discovered { discoveredItems = discovered }
        }
    }
    private func recordInstallSuccess() {
        let previous = recordedInstallSuccessIDs
        let current = installSuccessfulIDs
        guard previous != current else { return }
        recordedInstallSuccessIDs = current
        guard let previous else { return }
        let completed = current.subtracting(previous)
        feedback.recentSuccessIDs.formUnion(completed)
        feedback.recentInstallIDs.formUnion(completed)
    }

    private func perform(_ item: ManagedPluginItem, buttonID: UUID?, surface: PluginActionConsentOrigin.Surface = .row) {
        guard canOperate else { return }
        let origin = buttonID.map { PluginActionConsentOrigin(buttonID: $0, itemID: item.id, pluginID: item.pluginID, surface: surface) }
        if manager.installedVersion(for: item.pluginID) != nil {
            update([item.pluginID], consentOrigin: origin)
            return
        }
        guard commitPending() else { return }
        feedback.consentOrigin = origin
        operationTask = Task {
            defer { feedback.consentOrigin = nil; operationTask = nil; refreshItems() }
            await installation.install(pluginIds: [item.pluginID], sourceURLs: item.sourceURL.map { [$0] } ?? context.sourceURLs, manager: manager, availability: availability)
        }
    }
    private func update(_ ids: [String], consentOrigin: PluginActionConsentOrigin? = nil) {
        guard canOperate, !ids.isEmpty else { return }
        guard commitPending() else { return }
        feedback.consentOrigin = consentOrigin
        operationTask = Task {
            defer { feedback.consentOrigin = nil; operationTask = nil; refreshItems() }
            _ = await manager.updateAllPlugins(pluginIds: ids)
            await availability.refresh(); await manager.refreshAvailableUpdates()
        }
    }
    private func retryInstall() {
        guard canOperate else { return }
        guard commitPending() else { return }
        operationTask = Task {
            defer { operationTask = nil; refreshItems() }
            await installation.retryFailed(manager: manager, availability: availability)
        }
    }
    private func installAll() {
        guard canOperate, commitPending() else { return }
        let ids = catalog.items.compactMap { item in
            manager.installedVersion(for: item.pluginID) == nil ? item.pluginID : nil
        }
        let sourceURLs = context.sourceURLs
        guard !ids.isEmpty else { return }
        operationTask = Task {
            defer { operationTask = nil; refreshItems() }
            await installation.install(pluginIds: ids, sourceURLs: sourceURLs, manager: manager, availability: availability)
        }
    }
    private func stop() { if consentLocked { consent.resolve(false) }; operationTask?.cancel() }
    private func check() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }
    private func retryPreparation() {
        guard canOperate, commitPending() else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            await installation.prepare(entry, context: context, manager: manager)
            guard !Task.isCancelled else { return }
            lastChecked = Date(); refreshCatalog()
        }
    }
    private func retrySource(_ url: String) {
        guard canOperate, commitPending() else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            await installation.retrySource(url, context: context, manager: manager)
            guard !Task.isCancelled else { return }
            lastChecked = Date(); refreshCatalog()
        }
    }
    private func showAllSources() { context.showAllSources(); searchText = ""; check() }
    private func refresh() async {
        guard canOperate, commitPending() else { return }
        if let urls = context.sourceURLs {
            await installation.prepare(.sources(urls), context: context, manager: manager, resetsResult: false)
        } else {
            await manager.fetchAllSourceIndexes(); await manager.refreshAvailableUpdates()
        }
        guard !Task.isCancelled else { return }
        lastChecked = Date()
        refreshCatalog()
    }

    private func stageUninstall(_ id: String, origin: PluginInstalledSection.UninstallOrigin = .action) {
        guard canOperate else { return }
        let previous = stagedUninstallID ?? manager.pendingUninstallPluginId
        func stageAndRemove() -> Bool {
            guard manager.stageUninstall(pluginId: id) else { return false }
            stagedUninstallID = id
            hiddenInstalledIDs.insert(id)
            installedItems.removeAll { $0.pluginID == id }
            return true
        }
        let staged = origin == .swipe ? stageAndRemove() : withAnimation(itemAnimation, stageAndRemove)
        if staged, let previous, previous != id { refreshAfterUninstall(previous) }
    }

    private func undoUninstall() {
        guard let id = manager.pendingUninstallPluginId else { return }
        stagedUninstallID = nil
        manager.undoPendingUninstall()
        hiddenInstalledIDs.remove(id)
        applySearch()
    }

    @discardableResult private func commitPending() -> Bool {
        guard let id = manager.pendingUninstallPluginId else { return true }
        stagedUninstallID = nil
        let committed = manager.commitPendingUninstall()
        refreshAfterUninstall(id)
        return committed
    }

    private func refreshAfterUninstall(_ id: String) {
        Task {
            await availability.refresh()
            if manager.pendingUninstallPluginId != id { hiddenInstalledIDs.remove(id) }
            reconcileInventory(ids: [id])
        }
    }
}

private struct PluginManagementCatalog {
    private(set) var items: [ManagedPluginItem] = []
    private(set) var positions: [String: Int] = [:]

    init() {}

    init(manager: PluginSourceManager, scope: [String]?, feedback: PluginManagementFeedback) {
        var sourcesByID: [String: String] = [:]
        for url in scope ?? manager.sourceURLs {
            for plugin in manager.catalogPlugins(forSourceURLs: [url]) where sourcesByID[plugin.id] == nil {
                sourcesByID[plugin.id] = url
            }
        }
        for plugin in manager.catalogPlugins(forSourceURLs: scope) where positions[plugin.id] == nil {
            positions[plugin.id] = items.count
            items.append(ManagedPluginItem(pluginID: plugin.id, name: plugin.displayName,
                                           sourceURL: sourcesByID[plugin.id], remote: plugin, namespace: .catalog,
                                           row: feedback.row(for: plugin.id, namespace: .catalog)))
        }
    }

    func item(for pluginID: String) -> ManagedPluginItem? {
        positions[pluginID].map { items[$0] }
    }
}

private extension Array where Element == ManagedPluginItem {
    mutating func replacePlugin(_ id: String, with item: ManagedPluginItem?,
                                orderedBy precedes: (ManagedPluginItem, ManagedPluginItem) -> Bool) {
        if let index = firstIndex(where: { $0.pluginID == id }) {
            if let item { self[index] = item } else { remove(at: index) }
        } else if let item {
            let index = firstIndex { precedes(item, $0) } ?? endIndex
            insert(item, at: index)
        }
    }
}

private struct PluginPendingUninstallOverlay: View {
    @Environment(PluginSourceManager.self) private var manager
    let animation: Animation
    let reduceMotion: Bool
    let undo: () -> Void

    var body: some View {
        Group {
            if let id = manager.pendingUninstallPluginId {
                PluginUninstallUndoBar(name: manager.managementDisplayName(for: id),
                                       deadline: manager.pendingUninstallDeadline, undo: undo)
                    .id(id)
                    .padding(.horizontal, PluginManagementLayout.pageInset)
                    .padding(.bottom, PluginManagementLayout.itemSpacing)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(animation, value: manager.pendingUninstallPluginId)
    }
}
