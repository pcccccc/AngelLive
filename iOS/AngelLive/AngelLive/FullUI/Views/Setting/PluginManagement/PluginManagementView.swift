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
    @State private var highlightedIDs: Set<String> = []
    @State private var feedback = PluginManagementFeedback()
    @State private var recordedInstallSuccessIDs: Set<String>?
    @State private var lastChecked: Date?
    @State private var refreshTask: Task<Void, Never>?
    @State private var playlistCount = PlaylistInstanceStore.shared.all().count

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

    var body: some View {
        List {
            Section {
                PluginManagementStatusCard(
                    manager: manager, installedIDs: availability.installedPluginIds,
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
        .environment(\.pluginConsentButton, { consentButtonID })
        .contentMargins(.horizontal, PluginManagementLayout.pageInset, for: .scrollContent)
        .contentMargins(.top, PluginManagementLayout.itemSpacing, for: .scrollContent)
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
        .safeAreaInset(edge: .bottom) {
            if let id = manager.pendingUninstallPluginId {
                PluginUninstallUndoBar(name: manager.managementDisplayName(for: id), deadline: manager.pendingUninstallDeadline, undo: { manager.undoPendingUninstall() })
                    .padding(.horizontal, PluginManagementLayout.pageInset).padding(.bottom, PluginManagementLayout.itemSpacing)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: manager.pendingUninstallPluginId)
        .task {
            consent.presentationDidAppear(consentHostID)
            await prepareIfNeeded()
            guard !Task.isCancelled else { return }
            refreshItems()
        }
        .onDisappear {
            commitPending(); consent.presentationDidDisappear(consentHostID)
            operationTask?.cancel()
            refreshTask?.cancel(); refreshTask = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { commitPending() } }
        .onChange(of: searchText) { _, _ in refreshItems() }
        .onChange(of: context.sourceURLs) { _, _ in refreshItems() }
        .onChange(of: manager.remotePlugins.map(\.item)) { _, _ in refreshItems() }
        .onChange(of: availability.catalogRevision) { _, _ in refreshItems() }
        .onChange(of: availability.installedPluginIds) { old, new in
            highlightedIDs.formUnion(Set(new).subtracting(old)); refreshItems()
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
        .onChange(of: manager.pendingUninstallPluginId) { _, pending in
            refreshItems()
            if pending == nil {
                refreshTask?.cancel()
                refreshTask = Task { await availability.refresh(); guard !Task.isCancelled else { return }; refreshItems() }
            }
        }
        .onChange(of: canOperate) { _, ready in
            if ready && !didPrepare {
                refreshTask = Task { await prepareIfNeeded(); guard !Task.isCancelled else { return }; refreshItems() }
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
            .environment(\.pluginConsentButton, { consentButtonID })
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ item: ManagedPluginItem) -> Bool {
            query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.pluginID.localizedCaseInsensitiveContains(query)
        }
        let catalog = manager.catalogPlugins(forSourceURLs: context.sourceURLs)
        func source(for id: String) -> String? {
            (context.sourceURLs ?? manager.sourceURLs).first { url in manager.catalogPlugins(forSourceURLs: [url]).contains { $0.id == id } }
        }
        let installed = availability.installedPluginIds.filter { $0 != manager.pendingUninstallPluginId }.map { id in
            ManagedPluginItem(pluginID: id, name: manager.managementDisplayName(for: id), sourceURL: source(for: id), remote: catalog.first { $0.id == id }, namespace: .installed)
        }.filter(matches)
        let batch = manager.installBatch
        let pendingInstallIDs = batch.isRunning ? batch.pluginIds.filter { batch.outcomes[$0] == nil } : []
        let retainedDiscoveryIDs = feedback.recentInstallIDs.union(pendingInstallIDs)
        let discovered = catalog.filter { manager.installedVersion(for: $0.id) == nil || retainedDiscoveryIDs.contains($0.id) }.map {
            ManagedPluginItem(pluginID: $0.id, name: $0.displayName, sourceURL: source(for: $0.id), remote: $0)
        }.filter(matches)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4)) {
            installedItems = installed; discoveredItems = discovered
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
        let ids = manager.catalogPlugins(forSourceURLs: context.sourceURLs)
            .filter { manager.installedVersion(for: $0.id) == nil }.map(\.id)
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
            lastChecked = Date(); refreshItems()
        }
    }
    private func retrySource(_ url: String) {
        guard canOperate, commitPending() else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            await installation.retrySource(url, context: context, manager: manager)
            guard !Task.isCancelled else { return }
            lastChecked = Date(); refreshItems()
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
        refreshItems()
    }
    private func stageUninstall(_ id: String) { guard canOperate else { return }; _ = manager.stageUninstall(pluginId: id) }
    @discardableResult private func commitPending() -> Bool { manager.commitPendingUninstall() }
}
