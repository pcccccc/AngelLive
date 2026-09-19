import SwiftUI
import AngelLiveCore

/// FullUI-only plugin management. ShellUI keeps its existing management page
/// and add-source surface in TVShellConfigView/TVAddPluginSourceView.
struct TVFullPluginManagementView: View {
    let pluginSourceManager: PluginSourceManager
    let pluginAvailability: PluginAvailabilityService
    let onClose: () -> Void

    @Environment(PluginInstallConsentService.self) private var consentService
    @Environment(AppState.self) private var appViewModel
    @State private var focusedPluginID: String?
    @State private var selectedPlugin: TVFullPluginSelection?
    @State private var showSources = false
    @State private var focusToRestore: TVFullPluginFocus?
    @FocusState private var focusedAction: TVFullPluginFocus?

    init(
        pluginSourceManager: PluginSourceManager,
        pluginAvailability: PluginAvailabilityService,
        onClose: @escaping () -> Void = {}
    ) {
        self.pluginSourceManager = pluginSourceManager
        self.pluginAvailability = pluginAvailability
        self.onClose = onClose
    }

    var body: some View {
        @Bindable var consent = consentService

        NavigationStack {
            TVFullDualColumnLayout {
                TVFullPluginSummary(
                    pluginID: focusedPluginID,
                    manager: pluginSourceManager,
                    availability: pluginAvailability
                )
            } right: {
                operationColumn
            }
            .navigationTitle("插件管理")
            .onExitCommand(perform: onClose)
            .defaultFocus($focusedAction, .check)
        }
        .background {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
        }
        .task {
            await reloadCatalog()
            if let action = appViewModel.pendingPluginManagementAction {
                appViewModel.pendingPluginManagementAction = nil
                await runAutoAction(action)
            }
        }
        .onChange(of: focusedAction) { _, newFocus in
            switch newFocus {
            case .installed(let id), .available(let id):
                focusedPluginID = id
            default:
                focusedPluginID = nil
            }
        }
        .onChange(of: selectedPlugin) { _, value in
            if value == nil {
                focusedAction = focusToRestore ?? .check
                focusToRestore = nil
            }
        }
        .fullScreenCover(item: $selectedPlugin) { selection in
            TVFullPluginDetailView(
                pluginID: selection.id,
                manager: pluginSourceManager,
                availability: pluginAvailability,
                performAction: performPluginAction,
                refreshAfterMutation: refreshAfterMutation,
                onClose: { selectedPlugin = nil }
            )
        }
        .fullScreenCover(isPresented: $showSources) {
            NavigationStack {
                TVFullPluginSourcesView(
                    manager: pluginSourceManager,
                    onClose: { showSources = false },
                    refreshCatalog: reloadCatalog,
                    refreshAfterMutation: refreshAfterMutation
                )
            }
            .environment(appViewModel)
        }
        .alert(
            consent.alertTitle,
            isPresented: Binding(
                get: { consent.isPresenting && selectedPlugin == nil && !showSources },
                set: { isPresented in
                    if !isPresented { consent.isPresenting = false }
                }
            )
        ) {
            Button(consent.continueButtonTitle) { consent.resolve(true) }
            Button("取消", role: .cancel) { consent.resolve(false) }
        } message: {
            Text(consent.alertMessage)
        }
        .onChange(of: showSources) { _, showing in
            if !showing {
                focusedAction = focusToRestore ?? .sources
                focusToRestore = nil
            }
        }
    }

    @ViewBuilder
    private var operationColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            TVFullOperationRow(
                title: "检查更新",
                symbol: "arrow.clockwise",
                disabled: pluginSourceManager.sourceURLs.isEmpty || pluginSourceManager.isManagementBusy,
                action: checkUpdates
            )
            .focused($focusedAction, equals: .check)

            if !updateIDs.isEmpty || pluginSourceManager.updateBatch.isRunning {
                TVFullOperationRow(
                    title: pluginSourceManager.updateBatch.isRunning ? "正在更新" : "全部更新",
                    symbol: "arrow.down.circle",
                    trailing: pluginSourceManager.updateBatch.isRunning ? updateProgressText : nil,
                    disabled: pluginSourceManager.isManagementBusy && !pluginSourceManager.updateBatch.isRunning,
                    action: updateAll
                )
                .focused($focusedAction, equals: .update)
            }

