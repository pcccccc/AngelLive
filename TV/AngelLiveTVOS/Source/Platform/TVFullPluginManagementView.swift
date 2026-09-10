import SwiftUI
import AngelLiveCore

/// FullUI only. The existing ShellUI installation and consent surface is kept
/// separate so changing management doesn't alter first-install onboarding.
struct TVFullPluginManagementView: View {
    let pluginSourceManager: PluginSourceManager
    let pluginAvailability: PluginAvailabilityService
    @Environment(PluginInstallConsentService.self) private var consentService
    @Environment(AppState.self) private var appViewModel
    @State private var showAddSource = false
    @State private var showSources = false
    @State private var pluginToRemove: String?
    @State private var sourceToRemove: String?

    var body: some View {
        @Bindable var consent = consentService
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    TVPluginManagementHeader(
                        manager: pluginSourceManager,
                        installedPluginIds: pluginAvailability.installedPluginIds,
                        sources: { showSources = true }, update: updatePlugins, check: checkUpdates
                    )

                    TVPluginOperationStatus(manager: pluginSourceManager, retry: updatePlugins)

                    PluginManagementOperationError(manager: pluginSourceManager)

                    TVPluginInventorySection(title: "已安装插件",
                                             ids: pluginAvailability.installedPluginIds,
                                             manager: pluginSourceManager, availability: pluginAvailability,
                                             action: performAction, remove: { pluginToRemove = $0 })

                    TVPluginInventorySection(title: "可安装插件",
                                             ids: pluginSourceManager.remotePlugins.filter {
                                                 pluginSourceManager.installedVersion(for: $0.id) == nil
                                             }.map(\.id),
                                             manager: pluginSourceManager, availability: pluginAvailability,
                                             action: performAction, remove: { pluginToRemove = $0 },
                                             installAll: installAll)
                }
                .padding(.horizontal, 80)
                .padding(.top, 48)
                .padding(.bottom, 80)
            }
            .scrollClipDisabled()
            .navigationDestination(isPresented: $showSources) {
                TVPluginSourcesPage(manager: pluginSourceManager,
                                    add: { showAddSource = true },
                                    remove: { sourceToRemove = $0 })
                    .onExitCommand { showSources = false }
            }
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
        .confirmationDialog("插件操作", isPresented: Binding(
            get: { pluginToRemove != nil }, set: { if !$0 { pluginToRemove = nil } }
        )) {
            Button("卸载插件", role: .destructive) {
                guard let id = pluginToRemove, !pluginSourceManager.isManagementBusy else { return }
                Task {
                    _ = pluginSourceManager.uninstallPlugin(pluginId: id)
                    await refreshInstalledPlugins()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卸载后需要重新安装才能继续使用。")
        }
        .confirmationDialog("删除订阅源", isPresented: Binding(
            get: { sourceToRemove != nil }, set: { if !$0 { sourceToRemove = nil } }
        )) {
            Button("删除并卸载关联插件", role: .destructive) {
                guard let source = sourceToRemove, !pluginSourceManager.isManagementBusy else { return }
                Task {
                    await pluginSourceManager.removeSourceAndAssociatedPlugins(source)
                    await refreshInstalledPlugins()
                    await reloadCatalog()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除订阅源后，该源安装的插件也会一起移除。")
        }
        .alert(consent.alertTitle, isPresented: $consent.isPresenting) {
            Button(consent.continueButtonTitle) { consent.resolve(true) }
            Button("取消", role: .cancel) { consent.resolve(false) }
        } message: {
            Text(consent.alertMessage)
        }
        .fullScreenCover(isPresented: $showAddSource) {
            TVAddPluginSourceView().environment(appViewModel)
        }
        .onChange(of: showAddSource) { _, showing in
            if !showing { Task { await reloadCatalog() } }
        }
    }

    private func updatePlugins(_ ids: [String]) {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: ids)
            await refreshInstalledPlugins()
        }
    }

    private func performAction(_ id: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        if pluginSourceManager.hasUpdate(for: id) {
            updatePlugins([id])
        } else if pluginSourceManager.installedVersion(for: id) != nil {
            pluginToRemove = id
        } else if let item = pluginSourceManager.remotePlugins.first(where: { $0.id == id }) {
            Task {
                _ = await pluginSourceManager.installPlugin(item)
                await refreshInstalledPlugins()
            }
        }
    }

    private func installAll() {
        guard !pluginSourceManager.isManagementBusy else { return }
        Task {
            _ = await pluginSourceManager.installAll()
            await refreshInstalledPlugins()
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

    private func refreshInstalledPlugins() async {
        PluginAppGroupSync.syncToAppGroup()
        await pluginAvailability.refresh()
    }

    private func runAutoAction(_ action: PluginManagementAutoAction) async {
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
            await refreshInstalledPlugins()
        }
    }
}

private struct TVPluginManagementHeader: View {
    let manager: PluginSourceManager
    let installedPluginIds: [String]
    let sources: () -> Void
    let update: ([String]) -> Void
    let check: () -> Void

    var body: some View {
        let candidates = installedPluginIds.filter { manager.hasUpdate(for: $0) }
        let isChecking = manager.isFetchingIndex || manager.isCheckingUpdates
        HStack(alignment: .center, spacing: 48) {
            VStack(alignment: .leading, spacing: 12) {
                Text("插件管理").font(.largeTitle.weight(.bold))
                Group {
                    if isChecking {
                        Text("正在检查更新…")
                    } else if candidates.isEmpty {
                        Text("已安装 \(installedPluginIds.count) 个插件")
                    } else {
                        Text("已安装 \(installedPluginIds.count) 个 · \(candidates.count) 个可更新")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                Button("订阅源", systemImage: "link", action: sources)
                    .accessibilityIdentifier("plugins.sources")
                Button("检查更新", systemImage: "arrow.clockwise", action: check)
                    .disabled(manager.sourceURLs.isEmpty || (manager.isManagementBusy && !isChecking))
                    .accessibilityIdentifier("plugins.checkUpdates")
                Button { update(candidates) } label: {
                    Label {
                        if manager.updateBatch.isRunning {
                            Text("正在更新")
                        } else {
                            Text("全部更新")
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .disabled(!manager.updateBatch.isRunning && (candidates.isEmpty || manager.isManagementBusy))
                .accessibilityIdentifier("plugins.updateAll")
            }
            .buttonStyle(.bordered)
            .focusSection()
        }
    }
}

private struct TVPluginOperationStatus: View {
    let manager: PluginSourceManager
    let retry: ([String]) -> Void

    var body: some View {
        let batch = manager.updateBatch
        if batch.isRunning || !batch.pluginIds.isEmpty || manager.installTotalCount > 0 ||
            manager.sourceHealth.values.contains(where: { $0.isFailed }) {
            VStack(alignment: .leading, spacing: 18) {
                if batch.isRunning {
                    ProgressView(value: Double(batch.completedCount), total: Double(max(1, batch.pluginIds.count))) {
                        if let id = batch.currentPluginId {
                            Text("正在更新 \(manager.managementDisplayName(for: id))")
                        }
                    } currentValueLabel: {
                        Text("\(batch.completedCount) / \(batch.pluginIds.count)").monospacedDigit()
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                } else if !batch.pluginIds.isEmpty {
                    if batch.outcomes.values.contains(.cancelled) {
                        Text("更新已停止，\(batch.successCount) 个已完成")
                    } else if batch.failedPluginIds.isEmpty {
                        Label("已更新 \(batch.successCount) 个插件", systemImage: "checkmark.circle")
                    }
                    if !batch.failedPluginIds.isEmpty {
                        Text("\(batch.successCount) 个已更新，\(batch.failedPluginIds.count) 个失败")
                        ForEach(batch.failedPluginIds, id: \.self) { id in
                            if case .failed(let reason) = batch.outcomes[id] {
                                Text("\(manager.managementDisplayName(for: id))：\(reason)")
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button("重试失败项") { retry(batch.failedPluginIds) }
                            .disabled(manager.isManagementBusy)
                    }
                }
                if manager.installTotalCount > 0 {
                    ProgressView("已安装 \(manager.installCompletedCount) / \(manager.installTotalCount)")
                }
                if manager.sourceHealth.values.contains(where: { $0.isFailed }) {
                    Label("部分订阅源未能检查，请在订阅源页面重试。", systemImage: "exclamationmark.circle")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct TVPluginInventorySection: View {
    let title: LocalizedStringKey
    let ids: [String]
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let action: (String) -> Void
    let remove: (String) -> Void
    var installAll: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 40)]

    var body: some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let installAll {
                        Button("全部安装", systemImage: "square.and.arrow.down", action: installAll)
                            .disabled(manager.isManagementBusy)
                    }
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                    ForEach(ids, id: \.self) { id in
                        TVManagedPluginCard(id: id, manager: manager, availability: availability, action: action)
                            .contextMenu {
                                if manager.installedVersion(for: id) != nil {
                                    Button("卸载插件", role: .destructive) { remove(id) }
                                        .disabled(manager.isManagementBusy)
                                }
                            }
                    }
                }
            }
            .focusSection()
        }
    }
}

private struct TVManagedPluginCard: View {
    let id: String
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let action: (String) -> Void

    var body: some View {
        let installed = manager.installedVersion(for: id)
        let remote = manager.remotePlugins.first { $0.id == id }
        let state = manager.managementActionState(for: id, remote: remote)
        let platform = LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == id }
        let icon = platform.flatMap { TVPlatformIconProvider.tabImage(for: $0.liveType) }.map { Image(uiImage: $0) }
        let name = manager.managementDisplayName(for: id)
        Button { action(id) } label: {
            TVPluginCardLabel(name: name, version: installed ?? remote?.item.version ?? "—", icon: icon,
                              requiresLogin: availability.requiresLogin(for: id) || remote?.item.auth?.required == true,
                              state: state, isWaiting: manager.isWaitingForUpdate(for: id))
        }
        .buttonStyle(.card)
        .disabled(manager.isManagementBusy && state != .updating && state != .installing)
        .accessibilityIdentifier("plugins.item.\(id)")
    }
}

private struct TVPluginCardLabel: View {
    let name: String
    let version: String
    let icon: Image?
    let requiresLogin: Bool
    let state: RemotePluginCatalogActionState
    let isWaiting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Group {
                    if let icon {
                        icon.resizable().scaledToFit()
                    } else {
                        Text(String(name.prefix(1))).font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary, in: .rect(cornerRadius: 14))
                    }
                }
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)
                Spacer()
                if requiresLogin {
                    Image(systemName: "person.crop.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("需登录")
                }
            }
            Text(name)
                .font(.body.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                Text(version).lineLimit(1)
                Spacer(minLength: 0)
                TVPluginCardStatus(state: state, isWaiting: isWaiting)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TVPluginCardStatus: View {
    let state: RemotePluginCatalogActionState
    let isWaiting: Bool

    var body: some View {
        if isWaiting {
            Text("等待更新")
        } else {
            switch state {
            case .installed:
                EmptyView()
            case .install:
                Label("安装", systemImage: "arrow.down.circle")
            case .update:
                Label("可更新", systemImage: "arrow.down.circle")
            case .failed:
                Label("重试", systemImage: "exclamationmark.circle")
            case .updating:
                ProgressView().accessibilityLabel("更新中")
            case .installing:
                ProgressView().accessibilityLabel("安装中")
            }
        }
    }
}

private struct TVPluginSourcesPage: View {
    let manager: PluginSourceManager
    let add: () -> Void
    let remove: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                HStack {
                    Text("订阅源").font(.largeTitle.weight(.bold))
                    Spacer()
                    Button("添加订阅源", systemImage: "plus", action: add)
                        .disabled(manager.isManagementBusy)
                }
                PluginManagementOperationError(manager: manager)
                if manager.sourceURLs.isEmpty {
                    ContentUnavailableView("尚未添加订阅源", systemImage: "link",
                                           description: Text("添加订阅源后，可以浏览和安装其中的插件。"))
                } else {
                    TVPluginSourcesSection(manager: manager, remove: remove)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .scrollClipDisabled()
        .background(.background)
    }
}

private struct TVPluginSourcesSection: View {
    let manager: PluginSourceManager
    let remove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !manager.sourceURLs.isEmpty {
                ForEach(manager.sourceURLs, id: \.self) { url in
                    let health = manager.health(for: url)
                    Button {
                        if health.isFailed {
                            Task { await manager.refreshSource(url) }
                        } else {
                            remove(url)
                        }
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: health.isFailed ? "exclamationmark.circle" : "link")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(URL(string: url)?.host() ?? url).font(.body)
                                Text(url).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                if case .failed(let reason) = health {
                                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if health.isFailed {
                                Text("重试").font(.callout)
                            } else if case .healthy(let count) = health {
                                Text("\(count) 个插件").font(.caption).foregroundStyle(.secondary)
                            } else if case .checking = health {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .disabled(manager.isManagementBusy)
                    .contextMenu {
                        Button("删除订阅源", role: .destructive) { remove(url) }
                            .disabled(manager.isManagementBusy)
                    }
                }
            }
        }
        .focusSection()
    }
}
