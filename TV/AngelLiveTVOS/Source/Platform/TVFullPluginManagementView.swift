import SwiftUI
import AngelLiveCore

/// FullUI owns its shelf navigation and leaves the ShellUI entry points intact.
struct TVFullPluginManagementView: View {
    let pluginSourceManager: PluginSourceManager
    let pluginAvailability: PluginAvailabilityService
    let onClose: () -> Void

    @Environment(PluginInstallConsentService.self) private var consentService
    @Environment(AppState.self) private var appViewModel
    @State private var selectedPlugin: TVFullPluginSelection?
    @State private var showSources = false
    @State private var focusToRestore: TVFullPluginFocus = .summary
    @FocusState private var focusedAction: TVFullPluginFocus?
    @State private var operation: Task<Void, Never>?
    @State private var deferredUninstall: PluginDeferredUninstall
    @State private var hasChecked = false
    @State private var installedIDs: [String] = []
    @State private var availableIDs: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(pluginSourceManager: PluginSourceManager, pluginAvailability: PluginAvailabilityService,
         onClose: @escaping () -> Void = {}) {
        self.pluginSourceManager = pluginSourceManager
        self.pluginAvailability = pluginAvailability
        self.onClose = onClose
        // The television's remote undo affordance has its own six-second window.
        _deferredUninstall = State(initialValue: PluginDeferredUninstall(
            delay: .seconds(6),
            canUninstall: { id in
                pluginSourceManager.installedVersion(for: id) != nil && !pluginSourceManager.isManagementBusy
            },
            uninstall: { id in
                let removed = pluginSourceManager.uninstallPlugin(pluginId: id)
                if removed {
                    PluginAppGroupSync.syncToAppGroup()
                    Task { await pluginAvailability.refresh() }
                }
                return removed
            }
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVPluginLayout.sectionSpacing) {
                TVPluginManagementHeader(manager: pluginSourceManager, ids: installedIDs,
                    hasChecked: hasChecked, focus: $focusedAction,
                    summaryAction: performSummaryAction, check: checkUpdates, sources: openSources)
                TVPluginShelf(title: "已安装", ids: installedIDs, installed: true,
                    manager: pluginSourceManager, availability: pluginAvailability,
                    focus: $focusedAction, open: openPlugin, action: performPluginAction,
                    emptyAction: openSources)
                TVPluginShelf(title: "发现", ids: availableIDs, installed: false,
                    manager: pluginSourceManager, availability: pluginAvailability,
                    focus: $focusedAction, open: openPlugin, action: performPluginAction,
                    emptyAction: openSources)
                if let message = pluginSourceManager.errorMessage {
                    TVPluginEmptyState(title: "操作未完成", message: message,
                        actionTitle: "重试读取来源", action: checkUpdates)
                }
            }
            .padding(.horizontal, TVPluginLayout.pageMargin)
            .padding(.top, TVPluginLayout.topMargin)
            .padding(.bottom, TVPluginLayout.focusBleed)
        }
        .scrollClipDisabled()
        .toolbar(.hidden, for: .navigationBar)
        .defaultFocus($focusedAction, .summary)
        .onExitCommand {
            guard selectedPlugin == nil, !showSources else { return }
            closeManagement()
        }
        .ignoresSafeArea()
        .background(.background)
        .overlay(alignment: .topTrailing) {
            if let id = deferredUninstall.pendingUninstallPluginId,
               let deadline = deferredUninstall.pendingUninstallDeadline {
                TVPluginUndoNotice(name: pluginSourceManager.managementDisplayName(for: id), deadline: deadline)
                    .padding(TVPluginLayout.pageMargin)
            }
        }
        .overlay {
            if consentService.isPresenting && selectedPlugin == nil && !showSources {
                TVPluginConsentSurface(consent: consentService)
            }
        }
        .onPlayPauseCommand(perform: undoUninstall)
        .task {
            rebuildShelves()
            await reloadCatalog()
            if let action = appViewModel.pendingPluginManagementAction {
                appViewModel.pendingPluginManagementAction = nil
                await runAutoAction(action)
            }
        }
        .onChange(of: pluginAvailability.catalogRevision) { rebuildShelves() }
        .onChange(of: pluginSourceManager.remotePlugins.map(\.id)) { rebuildShelves() }
        .onChange(of: deferredUninstall.pendingUninstallPluginId) {
            rebuildShelves()
        }
        .fullScreenCover(item: $selectedPlugin, onDismiss: restoreManagementFocus) { selection in
            TVFullPluginDetailView(pluginID: selection.id, manager: pluginSourceManager,
                availability: pluginAvailability, initialFocus: selection.focus,
                performAction: performPluginAction, install: installPlugin, uninstall: stageUninstall,
                onClose: { selectedPlugin = nil })
                .background(.background)
                .environment(appViewModel)
                .environment(consentService)
        }
        .fullScreenCover(isPresented: $showSources, onDismiss: restoreManagementFocus) {
            TVFullPluginSourcesView(manager: pluginSourceManager,
                onClose: { showSources = false }, refreshCatalog: reloadCatalog,
                refreshAfterMutation: refreshAfterMutation, commitUninstall: commitUninstall)
                .background(.background)
                .environment(appViewModel)
        }
        .onDisappear {
            // Covers do not dismiss this owner; its actual departure flushes the intent.
            if selectedPlugin == nil && !showSources { commitUninstall() }
        }
    }