            TVFullOperationRow(
                title: "订阅源",
                symbol: "chevron.right",
                action: {
                    focusToRestore = focusedAction
                    showSources = true
                }
            )
            .focused($focusedAction, equals: .sources)

            Text("已安装")
                .font(.headline)
                .padding(.top, 15)

            if installedIDs.isEmpty {
                Text("尚未安装插件")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                installedRows
            }

            Text("可安装")
                .font(.headline)
                .padding(.top, 15)

            if availableItems.isEmpty {
                if pluginSourceManager.sourceURLs.isEmpty {
                    TVFullOperationRow(
                        title: "添加订阅源",
                        symbol: "plus",
                        action: {
                            focusToRestore = focusedAction
                            showSources = true
                        }
                    )
                    .focused($focusedAction, equals: .addSource)
                } else {
                    Text("当前订阅源暂无可安装插件")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !installableItems.isEmpty {
                    TVFullOperationRow(
                        title: "全部安装",
                        symbol: "square.and.arrow.down",
                        disabled: pluginSourceManager.isManagementBusy,
                        action: installAll
                    )
                    .focused($focusedAction, equals: .installAll)
                }
                availableRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    @ViewBuilder
    private var installedRows: some View {
        ForEach(installedIDs, id: \.self) { id in
            TVFullOperationRow(
                title: pluginSourceManager.managementDisplayName(for: id),
                symbol: "chevron.right",
                trailing: statusText(for: id),
                action: {
                    focusToRestore = focusedAction
                    selectedPlugin = TVFullPluginSelection(id: id)
                }
            )
            .focused($focusedAction, equals: .installed(id))
            .accessibilityIdentifier("plugins.item.\(id)")
        }
    }

    @ViewBuilder
    private var availableRows: some View {
        ForEach(availableItems) { item in
            TVFullOperationRow(
                title: item.displayName,
                symbol: "chevron.right",
                trailing: statusText(for: item.id),
                action: {
                    focusToRestore = focusedAction
                    selectedPlugin = TVFullPluginSelection(id: item.id)
                }
            )
            .focused($focusedAction, equals: .available(item.id))
            .accessibilityIdentifier("plugins.item.\(item.id)")
        }
    }

    private var installedIDs: [String] {
        pluginAvailability.installedPluginIds
    }

    private var availableItems: [RemotePluginDisplayItem] {
        pluginSourceManager.remotePlugins.filter {
            pluginSourceManager.installedVersion(for: $0.id) == nil
        }
    }

    private var updateIDs: [String] {
        installedIDs.filter { pluginSourceManager.hasUpdate(for: $0) }
    }

    private var installableItems: [RemotePluginDisplayItem] {
        availableItems.filter {
            pluginSourceManager.catalogActionState(for: $0) == .install
        }
    }

    private var updateProgressText: String {
        let batch = pluginSourceManager.updateBatch
        return "\(batch.completedCount)/\(batch.pluginIds.count)"
    }

    private func statusText(for id: String) -> String? {
        let remote = pluginSourceManager.remotePlugins.first { $0.id == id }
        if pluginSourceManager.isWaitingForUpdate(for: id) {
            return "等待更新"
        }
        switch pluginSourceManager.managementActionState(for: id, remote: remote) {
        case .install:
            return "安装"
        case .installing:
            return "安装中"
        case .update:
            return "可更新"
        case .updating:
            return "更新中"
        case .installed:
            return nil
        case .failed:
            return "失败"
        }
    }

    private func updateAll() {
        guard !updateIDs.isEmpty, !pluginSourceManager.isManagementBusy else { return }
        updatePlugins(updateIDs)
    }

    private func checkUpdates() {
        guard !pluginSourceManager.isManagementBusy else { return }
        pluginSourceManager.updateBatch.clearResult()
        Task { await reloadCatalog() }
    }

    private func performPluginAction(_ id: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        let remote = pluginSourceManager.remotePlugins.first { $0.id == id }
        switch pluginSourceManager.managementActionState(for: id, remote: remote) {
        case .install:
            guard let remote else { return }
            Task {
                _ = await pluginSourceManager.installPlugin(remote)
                await refreshAfterMutation()
            }
        case .failed:
            if pluginSourceManager.installedVersion(for: id) != nil {
                updatePlugins([id])
            } else if let remote {
                Task {
                    _ = await pluginSourceManager.installPlugin(remote)
                    await refreshAfterMutation()
                }
            }
        case .update:
            updatePlugins([id])
        case .installed, .installing, .updating:
            break
        }
    }

    private func updatePlugins(_ ids: [String]) {
        guard !ids.isEmpty, !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: ids)
            await refreshAfterMutation()
        }
    }

