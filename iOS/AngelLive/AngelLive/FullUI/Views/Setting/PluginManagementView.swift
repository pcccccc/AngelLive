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
    @Environment(PluginInstallationCoordinator.self) private var installationFlow
    @Environment(PluginInstallConsentService.self) private var consentService
    @Environment(\.dismiss) private var dismiss

    private let entry: PluginInstallationEntry
    private let isPresentedModally: Bool

    @State private var searchText = ""
    @State private var selectedScope: PluginManagementScope
    @State private var showAddSource = false
    @State private var pendingUninstallPluginID: String?
    @State private var didPrepare = false
    @State private var consentHostID = UUID()
    @State private var installationContext = PluginInstallationContext()

    init(
        entry: PluginInstallationEntry = .management,
        isPresentedModally: Bool = false
    ) {
        self.entry = entry
        self.isPresentedModally = isPresentedModally
        switch entry {
        case .management:
            _selectedScope = State(initialValue: .installed)
        case .sourceInput, .cloudSources, .sources:
            _selectedScope = State(initialValue: .available)
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsUpdateOverview: Bool {
        let batch = pluginSourceManager.updateBatch
        return batch.isRunning
            || !batch.pluginIds.isEmpty
            || pluginAvailability.installedPluginIds.contains { pluginSourceManager.hasUpdate(for: $0) }
            || pluginSourceManager.sourceURLs.contains { pluginSourceManager.health(for: $0).isFailed }
    }

    private var hasRunningPluginOperation: Bool {
        installationFlow.isPreparing
            || installationFlow.isInstalling
            || pluginSourceManager.installBatch.isRunning
            || pluginSourceManager.updateBatch.isRunning
            || !pluginSourceManager.updatingPluginIds.isEmpty
    }

    private var installingPluginName: String? {
        guard let pluginID = pluginSourceManager.installBatch.currentPluginId else { return nil }
        return pluginSourceManager.installBatch.displayNames[pluginID]
            ?? pluginSourceManager.managementDisplayName(for: pluginID)
    }

    private var canPrepare: Bool {
        !installationFlow.isPreparing
            && !installationFlow.isInstalling
            && !pluginSourceManager.isManagementBusy
    }

    private var isNavigationLocked: Bool {
        installationFlow.isInstalling
            || pluginSourceManager.installBatch.isRunning
            || consentService.isPresenting(for: consentHostID)
    }

    private var consentPresentation: Binding<Bool> {
        Binding(
            get: { consentService.isPresenting(for: consentHostID) },
            set: { isPresented in
                if !isPresented, consentService.isPresenting(for: consentHostID) {
                    consentService.resolve(false)
                }
            }
        )
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
        managementList
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索插件"
            )
            .navigationTitle("插件管理")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isNavigationLocked)
            .fullUITabBarHidden()
            .interactiveDismissDisabled(isPresentedModally && isNavigationLocked)
            .toolbar {
                if isPresentedModally {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                            .disabled(isNavigationLocked)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("添加订阅源", systemImage: "plus") {
                        showAddSource = true
                    }
                    .disabled(
                        pluginSourceManager.isManagementBusy
                            || installationFlow.isPreparing
                            || installationFlow.isInstalling
                    )
                    .accessibilityIdentifier("plugins.addSource")
                }
            }
            .task { await prepareIfNeeded() }
            .onChange(of: canPrepare) { _, isReady in
                guard isReady, !didPrepare else { return }
                Task { await prepareIfNeeded() }
            }
            .refreshable { await refreshCurrentScope() }
            .sheet(isPresented: $showAddSource) {
                NavigationStack {
                    PluginSourceAddView { addedURLs in
                        selectedScope = .available
                        searchText = ""
                        pluginSourceManager.installBatch.clearResult()
                        installationContext.useSources(addedURLs)
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                consentService.presentationDidAppear(consentHostID)
            }
            .onDisappear {
                consentService.presentationDidDisappear(consentHostID)
            }
            .onChange(of: pluginAvailability.installedPluginIds) { _, _ in
                guard !pluginSourceManager.isManagementBusy,
                      !installationFlow.isPreparing,
                      !installationFlow.isInstalling else { return }
                Task { await refreshCurrentScope() }
            }
            .alert(
                consentService.alertTitle,
                isPresented: consentPresentation
            ) {
                Button(consentService.cancelButtonTitle, role: .cancel) {
                    consentService.resolve(false)
                }
                Button(consentService.continueButtonTitle) {
                    consentService.resolve(true)
                }
            } message: {
                Text(consentService.alertMessage)
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

    private var managementList: some View {
        List {
            PluginManagementScopeSection(selection: $selectedScope)

            if installationFlow.isPreparing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(installationContext.preparationTitle ?? "正在读取插件列表…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
            }

            if pluginSourceManager.installBatch.isRunning {
                Section {
                    PluginInstallationProgressView(
                        completedCount: pluginSourceManager.installBatch.completedCount,
                        totalCount: pluginSourceManager.installBatch.pluginIds.count,
                        currentPluginName: installingPluginName
                    )
                }
            } else if !pluginSourceManager.installBatch.pluginIds.isEmpty {
                PluginInstallationResultSection(
                    batch: pluginSourceManager.installBatch,
                    retry: retryFailedInstallation
                )
                .disabled(installationFlow.isPreparing)
            }

            if showsUpdateOverview {
                PluginManagementUpdateSection(
                    manager: pluginSourceManager,
                    installedPluginIDs: pluginAvailability.installedPluginIds,
                    update: updatePlugins,
                    check: checkUpdates
                )
                .disabled(installationFlow.isPreparing)
            }

            if let errorMessage = installationContext.errorMessage {
                Section {
                    PluginSourceErrorCard(title: "准备安装失败", message: errorMessage)
                    Button("重试", systemImage: "arrow.clockwise") {
                        Task {
                            await installationFlow.prepare(
                                entry, context: installationContext, manager: pluginSourceManager
                            )
                        }
                    }
                    .disabled(
                        pluginSourceManager.isManagementBusy
                            || installationFlow.isPreparing
                            || installationFlow.isInstalling
                    )
                }
            }

            if installationContext.errorMessage == nil,
               pluginSourceManager.errorMessage != nil,
               !showAddSource {
                Section {
                    PluginManagementOperationError(manager: pluginSourceManager)
                }
            }

            if let sourceURLs = installationContext.sourceURLs, !sourceURLs.isEmpty {
                PluginInstallationSourcesSection(
                    sourceURLs: sourceURLs,
                    retry: retrySource,
                    showAll: showAllSources
                )
                .disabled(installationFlow.isPreparing)
            }

            PluginManagementPluginListSection(
                selectedScope: $selectedScope,
                searchText: normalizedSearch,
                scopedSourceURLs: installationContext.sourceURLs,
                update: updatePlugins,
                install: installPlugins,
                requestUninstall: requestUninstall,
                addSource: { showAddSource = true }
            )
            .disabled(installationFlow.isPreparing)

            PluginManagementToolsSection(
                installedPluginIDs: pluginAvailability.installedPluginIds,
                showsCheckAction: !hasRunningPluginOperation,
                check: checkUpdates
            )
            .disabled(installationFlow.isPreparing)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .contentMargins(.top, 8, for: .scrollContent)
        .disabled(installationFlow.isInstalling || pluginSourceManager.installBatch.isRunning)
    }

    // MARK: - Actions

    private func prepareIfNeeded() async {
        guard !didPrepare, canPrepare else { return }
        didPrepare = true
        await installationFlow.prepare(entry, context: installationContext, manager: pluginSourceManager)
    }

    private func updatePlugins(_ ids: [String]) {
        guard !ids.isEmpty, canPrepare else { return }
        Task {
            _ = await pluginSourceManager.updateAllPlugins(pluginIds: ids)
            await pluginAvailability.refresh()
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }

    private func installPlugins(_ pluginIDs: [String]) {
        guard !pluginIDs.isEmpty,
              !pluginSourceManager.isManagementBusy,
              !installationFlow.isPreparing,
              !installationFlow.isInstalling else { return }
        Task {
            await installationFlow.install(
                pluginIds: pluginIDs,
                sourceURLs: installationContext.sourceURLs,
                manager: pluginSourceManager,
                availability: pluginAvailability
            )
        }
    }

    private func retrySource(_ sourceURL: String) {
        guard !pluginSourceManager.isManagementBusy,
              !installationFlow.isPreparing,
              !installationFlow.isInstalling else { return }
        Task {
            await installationFlow.retrySource(
                sourceURL, context: installationContext, manager: pluginSourceManager
            )
        }
    }

    private func retryFailedInstallation() {
        Task {
            await installationFlow.retryFailed(
                manager: pluginSourceManager,
                availability: pluginAvailability
            )
        }
    }

    private func showAllSources() {
        guard !pluginSourceManager.isManagementBusy,
              !installationFlow.isPreparing,
              !installationFlow.isInstalling else { return }
        searchText = ""
        installationContext.showAllSources()
        Task { await reloadCatalog() }
    }

    private func requestUninstall(_ pluginID: String) {
        guard !pluginSourceManager.isManagementBusy,
              !installationFlow.isPreparing,
              !installationFlow.isInstalling else { return }
        pendingUninstallPluginID = pluginID
    }

    private func uninstallPlugin(_ pluginID: String) {
        guard canPrepare else { return }
        _ = pluginSourceManager.uninstallPlugin(pluginId: pluginID)
        Task {
            await pluginAvailability.refresh()
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }

    private func checkUpdates() {
        guard canPrepare else { return }
        pluginSourceManager.updateBatch.clearResult()
        Task { await reloadCatalog() }
    }

    private func reloadCatalog() async {
        guard canPrepare else { return }
        await pluginSourceManager.fetchAllSourceIndexes()
        await pluginSourceManager.refreshAvailableUpdates()
    }

    private func refreshCurrentScope() async {
        guard canPrepare else { return }
        if let sourceURLs = installationContext.sourceURLs {
            await installationFlow.prepare(
                .sources(sourceURLs),
                context: installationContext,
                manager: pluginSourceManager,
                resetsResult: false
            )
        } else {
            await reloadCatalog()
        }
    }
}

private struct PluginManagementUpdateSection: View {
    let manager: PluginSourceManager
    let installedPluginIDs: [String]
    let update: ([String]) -> Void
    let check: () -> Void

    private var batch: PluginUpdateBatch {
        manager.updateBatch
    }

    private var candidatePluginIDs: [String] {
        installedPluginIDs.filter { manager.hasUpdate(for: $0) }
    }

    private var retryableFailedPluginIDs: [String] {
        batch.failedPluginIds.filter { manager.hasUpdate(for: $0) }
    }

    private var cancelledCount: Int {
        batch.outcomes.values.filter { $0 == .cancelled }.count
    }

    private var hasCompletedBatch: Bool {
        !batch.isRunning && !batch.pluginIds.isEmpty
    }

    private var statusTitle: LocalizedStringKey {
        if batch.isRunning {
            return "正在更新插件"
        }
        if hasCompletedBatch {
            if !batch.failedPluginIds.isEmpty {
                return "更新完成：\(batch.successCount) 个成功，\(batch.failedPluginIds.count) 个失败"
            }
            if cancelledCount > 0 {
                return "更新已停止"
            }
            return "已更新 \(batch.successCount) 个插件"
        }
        if manager.isFetchingIndex || manager.isCheckingUpdates {
            return "正在检查更新…"
        }
        if !candidatePluginIDs.isEmpty {
            return "\(candidatePluginIDs.count) 个插件可更新"
        }
        if installedPluginIDs.isEmpty {
            return "暂无已安装插件"
        }
        if manager.sourceURLs.contains(where: { manager.health(for: $0).isFailed }) {
            return "部分订阅源未能检查"
        }
        if manager.sourceURLs.isEmpty {
            return "添加订阅源以获取更新"
        }
        return "插件均为最新版本"
    }

    var body: some View {
        Section {
            statusRow

            if batch.isRunning {
                progressRow
            } else if hasCompletedBatch {
                ForEach(batch.failedPluginIds, id: \.self) { pluginID in
                    failureRow(pluginID)
                }

                if !retryableFailedPluginIDs.isEmpty {
                    retryButton
                }
                if !candidatePluginIDs.isEmpty,
                   Set(candidatePluginIDs) != Set(retryableFailedPluginIDs) {
                    updateAllButton
                }
                if !batch.failedPluginIds.isEmpty, candidatePluginIDs.isEmpty {
                    recheckButton
                }
            } else if !candidatePluginIDs.isEmpty {
                updateAllButton
            }
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("已安装 \(installedPluginIDs.count) 个 · \(manager.sourceURLs.count) 个订阅源")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(
                value: Double(batch.completedCount),
                total: Double(max(1, batch.pluginIds.count))
            )

            if let currentPluginID = batch.currentPluginId {
                Text("\(batch.completedCount) / \(batch.pluginIds.count) · 正在更新 \(manager.managementDisplayName(for: currentPluginID))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(batch.completedCount) / \(batch.pluginIds.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func failureRow(_ pluginID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(manager.managementDisplayName(for: pluginID))
                .foregroundStyle(.primary)
            Text("更新失败，请重试。")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup("技术详情") {
                Text(failureReason(for: pluginID))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var updateAllButton: some View {
        Button {
            update(candidatePluginIDs)
        } label: {
            PluginManagementListActionLabel(
                title: "全部更新（\(candidatePluginIDs.count)）",
                systemImage: "arrow.down.circle"
            )
        }
        .buttonStyle(.plain)
        .disabled(candidatePluginIDs.isEmpty || manager.isManagementBusy)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .accessibilityIdentifier("plugins.updateAll")
        .accessibilityHint("更新全部已安装且有新版本的插件")
    }

    private var retryButton: some View {
        Button {
            update(retryableFailedPluginIDs)
        } label: {
            PluginManagementListActionLabel(
                title: "重试失败项（\(retryableFailedPluginIDs.count)）",
                systemImage: "arrow.clockwise"
            )
        }
        .buttonStyle(.plain)
        .disabled(manager.isManagementBusy)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .accessibilityIdentifier("plugins.retryUpdates")
    }

    private var recheckButton: some View {
        Button(action: check) {
            PluginManagementListActionLabel(
                title: "重新检查更新",
                systemImage: "arrow.clockwise"
            )
        }
        .buttonStyle(.plain)
        .disabled(manager.isManagementBusy)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .accessibilityIdentifier("plugins.recheckUpdates")
    }

    private func failureReason(for pluginID: String) -> String {
        guard case .failed(let reason) = batch.outcomes[pluginID] else {
            return "更新失败，请重新检查更新。"
        }
        return SupportDiagnosticSanitizer.text(reason)
    }
}

private struct PluginManagementListActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: LocalizedStringKey
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if isEnabled {
            content
                .foregroundStyle(Color(uiColor: .systemBlue))
        } else {
            content
                .foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PluginInstallationProgressView: View {
    let completedCount: Int
    let totalCount: Int
    let currentPluginName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("正在安装插件")
                .font(.headline)

            if let currentPluginName {
                Text(currentPluginName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if totalCount > 0 {
                ProgressView(
                    value: Double(completedCount),
                    total: Double(totalCount)
                )
                Text("\(completedCount) / \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView()
                    .accessibilityLabel("正在安装插件")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct PluginInstallationResultSection: View {
    let batch: PluginInstallBatch
    let retry: () -> Void

    var body: some View {
        Section("安装结果") {
            HStack(spacing: 12) {
                resultCount(title: "成功", count: batch.successCount, color: .green)
                Divider()
                resultCount(title: "失败", count: batch.failedPluginIds.count, color: .orange)
                Divider()
                resultCount(title: "取消", count: batch.cancelledCount, color: .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            if !batch.failedPluginIds.isEmpty {
                ForEach(batch.failedPluginIds, id: \.self) { pluginID in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(batch.displayNames[pluginID] ?? pluginID)
                            .foregroundStyle(.primary)
                        Text("安装失败，请重试。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DisclosureGroup("技术详情") {
                            Text(failureReason(for: pluginID))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                Button("重试失败项", systemImage: "arrow.clockwise") {
                    retry()
                }
                .disabled(batch.isRunning)
            }

            Button("清除安装结果") {
                batch.clearResult()
            }
            .disabled(batch.isRunning)
        }
    }

    private func failureReason(for pluginID: String) -> String {
        guard case .failed(let reason) = batch.outcomes[pluginID] else {
            return "安装失败"
        }
        return SupportDiagnosticSanitizer.text(reason)
    }

    private func resultCount(title: LocalizedStringKey, count: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct PluginInstallationSourcesSection: View {
    @Environment(PluginSourceManager.self) private var manager

    let sourceURLs: [String]
    let retry: (String) -> Void
    let showAll: () -> Void

    var body: some View {
        Section("本次安装来源") {
            ForEach(sourceURLs, id: \.self) { sourceURL in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pluginSourceHost(sourceURL))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    PluginSourceHealthLabel(health: manager.health(for: sourceURL))

                    if case .failed(let reason) = manager.health(for: sourceURL) {
                        Text("已保存，但暂时无法读取")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("重试", systemImage: "arrow.clockwise") {
                            retry(sourceURL)
                        }
                        .disabled(manager.isManagementBusy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            Button("查看所有可安装插件", action: showAll)
                .disabled(manager.isManagementBusy)
        }
    }
}

#Preview("插件安装进度") {
    List {
        Section("批量安装") {
            PluginInstallationProgressView(
                completedCount: 3,
                totalCount: 18,
                currentPluginName: nil
            )
        }
        Section("单项安装") {
            PluginInstallationProgressView(
                completedCount: 0,
                totalCount: 0,
                currentPluginName: "示例插件"
            )
        }
    }
    .listStyle(.insetGrouped)
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
        let updateCount = installedPluginIDs.filter { manager.hasUpdate(for: $0) }.count
        if updateCount > 0 { return "\(updateCount) 个插件可更新" }
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
            .disabled(manager.isManagementBusy)
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
    let scopedSourceURLs: [String]?
    let update: ([String]) -> Void
    let install: ([String]) -> Void
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

    private var scopedCatalogPluginItems: [RemotePluginDisplayItem] {
        pluginSourceManager.catalogPlugins(forSourceURLs: scopedSourceURLs)
    }

    private var scopedUpdatablePluginItems: [RemotePluginDisplayItem] {
        scopedCatalogPluginItems.filter { item in
            pluginSourceManager.installedVersion(for: item.id) != nil
                && pluginSourceManager.hasUpdate(for: item.id)
        }
    }

    private var scopedInstallablePluginItems: [RemotePluginDisplayItem] {
        scopedCatalogPluginItems.filter { item in
            pluginSourceManager.installedVersion(for: item.id) == nil
        }
    }

    private var visibleUpdatablePluginItems: [RemotePluginDisplayItem] {
        scopedUpdatablePluginItems.filter { item in
            guard !normalizedSearch.isEmpty else { return true }
            return pluginMatchesSearch(name: item.displayName, pluginId: item.id)
        }
    }

    private var visibleInstallablePluginItems: [RemotePluginDisplayItem] {
        scopedInstallablePluginItems.filter { item in
            guard !normalizedSearch.isEmpty else { return true }
            return pluginMatchesSearch(name: item.displayName, pluginId: item.id)
        }
    }

    private var hasScopedAvailableActions: Bool {
        !scopedUpdatablePluginItems.isEmpty || !scopedInstallablePluginItems.isEmpty
    }

    private var hasVisibleAvailableActions: Bool {
        !visibleUpdatablePluginItems.isEmpty || !visibleInstallablePluginItems.isEmpty
    }

    private var relevantSourceURLs: [String] {
        scopedSourceURLs ?? pluginSourceManager.sourceURLs
    }

    private var installablePluginIDs: [String] {
        scopedInstallablePluginItems.compactMap { item in
            pluginSourceManager.catalogActionState(for: item) == .install ? item.id : nil
        }
    }

    @ViewBuilder
    var body: some View {
        if selectedScope == .installed {
            Section {
                installedPluginRows
            } header: {
                if normalizedSearch.isEmpty {
                    Text("\(filteredInstalledPluginIDs.count) 个插件")
                } else {
                    Text("找到 \(filteredInstalledPluginIDs.count) 个插件")
                }
            }
        } else {
            availablePluginSections
        }
    }

    @ViewBuilder
    private var availablePluginSections: some View {
        if !hasScopedAvailableActions,
           pluginSourceManager.isFetchingIndex || pluginSourceManager.isCheckingUpdates {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在获取插件…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 76)
            }
        } else if !hasScopedAvailableActions {
            Section {
                availablePluginEmptyState
            }
        } else if !hasVisibleAvailableActions {
            Section {
                PluginManagementEmptyState(
                    title: "没有匹配的插件",
                    message: "请尝试其他搜索词。"
                )
            }
        } else {
            if !visibleUpdatablePluginItems.isEmpty {
                Section {
                    ForEach(visibleUpdatablePluginItems) { displayItem in
                        managedPluginRow(pluginId: displayItem.id, remote: displayItem)
                            .listRowInsets(
                                EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
                            )
                    }
                } header: {
                    if normalizedSearch.isEmpty {
                        Text("可更新（\(visibleUpdatablePluginItems.count)）")
                    } else {
                        Text("找到 \(visibleUpdatablePluginItems.count) 个可更新插件")
                    }
                }
            }

            if !visibleInstallablePluginItems.isEmpty {
                Section {
                    if normalizedSearch.isEmpty, !installablePluginIDs.isEmpty {
                        installAllButton
                    }

                    ForEach(visibleInstallablePluginItems) { displayItem in
                        managedPluginRow(pluginId: displayItem.id, remote: displayItem)
                            .listRowInsets(
                                EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
                            )
                    }
                } header: {
                    if normalizedSearch.isEmpty {
                        Text("可安装（\(visibleInstallablePluginItems.count)）")
                    } else {
                        Text("找到 \(visibleInstallablePluginItems.count) 个可安装插件")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var availablePluginEmptyState: some View {
        if relevantSourceURLs.isEmpty {
            PluginManagementEmptyState(
                title: "暂无可安装或可更新插件",
                message: "先添加订阅源以获取插件。",
                actionTitle: "添加订阅源",
                action: addSource
            )
        } else if relevantSourceURLs.contains(where: {
            pluginSourceManager.health(for: $0).isFailed
        }) {
            PluginManagementEmptyState(
                title: "暂时无法获取插件",
                message: "部分订阅源未能加载，请检查订阅源状态后重试。"
            )
        } else {
            PluginManagementEmptyState(
                title: "暂无可安装或可更新插件",
                message: "订阅源中暂时没有可安装或可更新的插件。"
            )
        }
    }

    private var installAllButton: some View {
        Button {
            install(installablePluginIDs)
        } label: {
            PluginManagementListActionLabel(
                title: "全部安装（\(installablePluginIDs.count)）",
                systemImage: "arrow.down.circle"
            )
        }
        .buttonStyle(.plain)
        .disabled(installablePluginIDs.isEmpty || pluginSourceManager.isManagementBusy)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .accessibilityIdentifier("plugins.installAll")
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

    private func installedPluginRow(_ pluginID: String) -> some View {
        managedPluginRow(pluginId: pluginID)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    requestUninstall(pluginID)
                } label: {
                    Label("卸载", systemImage: "trash")
                }
                .tint(.red)
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
        .tint(Color(uiColor: .systemBlue))
    }

    private func performPluginAction(
        pluginId: String,
        remote: RemotePluginDisplayItem?
    ) {
        guard !pluginSourceManager.isManagementBusy else { return }

        if pluginSourceManager.installedVersion(for: pluginId) != nil {
            update([pluginId])
        } else if remote != nil {
            install([pluginId])
        }
    }
}

// MARK: - Subscription sources

private struct PluginSourceListView: View {
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @State private var showAddSource = false
    @State private var pendingRemovalSourceURL: String?
    @State private var pendingAddedSourceURLs: [String]?
    @State private var addedSourceURLs: [String]?

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // This action only presents confirmation; a destructive role
                            // makes List hide the row before the user confirms removal.
                            Button {
                                guard !pluginSourceManager.isManagementBusy else { return }
                                pendingRemovalSourceURL = url
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(.red)
                            .disabled(pluginSourceManager.isManagementBusy)
                        }
                        .accessibilityAction(named: Text("删除订阅源")) {
                            guard !pluginSourceManager.isManagementBusy else { return }
                            pendingRemovalSourceURL = url
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
        .sheet(isPresented: $showAddSource, onDismiss: {
            addedSourceURLs = pendingAddedSourceURLs
            pendingAddedSourceURLs = nil
        }) {
            NavigationStack {
                PluginSourceAddView { urls in
                    pendingAddedSourceURLs = urls
                }
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $addedSourceURLs) { urls in
            PluginManagementView(entry: .sources(urls))
        }
        .pluginSourceRemovalConfirmation(pendingSourceURL: $pendingRemovalSourceURL)
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

    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false
    @State private var pendingRemovalSourceURL: String?

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
                    guard !pluginSourceManager.isManagementBusy else { return }
                    pendingRemovalSourceURL = sourceURL
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
        .pluginSourceRemovalConfirmation(pendingSourceURL: $pendingRemovalSourceURL) {
            dismiss()
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
}

private struct PluginSourceRemovalConfirmationModifier: ViewModifier {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Binding var pendingSourceURL: String?
    let onRemoved: () -> Void

    init(
        pendingSourceURL: Binding<String?>,
        onRemoved: @escaping () -> Void = {}
    ) {
        _pendingSourceURL = pendingSourceURL
        self.onRemoved = onRemoved
    }

    private var isConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingSourceURL != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSourceURL = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "删除订阅源？",
            isPresented: isConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let sourceURL = pendingSourceURL {
                Button("删除并卸载关联插件", role: .destructive) {
                    removeSource(sourceURL)
                }
                .disabled(pluginSourceManager.isManagementBusy)
            }
            Button("取消", role: .cancel) {
                pendingSourceURL = nil
            }
        } message: {
            if let sourceURL = pendingSourceURL {
                Text("将删除「\(pluginSourceHost(sourceURL))」，并卸载仅由它提供、未被其他订阅源覆盖的插件。")
            }
        }
    }

    private func removeSource(_ sourceURL: String) {
        guard !pluginSourceManager.isManagementBusy else { return }
        pendingSourceURL = nil
        Task {
            await pluginSourceManager.removeSourceAndAssociatedPlugins(sourceURL)
            await pluginAvailability.refresh()
            await pluginSourceManager.fetchAllSourceIndexes()
            await pluginSourceManager.refreshAvailableUpdates()
            onRemoved()
        }
    }
}

private extension View {
    func pluginSourceRemovalConfirmation(
        pendingSourceURL: Binding<String?>,
        onRemoved: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            PluginSourceRemovalConfirmationModifier(
                pendingSourceURL: pendingSourceURL,
                onRemoved: onRemoved
            )
        )
    }
}

private struct PluginSourceAddView: View {
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss

    @State private var inputURL = ""
    @State private var isProcessing = false

    let onAdded: ([String]) -> Void

    init(onAdded: @escaping ([String]) -> Void = { _ in }) {
        self.onAdded = onAdded
    }

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
                Text("输入订阅源地址或兑换码，添加后选择要安装的插件。")
            }
        }
        .navigationTitle("添加订阅源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isProcessing)
            }
        }
        .interactiveDismissDisabled(isProcessing)
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
                onAdded(addedURLs)
                dismiss()
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