    private func rebuildShelves() {
        let pending = deferredUninstall.pendingUninstallPluginId
        var seen = Set<String>()
        installedIDs = pluginAvailability.installedPluginIds.filter {
            $0 != pending && pluginSourceManager.installedVersion(for: $0) != nil && seen.insert($0).inserted
        }
        seen.removeAll()
        availableIDs = pluginSourceManager.remotePlugins.compactMap {
            pluginSourceManager.installedVersion(for: $0.id) == nil && $0.id != pending &&
                seen.insert($0.id).inserted ? $0.id : nil
        }
    }

    private func openPlugin(_ id: String, _ focus: TVFullPluginFocus = .detailAction) {
        guard !pluginSourceManager.installBatch.isRunning, !consentService.isPresenting else { return }
        commitUninstall()
        focusToRestore = pluginSourceManager.installedVersion(for: id) == nil ? .available(id) : .installed(id)
        selectedPlugin = TVFullPluginSelection(id: id, focus: focus)
    }

    private func restoreManagementFocus() {
        switch focusToRestore {
        case .installed(let id) where !installedIDs.contains(id): focusedAction = .summary
        case .available(let id) where !availableIDs.contains(id): focusedAction = .summary
        default: focusedAction = focusToRestore
        }
    }

    private func openSources() {
        guard !pluginSourceManager.isManagementBusy, !consentService.isPresenting else { return }
        commitUninstall()
        focusToRestore = focusedAction ?? .sources
        showSources = true
    }

    private func closeManagement() {
        operation?.cancel()
        consentService.resolve(false)
        commitUninstall()
        onClose()
    }

    private func stageUninstall(_ id: String) {
        guard let index = installedIDs.firstIndex(of: id) else { return }
        let neighbor = index + 1 < installedIDs.count ? installedIDs[index + 1] :
            (index > 0 ? installedIDs[index - 1] : nil)
        guard deferredUninstall.stageUninstall(pluginId: id) else { return }
        focusToRestore = neighbor.map(TVFullPluginFocus.installed) ?? .summary
        withAnimation(reduceMotion ? nil : .default) { rebuildShelves() }
        selectedPlugin = nil
    }

    private func commitUninstall() {
        _ = deferredUninstall.commitPendingUninstall()
        _ = pluginSourceManager.commitPendingUninstall()
    }

    private func undoUninstall() {
        guard let id = deferredUninstall.pendingUninstallPluginId else { return }
        deferredUninstall.undoPendingUninstall()
        rebuildShelves()
        focusToRestore = .installed(id)
        focusedAction = .installed(id)
    }

    private func performSummaryAction() {
        let state = TVPluginStatus.resolve(manager: pluginSourceManager, ids: installedIDs, hasChecked: hasChecked)
        switch state {
        case .running: stopOperation()
        case .failed:
            let failed = pluginSourceManager.updateBatch.failedPluginIds
            if !failed.isEmpty {
                updatePlugins(failed)
            } else if !pluginSourceManager.installBatch.failedPluginIds.isEmpty {
                retryFailedInstalls()
            } else {
                checkUpdates()
            }
        case .updates: updatePlugins(installedIDs.filter { pluginSourceManager.hasUpdate(for: $0) })
        case .unchecked, .current: checkUpdates()
        case .checking: break
        }
    }

    private func stopOperation() {
        operation?.cancel()
        if consentService.isPresenting { consentService.resolve(false) }
    }

    private func checkUpdates() {
        guard !pluginSourceManager.isManagementBusy else { return }
        pluginSourceManager.updateBatch.clearResult()
        Task { await reloadCatalog() }
    }

    private func performPluginAction(_ id: String) {
        let phase = TVPluginStatus.phase(id, manager: pluginSourceManager)
        if phase == .progress || phase == .queued { stopOperation(); return }
        guard !pluginSourceManager.isManagementBusy else { return }
        if pluginSourceManager.installedVersion(for: id) != nil {
            if pluginSourceManager.hasUpdate(for: id) { updatePlugins([id]) }
        } else {
            openPlugin(id)
        }
    }

    private func installPlugin(_ id: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        commitUninstall()
        if pluginSourceManager.remotePlugins.first(where: { $0.id == id })?.item.auth?.required == true {
            consentService.approveNextLoginRequest(for: id)
        }
        operation = Task {
            defer { consentService.clearInlineApproval() }
            _ = await pluginSourceManager.installPlugins(pluginIds: [id])
            await refreshAfterMutation()
        }
    }

    private func retryFailedInstalls() {
        guard !pluginSourceManager.isManagementBusy else { return }
        let ids = pluginSourceManager.installBatch.failedPluginIds
        commitUninstall()
        operation = Task {
            _ = await pluginSourceManager.installPlugins(pluginIds: ids)
            await refreshAfterMutation()
        }
    }