    private func installAll() {
        guard !installableItems.isEmpty, !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.installAll()
            await refreshAfterMutation()
        }
    }

    private func reloadCatalog() async {
        guard !pluginSourceManager.isManagementBusy else { return }
        await pluginSourceManager.fetchAllSourceIndexes()
        await pluginSourceManager.refreshAvailableUpdates()
    }

    private func refreshAfterMutation() async {
        PluginAppGroupSync.syncToAppGroup()
        await pluginAvailability.refresh()
        await pluginSourceManager.refreshAvailableUpdates()
    }

    private func runAutoAction(_ action: PluginManagementAutoAction) async {
        switch action {
        case .oneClickInstall:
            await appViewModel.pluginSourceSyncService.performOneClickInstall(
                pluginSourceManager: pluginSourceManager,
                pluginAvailability: pluginAvailability,
                consentRequester: consentService
            )
            await refreshAfterMutation()
        case .deepLinkInstall(let input):
            let added = await pluginSourceManager.addSourceFromInput(input)
            guard !added.isEmpty else { return }
            await pluginSourceManager.fetchAllSourceIndexes()
            _ = await pluginSourceManager.installAll()
            await refreshAfterMutation()
        }
    }
}

private struct TVFullPluginSelection: Identifiable, Equatable {
    let id: String
}

private struct TVFullActionPresentation: Equatable {
    let title: String
    let symbol: String
    let trailing: String?
    let isRunning: Bool
}

private enum TVFullPluginFocus: Hashable {
    case check
    case update
    case sources
    case addSource
    case installAll
    case installed(String)
    case available(String)
    case detailAction
    case detailUninstall
    case detailBack
    case source(String)
    case sourceAdd
    case sourceRefresh
    case sourceDelete
    case sourceBack
    case inputField
    case inputAdd
    case inputCancel
}

private struct TVFullOperationRow: View {
    let title: String
    let symbol: String
    let trailing: String?
    let disabled: Bool
    let action: () -> Void

    init(
        title: String,
        symbol: String,
        trailing: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Text(title)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 44)
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)
            .overlay(alignment: .trailing) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
        }
        .disabled(disabled)
        .accessibilityLabel(Text(title))
    }
}

private struct TVFullDualColumnLayout<Left: View, Right: View>: View {
    private let left: Left
    private let right: Right

    init(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView(.vertical) {
                    left
                        .padding(.horizontal, 90)
                        .padding(.top, 60)
                        .padding(.bottom, 60)
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)

                ScrollView(.vertical) {
                    right
                        .padding(.top, 60)
                        .padding(.bottom, 60)
                }
                .scrollClipDisabled()
                .frame(
                    width: geometry.size.width / 2 - 50,
                    height: geometry.size.height
                )
                .padding(.trailing, 50)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
        }
    }
}