    private func updatePlugins(_ ids: [String]) {
        guard !ids.isEmpty, !pluginSourceManager.isManagementBusy else { return }
        commitUninstall()
        operation = Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: ids)
            await refreshAfterMutation()
        }
    }

    private func reloadCatalog() async {
        guard !pluginSourceManager.isManagementBusy else { return }
        await pluginSourceManager.fetchAllSourceIndexes()
        await pluginSourceManager.refreshAvailableUpdates()
        hasChecked = !pluginSourceManager.sourceURLs.isEmpty &&
            !pluginSourceManager.sourceHealth.values.contains(where: \.isFailed)
        rebuildShelves()
    }

    private func refreshAfterMutation() async {
        PluginAppGroupSync.syncToAppGroup()
        await pluginAvailability.refresh()
        await pluginSourceManager.refreshAvailableUpdates()
        rebuildShelves()
    }

    private func runAutoAction(_ action: PluginManagementAutoAction) async {
        commitUninstall()
        switch action {
        case .oneClickInstall:
            await appViewModel.pluginSourceSyncService.performOneClickInstall(
                pluginSourceManager: pluginSourceManager, pluginAvailability: pluginAvailability,
                consentRequester: consentService)
        case .deepLinkInstall(let input):
            let added = await pluginSourceManager.addSourceFromInput(input)
            guard !added.isEmpty else { return }
            await pluginSourceManager.fetchAllSourceIndexes()
            _ = await pluginSourceManager.installAll()
        }
        await refreshAfterMutation()
    }
}

struct TVFullPluginSelection: Identifiable {
    let id: String
    var focus: TVFullPluginFocus = .detailAction
}

enum TVFullPluginFocus: Hashable {
    case summary, check, sources, addSource, installAll
    case installed(String), available(String)
    case detailAction, detailLogin, detailUninstall, detailBack
    case source(String), playlist(UUID), playlistName, playlistIcon, playlistURL
    case sourceAdd, sourceRefresh, sourceDelete, sourceDeleteAll, sourceBack, sourceEdit
    case inputField, inputAdd, inputCancel
}

private struct TVFullPluginDetailView: View {
    let pluginID: String
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let initialFocus: TVFullPluginFocus
    let performAction: (String) -> Void
    let install: (String) -> Void
    let uninstall: (String) -> Void
    let onClose: () -> Void

    @Environment(AppState.self) private var appViewModel
    @Environment(PluginInstallConsentService.self) private var consent
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    @FocusState private var focus: TVFullPluginFocus?
    @State private var showLogin = false

    private var remote: RemotePluginDisplayItem? { manager.remotePlugins.first { $0.id == pluginID } }
    private var installed: Bool { manager.installedVersion(for: pluginID) != nil }
    private var needsLogin: Bool { availability.requiresLogin(for: pluginID) || remote?.item.auth?.required == true }
    private var phase: PluginManagementRowPhase { TVPluginStatus.phase(pluginID, manager: manager) }

    var body: some View {
        TVFullDualColumnLayout {
            TVPluginDetailInformation(pluginID: pluginID, manager: manager, availability: availability,
                loggedIn: credentials.isLoggedIn(pluginId: pluginID))
        } right: {
            VStack(alignment: .leading, spacing: TVPluginLayout.actionSpacing) {
                TVPluginConfirmRow(title: primaryTitle, symbol: primarySymbol,
                    confirmation: consent.isPresenting || (!installed && needsLogin && (phase == .install || isInstallFailure))
                        ? "需要登录 · 再按一次继续安装" : nil,
                    destructive: false,
                    disabled: !consent.isPresenting && manager.isManagementBusy && phase != .progress && phase != .queued,
                    cancel: { if consent.isPresenting { consent.resolve(false) } },
                    action: primaryAction)
                    .focused($focus, equals: .detailAction)
                    .accessibilityIdentifier("plugins.detail.primary")
                if installed && needsLogin && !credentials.isLoggedIn(pluginId: pluginID) {
                    TVFullOperationRow(title: "登录账号", symbol: "person.crop.circle") { showLogin = true }
                        .focused($focus, equals: .detailLogin)
                }
                TVFullOperationRow(title: consent.isPresenting ? "取消安装并返回" : "返回",
                    symbol: "chevron.left", action: close)
                    .focused($focus, equals: .detailBack)
                if installed {
                    TVPluginConfirmRow(title: "卸载插件", symbol: "trash",
                        confirmation: "再按一次卸载", destructive: true,
                        disabled: manager.isManagementBusy, action: { uninstall(pluginID) })
                        .focused($focus, equals: .detailUninstall)
                        .padding(.top, TVPluginLayout.destructiveSpacing)
                        .accessibilityIdentifier("plugins.detail.uninstall")
                }
            }
            .focusSection()
        }
        .defaultFocus($focus, initialFocus)
        .onExitCommand {
            guard !showLogin else { return }
            close()
        }
        .onChange(of: consent.isPresenting) { _, presenting in
            if presenting { focus = .detailAction }
        }
        .onDisappear {
            if !showLogin && consent.isPresenting { consent.resolve(false) }
        }
        .fullScreenCover(isPresented: $showLogin, onDismiss: { focus = .detailLogin }) {
            AccountManagementView(recoveryPluginIDs: [pluginID])
                .padding(TVPluginLayout.pageMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .environment(appViewModel)
        }
    }

    private var isInstallFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var primaryTitle: String {
        if consent.isPresenting { return "需要登录 · 继续安装" }
        switch phase {
        case .install: return "安装"
        case .update: return "更新到 \(remote?.item.version ?? "")"
        case .queued, .progress: return "停止当前批次"
        case .failed: return installed ? "重试更新" : "重试安装"
        case .success, .idle: return "已是最新版本"
        }
    }

    private var primarySymbol: String {
        switch phase {
        case .queued, .progress: "stop.fill"
        case .failed: "arrow.clockwise"
        case .success, .idle: "checkmark"
        default: "arrow.down.circle"
        }
    }

    private func primaryAction() {
        if consent.isPresenting { consent.resolve(true); return }
        if installed { performAction(pluginID); return }
        if phase == .progress || phase == .queued { performAction(pluginID); return }
        guard remote != nil, !manager.isManagementBusy else { return }
        install(pluginID)
    }

    private func close() {
        if consent.isPresenting { consent.resolve(false) }
        onClose()
    }
}

private struct TVPluginDetailInformation: View {
    let pluginID: String
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let loggedIn: Bool
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var features: [PlatformFeature] = []

    var body: some View {
        let remote = manager.remotePlugins.first { $0.id == pluginID }
        let source = manager.sourceURLs.first { url in
            manager.catalogPlugins(forSourceURLs: [url]).contains { $0.id == pluginID }
        }
        VStack(alignment: .leading, spacing: TVPluginLayout.infoSpacing) {
            TVPluginManagementIcon(pluginID: pluginID, name: manager.managementDisplayName(for: pluginID),
                remote: remote?.item, size: TVPluginLayout.detailIcon,
                revision: availability.catalogRevision)
                .padding(.bottom, TVPluginLayout.infoSpacing)
            Text(manager.managementDisplayName(for: pluginID)).font(.title.bold()).lineLimit(1)
            Text("版本 \(manager.installedVersion(for: pluginID) ?? remote?.item.version ?? "未知")")
                .foregroundStyle(.secondary)
            if let host = source.flatMap({ URL(string: $0)?.host() }) {
                Text("来自 \(host)").foregroundStyle(.secondary).lineLimit(1)
            }
            Text(availability.requiresLogin(for: pluginID) || remote?.item.auth?.required == true
                ? (loggedIn ? "已登录" : "需要登录") : "不需要登录")
                .foregroundStyle(.secondary)
            if case .failed(let reason) = TVPluginStatus.phase(pluginID, manager: manager) {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(TVPluginLayout.failure).lineLimit(1)
            }
            if !features.isEmpty {
                TVPluginTagFlowLayout(spacing: TVPluginLayout.infoSpacing, layoutDirection: layoutDirection) {
                    ForEach(features, id: \.rawValue) { feature in
                        Text(feature.displayName).font(.caption).lineLimit(1)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: availability.catalogRevision) {
            features = PlatformCapability.declaredFeatures(forPluginId: pluginID) ?? []
        }
    }
}

/// Packs capability tags by their own width. Horizontal and vertical gaps share one spacing.
private struct TVPluginTagFlowLayout: Layout {
    let spacing: CGFloat
    let layoutDirection: LayoutDirection

    private struct Placement {
        let origins: [CGPoint]
        let sizes: [CGSize]
        let size: CGSize
    }

    private func placement(width: CGFloat?, subviews: Subviews) -> Placement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let limit = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        for size in sizes {
            if x > 0, let limit, x + size.width > limit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            contentWidth = max(contentWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        let reportedWidth = limit ?? contentWidth
        return Placement(origins: origins, sizes: sizes,
            size: CGSize(width: reportedWidth, height: sizes.isEmpty ? 0 : y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        placement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = placement(width: bounds.width, subviews: subviews)
        let isRightToLeft = layoutDirection == .rightToLeft
        for index in subviews.indices {
            let origin = placed.origins[index]
            subviews[index].place(
                at: CGPoint(x: isRightToLeft ? bounds.maxX - origin.x : bounds.minX + origin.x,
                            y: bounds.minY + origin.y),
                anchor: isRightToLeft ? .topTrailing : .topLeading,
                proposal: ProposedViewSize(placed.sizes[index])
            )
        }
    }
}

private struct TVFullPluginSourcesView: View {
    let manager: PluginSourceManager
    let onClose: () -> Void
    let refreshCatalog: () async -> Void
    let refreshAfterMutation: () async -> Void
    let commitUninstall: () -> Void
    @Environment(AppState.self) private var appViewModel
    @State private var selectedSource: TVFullSourceSelection?
    @State private var selectedPlaylist: PlaylistInstance?
    @State private var showAddSource = false
    @State private var playlists = PlaylistInstanceStore.shared.all()
    @FocusState private var focus: TVFullPluginFocus?
    @State private var savedFocus: TVFullPluginFocus = .sourceAdd

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVPluginLayout.sectionSpacing) {
                HStack {
                    Text("来源").font(.largeTitle.bold())
                        .padding(.leading, -TVPluginLayout.titleInkInset)
                    Spacer()
                    TVFullOperationRow(title: "添加来源", symbol: "plus") {
                        savedFocus = .sourceAdd
                        showAddSource = true
                    }
                    .frame(width: 340).focused($focus, equals: .sourceAdd)
                }
                VStack(alignment: .leading, spacing: TVPluginLayout.headingSpacing) {
                    TVFullPluginSectionHeader(title: "插件订阅源", count: manager.sourceURLs.count)
                    if manager.sourceURLs.isEmpty {
                        TVPluginEmptyState(title: "尚未添加订阅源", message: "用手机扫码输入订阅地址或兑换码。",
                            actionTitle: "添加来源", action: { showAddSource = true })
                    }
                    ForEach(manager.sourceURLs, id: \.self) { url in
                        TVFullOperationRow(title: URL(string: url)?.host() ?? url, symbol: "link",
                            trailing: sourceStatus(url),
                            trailingColor: manager.health(for: url).isFailed ? TVPluginLayout.failure : .secondary) {
                                savedFocus = .source(url)
                                selectedSource = TVFullSourceSelection(id: url)
                            }
                            .focused($focus, equals: .source(url))
                            .contextMenu {
                                Button("刷新", systemImage: "arrow.clockwise") {
                                    Task { _ = await manager.refreshSource(url) }
                                }.disabled(manager.isManagementBusy)
                                Button("查看详情", systemImage: "info.circle") {
                                    savedFocus = .source(url)
                                    selectedSource = TVFullSourceSelection(id: url)
                                }
                            }
                    }
                }.focusSection()
                VStack(alignment: .leading, spacing: TVPluginLayout.headingSpacing) {
                    TVFullPluginSectionHeader(title: "播放列表", count: playlists.count)
                    if playlists.isEmpty {
                        TVPluginEmptyState(title: "尚未添加播放列表", message: "支持 m3u 播放列表地址。",
                            actionTitle: "添加来源", action: { showAddSource = true })
                    }
                    ForEach(playlists) { instance in
                        TVFullOperationRow(title: instance.name, symbol: "list.and.film",
                            trailing: "播放列表") {
                                savedFocus = .playlist(instance.id)
                                selectedPlaylist = instance
                            }
                            .focused($focus, equals: .playlist(instance.id))
                    }
                }.focusSection()
                TVFullOperationRow(title: "返回", symbol: "chevron.left", action: onClose)
                    .frame(width: 520).focused($focus, equals: .sourceBack)
            }
            .padding(.horizontal, TVPluginLayout.pageMargin)
            .padding(.vertical, TVPluginLayout.topMargin)
        }
        .scrollClipDisabled()
        .toolbar(.hidden, for: .navigationBar)
        .defaultFocus($focus, .sourceAdd)
        .onExitCommand {
            guard selectedSource == nil, selectedPlaylist == nil, !showAddSource else { return }
            onClose()
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in
            playlists = PlaylistInstanceStore.shared.all()
        }
        .fullScreenCover(item: $selectedSource, onDismiss: restoreFocus) { selection in
            TVFullSourceDetailView(sourceURL: selection.id, manager: manager,
                refreshAfterMutation: refreshAfterMutation, commitUninstall: commitUninstall,
                onClose: { selectedSource = nil })
                .background(.background)
        }
        .fullScreenCover(item: $selectedPlaylist, onDismiss: restoreFocus) { instance in
            TVPlaylistDetailView(instance: instance, commitUninstall: commitUninstall,
                onClose: { selectedPlaylist = nil })
                .environment(appViewModel).background(.background)
        }
        .fullScreenCover(isPresented: $showAddSource, onDismiss: restoreFocus) {
            NavigationStack {
                TVFullPluginSourceInputView(onAdded: { Task { await refreshCatalog() } })
            }
            .environment(appViewModel).background(.background)
        }
    }

    private func restoreFocus() {
        if case .source(let url) = savedFocus, !manager.sourceURLs.contains(url) { savedFocus = .sourceAdd }
        if case .playlist(let id) = savedFocus, !playlists.contains(where: { $0.id == id }) { savedFocus = .sourceAdd }
        focus = savedFocus
    }

    private func sourceStatus(_ url: String) -> String {
        switch manager.health(for: url) {
        case .unknown: "未检查"
        case .checking: "检查中"
        case .healthy(let count): "\(count) 个插件"
        case .failed: "读取失败 · 查看详情"
        }
    }
}

private struct TVFullSourceSelection: Identifiable { let id: String }

private struct TVFullSourceDetailView: View {
    let sourceURL: String
    let manager: PluginSourceManager
    let refreshAfterMutation: () async -> Void
    let commitUninstall: () -> Void
    let onClose: () -> Void
    @FocusState private var focus: TVFullPluginFocus?
    @State private var isRefreshing = false
    var body: some View {
        TVFullDualColumnLayout {
            VStack(alignment: .leading, spacing: TVPluginLayout.infoSpacing) {
                Image(systemName: "link").font(.system(size: 72)).foregroundStyle(.secondary)
                Text(URL(string: sourceURL)?.host() ?? sourceURL).font(.title2.bold()).lineLimit(1)
                Text(sourceURL).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if case .failed(let reason) = manager.health(for: sourceURL) {
                    Text(reason).font(.callout).foregroundStyle(TVPluginLayout.failure).lineLimit(1)
                }
                Text("删除来源时可保留插件，或同时卸载仅由此来源提供的插件。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } right: {
            VStack(spacing: TVPluginLayout.actionSpacing) {
                TVFullOperationRow(title: isRefreshing ? "刷新中" : "刷新订阅源", symbol: "arrow.clockwise",
                    disabled: manager.isManagementBusy || isRefreshing) {
                        isRefreshing = true
                        Task {
                            _ = await manager.refreshSource(sourceURL)
                            await refreshAfterMutation()
                            isRefreshing = false
                        }
                    }.focused($focus, equals: .sourceRefresh)
                TVFullOperationRow(title: "返回", symbol: "chevron.left", action: onClose)
                    .focused($focus, equals: .sourceBack)
                TVPluginConfirmRow(title: "删除来源 · 保留插件", symbol: "trash",
                    confirmation: "再按一次删除来源", destructive: true,
                    disabled: manager.isManagementBusy || isRefreshing) {
                        commitUninstall()
                        manager.removeSource(sourceURL)
                        onClose()
                    }
                    .focused($focus, equals: .sourceDelete)
                    .padding(.top, TVPluginLayout.destructiveSpacing)
                TVPluginConfirmRow(title: "删除并卸载关联插件", symbol: "trash",
                    confirmation: "再按一次删除并卸载", destructive: true,
                    disabled: manager.isManagementBusy || isRefreshing) {
                        commitUninstall()
                        Task {
                            await manager.removeSourceAndAssociatedPlugins(sourceURL)
                            await refreshAfterMutation()
                            onClose()
                        }
                    }.focused($focus, equals: .sourceDeleteAll)
            }.focusSection()
        }
        .defaultFocus($focus, .sourceRefresh)
        .onExitCommand(perform: onClose)
    }
}

private struct TVPlaylistDetailView: View {
    let instance: PlaylistInstance
    let commitUninstall: () -> Void
    let onClose: () -> Void
    @Environment(AppState.self) private var appViewModel
    @State private var status: PlaylistRefreshStatus?
    @State private var isRefreshing = false
    @State private var isEditing = false
    @State private var message: String?
    @FocusState private var focus: TVFullPluginFocus?

    var body: some View {
        TVFullDualColumnLayout {
            VStack(alignment: .leading, spacing: TVPluginLayout.infoSpacing) {
                Image(systemName: "list.and.film").font(.system(size: 72)).foregroundStyle(.secondary)
                Text(instance.name).font(.title2.bold()).lineLimit(1)
                Text(instance.sourceURL).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let count = status?.channelCount {
                    Text("\(count) 个频道").font(.callout).foregroundStyle(.secondary)
                }
                if let error = message ?? status?.lastErrorMessage {
                    Text(error).font(.callout).foregroundStyle(TVPluginLayout.failure).lineLimit(1)
                }
            }
        } right: {
            VStack(spacing: TVPluginLayout.actionSpacing) {
                TVFullOperationRow(title: isRefreshing ? "正在刷新" : "刷新播放列表", symbol: "arrow.clockwise",
                    disabled: isRefreshing, action: refresh)
                    .focused($focus, equals: .sourceRefresh)
                TVFullOperationRow(title: "编辑播放列表", symbol: "pencil", disabled: isRefreshing) { isEditing = true }
                    .focused($focus, equals: .sourceEdit)
                TVFullOperationRow(title: "返回", symbol: "chevron.left", action: onClose)
                    .focused($focus, equals: .sourceBack)
                TVPluginConfirmRow(title: "删除播放列表", symbol: "trash", confirmation: "再按一次删除",
                    destructive: true, disabled: isRefreshing, action: remove)
                    .focused($focus, equals: .sourceDelete)
                    .padding(.top, TVPluginLayout.destructiveSpacing)
            }.focusSection()
        }
        .defaultFocus($focus, .sourceRefresh)
        .onExitCommand { if !isEditing { onClose() } }
        .task { status = await PlaylistPlatformService.shared.status(instanceID: instance.id) }
        .fullScreenCover(isPresented: $isEditing, onDismiss: { focus = .sourceEdit }) {
            TVPlaylistEditView(instance: instance, onSaved: onClose).environment(appViewModel).background(.background)
        }
    }

    private func refresh() {
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                _ = try await PlaylistPlatformService.shared.refresh(instanceID: instance.id)
                message = nil
            } catch { message = PlaylistPlatformService.userMessage(for: error) }
            status = await PlaylistPlatformService.shared.status(instanceID: instance.id)
        }
    }

    private func remove() {
        commitUninstall()
        Task {
            do {
                try PlaylistInstanceStore.shared.remove(id: instance.id)
                await PlaylistPlatformService.shared.removeCache(instanceID: instance.id)
                await appViewModel.pluginAvailability.checkAvailability()
                onClose()
            } catch { message = PlaylistPlatformService.userMessage(for: error) }
        }
    }
}

private struct TVPlaylistEditView: View {
    let instance: PlaylistInstance
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appViewModel
    @State private var name = ""
    @State private var icon = ""
    @State private var source = ""
    @State private var message: String?
    @State private var isSaving = false
    @FocusState private var focus: TVFullPluginFocus?

    var body: some View {
        TVFullDualColumnLayout {
            VStack(alignment: .leading, spacing: TVPluginLayout.infoSpacing) {
                Text("编辑播放列表").font(.title.bold())
                Text("可使用手机的远程输入页面填写名称和地址。").font(.callout).foregroundStyle(.secondary)
                let service = appViewModel.remoteInputService
                if service.isRunning && !service.localIPAddress.isEmpty {
                    Image(uiImage: Common.generateQRCode(from: "http://\(service.localIPAddress):\(service.port)/config"))
                        .resizable().interpolation(.none).scaledToFit().frame(width: 280, height: 280)
                }
                if let message { Text(message).font(.callout).foregroundStyle(TVPluginLayout.failure).lineLimit(1) }
            }
        } right: {
            VStack(spacing: TVPluginLayout.actionSpacing) {
                TextField("名称", text: $name).focused($focus, equals: .playlistName)
                TextField("播放列表地址", text: $source).focused($focus, equals: .playlistURL)
                TextField("图标地址（可选）", text: $icon).focused($focus, equals: .playlistIcon)
                TVPluginConfirmRow(title: isSaving ? "保存中" : "保存", symbol: "checkmark",
                    confirmation: "再按一次保存", disabled: isSaving, action: save)
                TVFullOperationRow(title: "取消", symbol: "chevron.left") { dismiss() }
            }.focusSection()
        }
        .defaultFocus($focus, .playlistName)
        .onExitCommand { dismiss() }
        .task { name = instance.name; icon = instance.iconURL ?? ""; source = instance.sourceURL }
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard let event = appViewModel.remoteInputService.lastEvent else { return }
            switch event.field {
            case .title: name = event.value
            case .url: if focus == .playlistIcon { icon = event.value } else { source = event.value }
            case .config: if let url = event.url { source = url }
            case .search, .cookie: break
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let preview = source != instance.sourceURL ? try await PlaylistPlatformService.shared.preview(sourceURL: source) : nil
                let reserved = Set(LiveParseJSPlatformManager.availablePlatforms
                    .filter { !PlaylistPlatformIdentity.isPlaylist($0.pluginId) }.map(\.displayName))
                let updated = try PlaylistInstanceStore.shared.update(id: instance.id, name: name,
                    iconURL: icon, sourceURL: source, reservedNames: reserved)
                if let preview { await PlaylistPlatformService.shared.seed(preview, for: updated) }
                if let icon = updated.iconURL, !icon.isEmpty { await PlaylistIconCache.fetch(iconURL: icon) }
                await appViewModel.pluginAvailability.checkAvailability()
                dismiss()
                onSaved()
            } catch { message = PlaylistPlatformService.userMessage(for: error) }
        }
    }
}

private struct TVFullPluginSourceInputView: View {
    let onAdded: () -> Void

    @Environment(AppState.self) private var appViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputURL = ""
    @State private var isProcessing = false
    @State private var localErrorMessage: String?
    @State private var playlistPreview: PlaylistPreview?
    @State private var playlistURL: String?
    @State private var playlistName = ""
    @State private var playlistIconURL = ""
    @FocusState private var focusedField: TVFullPluginFocus?

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        TVFullDualColumnLayout {
            explanationColumn
        } right: {
            inputColumn
        }
        .toolbar(.hidden, for: .navigationBar)
        .onExitCommand { dismiss() }
        .defaultFocus($focusedField, .inputField)
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard let event = appViewModel.remoteInputService.lastEvent else { return }
            switch event.field {
            case .url:
                if playlistURL != nil {
                    playlistIconURL = event.value
                } else {
                    inputURL = event.value
                }
            case .config:
                if let url = event.url { inputURL = url }
            case .title:
                if playlistURL != nil { playlistName = event.value }
            case .search, .cookie:
                break
            }
        }
    }