private struct TVFullPluginSummary: View {
    let pluginID: String?
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let pluginID {
                pluginDetails(for: pluginID)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("插件管理")
                    .font(.title2)
                Text("选择右侧插件查看版本、状态和操作。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("已安装 \(availability.installedPluginIds.count) 个插件 · \(updateCount) 个可更新")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if manager.isFetchingIndex || manager.isCheckingUpdates {
                    ProgressView("正在检查更新…")
                        .font(.callout)
                }
                if manager.installTotalCount > 0 {
                    ProgressView(
                        value: Double(manager.installCompletedCount),
                        total: Double(max(1, manager.installTotalCount))
                    ) {
                        Text("正在安装插件")
                            .font(.callout)
                    } currentValueLabel: {
                        Text("\(manager.installCompletedCount)/\(manager.installTotalCount)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                if failedSourceCount > 0 {
                    Text("\(failedSourceCount) 个订阅源检查失败，请打开订阅源重试。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = manager.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("关闭提示") {
                        manager.errorMessage = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var updateCount: Int {
        availability.installedPluginIds.filter { manager.hasUpdate(for: $0) }.count
    }

    private var failedSourceCount: Int {
        manager.sourceHealth.values.filter(\.isFailed).count
    }

    @ViewBuilder
    private func pluginDetails(for id: String) -> some View {
        if let platform = LiveParseJSPlatformManager.availablePlatforms.first(where: { $0.pluginId == id }),
           let image = TVPlatformIconProvider.tabImage(for: platform.liveType) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }

        Text(manager.managementDisplayName(for: id))
            .font(.title2)
            .fixedSize(horizontal: false, vertical: true)

        if let remote = manager.remotePlugins.first(where: { $0.id == id }) {
            Text("版本 \(manager.installedVersion(for: id) ?? "未安装") · 远程 \(remote.item.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let description = remote.item.platformDescription,
               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if availability.requiresLogin(for: id) || remote.item.auth?.required == true {
                Label("需登录", systemImage: "person.crop.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let version = manager.installedVersion(for: id) {
            Text("版本 \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        if case .failed(let reason) = manager.managementActionState(
            for: id,
            remote: manager.remotePlugins.first(where: { $0.id == id })
        ) {
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TVFullPluginDetailView: View {
    let pluginID: String
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let performAction: (String) -> Void
    let refreshAfterMutation: () async -> Void
    let onClose: () -> Void

    @Environment(PluginInstallConsentService.self) private var consentService
    @FocusState private var focusedAction: TVFullPluginFocus?
    @State private var showUninstallConfirmation = false

    var body: some View {
        @Bindable var consent = consentService

        NavigationStack {
            TVFullDualColumnLayout {
                TVFullPluginSummary(
                    pluginID: pluginID,
                    manager: manager,
                    availability: availability
                )
            } right: {
                operationColumn
            }
            .navigationTitle("插件详情")
            .onExitCommand(perform: onClose)
            .defaultFocus($focusedAction, .detailBack)
        }
        .background {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "卸载插件",
            isPresented: $showUninstallConfirmation
        ) {
            Button("卸载 \(manager.managementDisplayName(for: pluginID))", role: .destructive) {
                guard !manager.isManagementBusy else { return }
                _ = manager.uninstallPlugin(pluginId: pluginID)
                Task {
                    await refreshAfterMutation()
                    onClose()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卸载后需要重新安装才能继续使用。")
        }
        .alert(consent.alertTitle, isPresented: $consent.isPresenting) {
            Button(consent.continueButtonTitle) { consent.resolve(true) }
            Button("取消", role: .cancel) { consent.resolve(false) }
        } message: {
            Text(consent.alertMessage)
        }
        .onChange(of: actionPresentation?.title) { oldTitle, newTitle in
            if oldTitle != nil, newTitle == nil {
                focusedAction = .detailBack
            }
        }
    }

    @ViewBuilder
    private var operationColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let actionPresentation {
                TVFullOperationRow(
                    title: actionPresentation.title,
                    symbol: actionPresentation.symbol,
                    trailing: actionPresentation.trailing,
                    disabled: manager.isManagementBusy && !actionPresentation.isRunning,
                    action: { performAction(pluginID) }
                )
                .focused($focusedAction, equals: .detailAction)
            }

            TVFullOperationRow(
                title: "返回",
                symbol: "chevron.left",
                action: onClose
            )
            .focused($focusedAction, equals: .detailBack)

            if manager.installedVersion(for: pluginID) != nil {
                Divider()
                    .padding(.vertical, 8)
                TVFullOperationRow(
                    title: "卸载插件",
                    symbol: "trash",
                    disabled: manager.isManagementBusy,
                    action: { showUninstallConfirmation = true }
                )
                .focused($focusedAction, equals: .detailUninstall)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var actionPresentation: TVFullActionPresentation? {
        let remote = manager.remotePlugins.first { $0.id == pluginID }
        switch manager.managementActionState(for: pluginID, remote: remote) {
        case .install:
            return TVFullActionPresentation(
                title: "安装",
                symbol: "arrow.down.circle",
                trailing: nil,
                isRunning: false
            )
        case .update:
            return TVFullActionPresentation(
                title: "更新",
                symbol: "arrow.down.circle",
                trailing: nil,
                isRunning: false
            )
        case .failed:
            return TVFullActionPresentation(
                title: "重试",
                symbol: "arrow.clockwise",
                trailing: nil,
                isRunning: false
            )
        case .installing:
            return TVFullActionPresentation(
                title: "安装中",
                symbol: "arrow.down.circle",
                trailing: "请稍候",
                isRunning: true
            )
        case .updating:
            return TVFullActionPresentation(
                title: "更新中",
                symbol: "arrow.down.circle",
                trailing: "请稍候",
                isRunning: true
            )
        case .installed:
            return nil
        }
    }
}

private struct TVFullPluginSourcesView: View {
    let manager: PluginSourceManager
    let onClose: () -> Void
    let refreshCatalog: () async -> Void
    let refreshAfterMutation: () async -> Void

    @State private var selectedSource: TVFullSourceSelection?
    @State private var showAddSource = false
    @State private var focusToRestore: TVFullPluginFocus?
    @FocusState private var focusedAction: TVFullPluginFocus?

    var body: some View {
        TVFullDualColumnLayout {
            TVFullSourceSummary(manager: manager)
        } right: {
            sourceOperationColumn
        }
        .navigationTitle("订阅源")
        .onExitCommand(perform: onClose)
        .defaultFocus($focusedAction, .sourceAdd)
        .fullScreenCover(item: $selectedSource) { selection in
            NavigationStack {
                TVFullSourceDetailView(
                    sourceURL: selection.id,
                    manager: manager,
                    refreshAfterMutation: refreshAfterMutation,
                    deleteSource: deleteSource,
                    onClose: { selectedSource = nil }
                )
            }
        }
        .fullScreenCover(isPresented: $showAddSource) {
            NavigationStack {
                TVFullPluginSourceInputView()
            }
            .environment(appViewModel)
        }
        .onChange(of: selectedSource) { _, value in
            if value == nil {
                focusedAction = focusToRestore ?? .sourceAdd
                focusToRestore = nil
            }
        }
        .onChange(of: showAddSource) { _, showing in
            if !showing {
                Task { await refreshCatalog() }
            }
        }
    }

    @Environment(AppState.self) private var appViewModel

    @ViewBuilder
    private var sourceOperationColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            TVFullOperationRow(
                title: "添加订阅源",
                symbol: "plus",
                disabled: manager.isManagementBusy,
                action: {
                    focusToRestore = focusedAction
                    showAddSource = true
                }
            )
            .focused($focusedAction, equals: .sourceAdd)

            if manager.sourceURLs.isEmpty {
                Text("尚未添加订阅源")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.sourceURLs, id: \.self) { url in
                    TVFullOperationRow(
                        title: sourceHost(for: url),
                        symbol: "chevron.right",
                        trailing: sourceStatus(for: url),
                        action: {
                            focusToRestore = focusedAction
                            selectedSource = TVFullSourceSelection(id: url)
                        }
                    )
                    .focused($focusedAction, equals: .source(url))
                    .accessibilityIdentifier("plugins.source.\(url)")
                }
            }

            TVFullOperationRow(
                title: "返回",
                symbol: "chevron.left",
                action: onClose
            )
            .focused($focusedAction, equals: .sourceBack)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func sourceHost(for url: String) -> String {
        URL(string: url)?.host() ?? url
    }

    private func sourceStatus(for url: String) -> String {
        switch manager.health(for: url) {
        case .unknown:
            return "未检查"
        case .checking:
            return "检查中"
        case .healthy(let count):
            return "\(count) 个插件"
        case .failed:
            return "异常"
        }
    }

    private func deleteSource(_ url: String) async {
        guard !manager.isManagementBusy else { return }
        await manager.removeSourceAndAssociatedPlugins(url)
        await refreshAfterMutation()
        await refreshCatalog()
    }
}

private struct TVFullSourceSelection: Identifiable, Equatable {
    let id: String
}

private struct TVFullSourceSummary: View {
    let manager: PluginSourceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "link")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("订阅源")
                .font(.title2)
            Text("管理插件目录的来源。选择右侧订阅源查看健康状态、刷新或删除。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = manager.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TVFullSourceDetailView: View {
    let sourceURL: String
    let manager: PluginSourceManager
    let refreshAfterMutation: () async -> Void
    let deleteSource: (String) async -> Void
    let onClose: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var isRefreshing = false
    @FocusState private var focusedAction: TVFullPluginFocus?

    var body: some View {
        TVFullDualColumnLayout {
            sourceSummary
        } right: {
            operationColumn
        }
        .navigationTitle("订阅源详情")
        .onExitCommand(perform: onClose)
        .defaultFocus($focusedAction, .sourceRefresh)
        .confirmationDialog("删除订阅源", isPresented: $showDeleteConfirmation) {
            Button("删除并卸载关联插件", role: .destructive) {
                Task {
                    await deleteSource(sourceURL)
                    onClose()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除订阅源后，只由此源提供且没有其他来源覆盖的插件也会被移除。")
        }
    }

    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: manager.health(for: sourceURL).isFailed ? "exclamationmark.circle" : "link")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(URL(string: sourceURL)?.host() ?? sourceURL)
                .font(.title2)
                .fixedSize(horizontal: false, vertical: true)
            Text(sourceURL)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch manager.health(for: sourceURL) {
            case .unknown:
                Text("尚未检查")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView("检查中")
            case .healthy(let count):
                Text("包含 \(count) 个插件")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var operationColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            TVFullOperationRow(
                title: "刷新订阅源",
                symbol: "arrow.clockwise",
                disabled: manager.isManagementBusy || isRefreshing || manager.health(for: sourceURL) == .checking,
                action: {
                    guard !isRefreshing, manager.health(for: sourceURL) != .checking else { return }
                    isRefreshing = true
                    Task {
                        _ = await manager.refreshSource(sourceURL)
                        await refreshAfterMutation()
                        isRefreshing = false
                    }
                }
            )
            .focused($focusedAction, equals: .sourceRefresh)

            TVFullOperationRow(
                title: "删除订阅源",
                symbol: "trash",
                disabled: manager.isManagementBusy || isRefreshing || manager.health(for: sourceURL) == .checking,
                action: { showDeleteConfirmation = true }
            )
            .focused($focusedAction, equals: .sourceDelete)

            TVFullOperationRow(
                title: "返回",
                symbol: "chevron.left",
                action: onClose
            )
            .focused($focusedAction, equals: .sourceBack)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

private struct TVFullPluginSourceInputView: View {
    @Environment(AppState.self) private var appViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputURL = ""
    @State private var isProcessing = false
    @State private var localErrorMessage: String?
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
        .navigationTitle("添加订阅源")
        .onExitCommand { dismiss() }
        .defaultFocus($focusedField, .inputField)
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard let event = appViewModel.remoteInputService.lastEvent else { return }
            switch event.field {
            case .url:
                inputURL = event.value
            case .config:
                if let url = event.url { inputURL = url }
            case .title, .search, .cookie:
                break
            }
        }
    }

    private var explanationColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("添加订阅源")
                .font(.title2)
            Text("输入插件订阅地址或兑换码。添加后会刷新插件目录；暂时无法访问的地址也会保留并显示异常。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            remoteInputQRPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            TextField("输入订阅地址或兑换码", text: $inputURL)
                .focused($focusedField, equals: .inputField)
                .onSubmit(handleAdd)

            if let error = localErrorMessage ?? appViewModel.pluginSourceManager.errorMessage,
               !error.isEmpty {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isProcessing {
                HStack(spacing: 15) {
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
        return VStack(alignment: .leading, spacing: 12) {
            if service.isRunning && !service.localIPAddress.isEmpty {
                Image(uiImage: Common.generateQRCode(from: url))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
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
            let addedURLs = await appViewModel.pluginSourceManager.addSourceFromInput(input)
            isProcessing = false
            if !addedURLs.isEmpty {
                inputURL = ""
                dismiss()
            } else if appViewModel.pluginSourceManager.errorMessage == nil {
                localErrorMessage = "无法解析为订阅源，请确认地址或兑换码有效。"
            }
        }
    }
}