    private var explanationColumn: some View {
        VStack(spacing: TVPluginLayout.actionSpacing) {
            Text("添加订阅源")
                .font(.title2)
            remoteInputQRPanel
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var inputColumn: some View {
        if let playlistURL {
            playlistColumn(sourceURL: playlistURL)
        } else {
            sourceColumn
        }
    }

    /// 地址内容是 m3u 播放列表：填写平台名称（必填）与图标地址(可选)后添加。
    private func playlistColumn(sourceURL: String) -> some View {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: TVPluginLayout.actionSpacing) {
            TVFullPluginSectionHeader(title: "添加播放列表")
            if let preview = playlistPreview {
                // 与分区标题同一内容边距。
                Text("\(preview.channelCount) 个频道 · \(preview.groupCount) 个分组")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 30)
            }
            // 两个输入框固定同一字号与宽度，避免随内容长度各自缩放。
            TextField("平台名称(必填)", text: $playlistName)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("平台名称")
                .focused($focusedField, equals: .playlistName)
                .onSubmit { focusedField = .playlistIcon }
            TextField("图标地址(可选)", text: $playlistIconURL)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("图标地址(可选)")
                .focused($focusedField, equals: .playlistIcon)
                .onSubmit { focusedField = .inputAdd }

            if let localErrorMessage {
                Text(localErrorMessage)
                    .font(.callout)
                    .foregroundStyle(TVPluginLayout.failure)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TVFullOperationRow(
                title: isProcessing ? "添加中…" : "添加",
                symbol: "plus",
                disabled: trimmedName.isEmpty || isProcessing,
                action: { addPlaylist(sourceURL: sourceURL) }
            )
            .focused($focusedField, equals: .inputAdd)

            TVFullOperationRow(
                title: "取消",
                symbol: "chevron.left",
                action: { dismiss() }
            )
            .focused($focusedField, equals: .inputCancel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func addPlaylist(sourceURL: String) {
        guard !isProcessing else { return }
        localErrorMessage = nil
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                let preview: PlaylistPreview
                if let playlistPreview {
                    preview = playlistPreview
                } else {
                    preview = try await PlaylistPlatformService.shared.preview(sourceURL: sourceURL)
                }
                let reserved = Set(LiveParseJSPlatformManager.availablePlatforms
                    .filter { !PlaylistPlatformIdentity.isPlaylist($0.pluginId) }
                    .map(\.displayName))
                let icon = playlistIconURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let instance = try PlaylistInstanceStore.shared.add(
                    name: playlistName,
                    iconURL: icon,
                    sourceURL: sourceURL,
                    reservedNames: reserved
                )
                await PlaylistPlatformService.shared.seed(preview, for: instance)
                if !icon.isEmpty { await PlaylistIconCache.fetch(iconURL: icon) }
                await appViewModel.pluginAvailability.checkAvailability()
                onAdded()
                dismiss()
            } catch {
                localErrorMessage = PlaylistPlatformService.userMessage(for: error)
            }
        }
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: TVPluginLayout.actionSpacing) {
            TVFullPluginSectionHeader(title: "订阅地址、兑换码或 m3u 地址")
            TextField("输入订阅地址、兑换码或 m3u 地址", text: $inputURL)
                .accessibilityLabel("订阅地址、兑换码或 m3u 地址")
                .focused($focusedField, equals: .inputField)
                .onSubmit(handleAdd)

            if let error = localErrorMessage ?? appViewModel.pluginSourceManager.errorMessage,
               !error.isEmpty {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(TVPluginLayout.failure)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isProcessing {
                HStack(spacing: TVPluginLayout.actionSpacing) {
                    ProgressView()
                    Text("添加中…")
                        .font(.body)
                }
            }

            TVFullOperationRow(
                title: "添加",
                symbol: "plus",
                disabled: trimmedURL.isEmpty || isProcessing,
                action: handleAdd
            )
            .focused($focusedField, equals: .inputAdd)

            TVFullOperationRow(
                title: "取消",
                symbol: "chevron.left",
                action: { dismiss() }
            )
            .focused($focusedField, equals: .inputCancel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var remoteInputQRPanel: some View {
        let service = appViewModel.remoteInputService
        let url = "http://\(service.localIPAddress):\(service.port)/config"
        return VStack(spacing: TVPluginLayout.infoSpacing) {
            if service.isRunning && !service.localIPAddress.isEmpty {
                Image(uiImage: Common.generateQRCode(from: url))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: TVPluginLayout.qrSide, height: TVPluginLayout.qrSide)
                    .accessibilityLabel("扫码用手机输入")
                Text("扫码用手机输入")
                    .font(.headline)
                Text(url)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView()
                Text("正在启动远程输入…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleAdd() {
        let input = trimmedURL
        guard !input.isEmpty, !isProcessing else { return }
        localErrorMessage = nil
        isProcessing = true
        Task {
            let addedURLs: [String]
            switch await appViewModel.pluginSourceManager.addSourceOrDetectPlaylist(input) {
            case .playlist(let url):
                playlistPreview = try? await PlaylistPlatformService.shared.preview(sourceURL: url)
                isProcessing = false
                playlistURL = url
                focusedField = .playlistName
                return
            case .sources(let urls):
                addedURLs = urls
            }
            isProcessing = false
            if !addedURLs.isEmpty {
                inputURL = ""
                onAdded()
                dismiss()
            } else if appViewModel.pluginSourceManager.errorMessage == nil {
                localErrorMessage = "无法解析为订阅源，请确认地址或兑换码有效。"
            }
        }
    }
}
