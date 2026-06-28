// TVShellConfigView.swift
// AngelLiveTVOS
//
// 壳 UI 配置页：简洁输入框，自动识别视频链接或订阅地址。

import SwiftUI
import AngelLiveCore

struct TVShellConfigView: View {
    @Environment(AppState.self) private var appViewModel

    // cover 由 ContentView 根部持有,本视图通过 appViewModel.showPluginManagement 触发它。
    @State private var inputURL = ""
    @State private var inputTitle = ""
    @State private var isProcessing = false
    @FocusState private var focusedField: Field?

    enum Field { case title, url, add }

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubscriptionURL: Bool {
        guard !trimmedURL.isEmpty else { return false }
        if let url = URL(string: trimmedURL) {
            return url.pathExtension.lowercased() == "json"
        }
        return trimmedURL.lowercased().hasSuffix(".json")
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.thinMaterial)
                .ignoresSafeArea()

            HStack(alignment: .center, spacing: 120) {
                VStack(alignment: .leading, spacing: 28) {
                    Text("配置")
                        .font(.system(size: 48, weight: .heavy))

                    Text("输入订阅地址或视频地址，添加到收藏。")
                        .font(.system(size: 24, weight: .medium))
                        .lineSpacing(6)
                        .foregroundStyle(.secondary)

                    TextField("标题（可选）", text: $inputTitle)
                        .focused($focusedField, equals: .title)
                        .frame(maxWidth: 600, alignment: .leading)

                    TextField("输入地址", text: $inputURL)
                        .focused($focusedField, equals: .url)
                        .frame(maxWidth: 600, alignment: .leading)

                    if let error = appViewModel.pluginSourceManager.errorMessage {
                        PluginSourceErrorCard(title: "插件源异常", message: error)
                            .frame(maxWidth: 600, alignment: .leading)
                    }

                    Spacer()

                    HStack(spacing: 20) {
                        Button(action: handleAdd) {
                            Label("添加", systemImage: "plus.circle.fill")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        .disabled(trimmedURL.isEmpty || isProcessing)
                        .focused($focusedField, equals: .add)

                        if isProcessing {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)

                // 右侧：远程输入二维码
                remoteInputQRPanel
            }
            .padding(80)
            .safeAreaPadding()
        }
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard let event = appViewModel.remoteInputService.lastEvent else { return }
            switch event.field {
            case .title:
                inputTitle = event.value
            case .url:
                inputURL = event.value
            case .config:
                if let url = event.url { inputURL = url }
                if let title = event.title { inputTitle = title }
            case .search, .cookie:
                break
            }
        }
    }

    // MARK: - 远程输入二维码面板

    private var remoteInputQRPanel: some View {
        let service = appViewModel.remoteInputService
        let url = "http://\(service.localIPAddress):\(service.port)/config"
        return VStack(spacing: 16) {
            Spacer()
            if service.isRunning && !service.localIPAddress.isEmpty {
                Image(uiImage: Common.generateQRCode(from: url))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 18)

                Text("扫码用手机输入")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(url)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                Text("正在启动远程输入...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func handleAdd() {
        let url = trimmedURL
        let title = inputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldTreatAsSubscription = isSubscriptionURL
        guard !url.isEmpty else { return }

        isProcessing = true
        Task {
            if shouldTreatAsSubscription {
                let addedURLs = await appViewModel.pluginSourceManager.addSourceFromInput(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    appViewModel.showPluginManagement = true
                }
            } else {
                let addedURLs = await appViewModel.pluginSourceManager.addSourceWithKeyResolution(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    appViewModel.showPluginManagement = true
                } else if appViewModel.pluginSourceManager.errorMessage == nil {
                    // 非 key，作为视频书签添加
                    await appViewModel.bookmarkService.add(
                        title: title.isEmpty ? url : title,
                        url: url
                    )
                    inputURL = ""
                    inputTitle = ""
                }
            }
            isProcessing = false
        }
    }
}

// MARK: - 插件管理

struct TVPluginManagementView: View {
    let pluginSourceManager: PluginSourceManager
    let pluginAvailability: PluginAvailabilityService
    // 本视图作为 fullScreenCover 的内容呈现,consent alert 必须挂在 cover 内部
    // 才能可靠覆盖在 cover 之上(SwiftUI 在 tvOS 上对 modal 之上叠 alert 的支持有缺陷)。
    @Environment(PluginInstallConsentService.self) private var consentService
    @Environment(AppState.self) private var appViewModel
    @State private var pluginIdToUninstall: String?
    @State private var sourceToRemove: String?
    @State private var showAddSource = false

    var body: some View {
        @Bindable var consent = consentService

        return ZStack {
            Color.clear
                .background(.thinMaterial)
                .ignoresSafeArea()

            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        if let error = pluginSourceManager.errorMessage {
                            PluginSourceErrorCard(title: "插件源异常", message: error)
                                .padding(.top, 50)
                                .padding(.horizontal, 50)
                        }

                        actionSection

                        pluginSection

                        if !pluginSourceManager.sourceURLs.isEmpty {
                            sourceSection
                        }

                        Spacer(minLength: 60)
                    }
                }
                .navigationTitle("插件管理")
            }
        }
        .task {
            await reloadPluginCatalog()
            // cover 由调用方设置 pendingPluginManagementAction 后再打开,这里 mount 完成后兜底执行。
            // 走 cover 内的 alert 绑定,避免 ContentView 顶层 alert 与 cover 撞 modal stack。
            if let action = appViewModel.pendingPluginManagementAction {
                appViewModel.pendingPluginManagementAction = nil
                await runAutoAction(action)
            }
        }
        .confirmationDialog("卸载插件", isPresented: Binding(
            get: { pluginIdToUninstall != nil },
            set: { if !$0 { pluginIdToUninstall = nil } }
        )) {
            Button("卸载", role: .destructive) {
                guard let pluginIdToUninstall else { return }
                Task {
                    _ = pluginSourceManager.uninstallPlugin(pluginId: pluginIdToUninstall)
                    PluginAppGroupSync.syncToAppGroup()
                    await pluginAvailability.refresh()
                    await pluginSourceManager.fetchAllSourceIndexes()
                    await pluginSourceManager.refreshAvailableUpdates()
                    self.pluginIdToUninstall = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卸载后需要重新安装才能继续使用该平台。")
        }
        .confirmationDialog("删除订阅源", isPresented: Binding(
            get: { sourceToRemove != nil },
            set: { if !$0 { sourceToRemove = nil } }
        )) {
            Button("删除并卸载关联插件", role: .destructive) {
                guard let sourceToRemove else { return }
                Task {
                    await pluginSourceManager.removeSourceAndAssociatedPlugins(sourceToRemove)
                    await pluginAvailability.refresh()
                    await reloadPluginCatalog()
                    self.sourceToRemove = nil
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
            TVAddPluginSourceView()
                .environment(appViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
        .onChange(of: showAddSource) { _, isShowing in
            // cover 关闭后刷新 availability 和插件目录,让新订阅源带来的插件状态跟上。
            guard !isShowing else { return }
            Task {
                await pluginAvailability.refresh()
                await reloadPluginCatalog()
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 16) {
            sectionHeader("操作", topPadding: 50)

            actionRow(
                title: "刷新目录",
                subtitle: pluginSourceManager.sourceURLs.isEmpty ? "当前没有可刷新的订阅源" : "重新读取 \(pluginSourceManager.sourceURLs.count) 个订阅源",
                iconName: "arrow.clockwise",
                trailing: pluginSourceManager.isFetchingIndex ? "加载中" : nil,
                disabled: pluginSourceManager.sourceURLs.isEmpty || pluginSourceManager.isFetchingIndex
            ) {
                Task { await reloadPluginCatalog() }
            }

            actionRow(
                title: "添加订阅源",
                subtitle: "输入 .json 订阅地址或兑换码",
                iconName: "plus.circle.fill"
            ) {
                showAddSource = true
            }

            if pluginSourceManager.installTotalCount > 0 {
                infoRow(
                    title: "正在批量安装",
                    subtitle: "已完成 \(pluginSourceManager.installCompletedCount)/\(pluginSourceManager.installTotalCount)",
                    iconName: "square.and.arrow.down.fill",
                    trailing: nil
                )
            } else if canInstallAll {
                actionRow(
                    title: "全部安装",
                    subtitle: "安装当前未安装的插件",
                    iconName: "square.and.arrow.down.fill"
                ) {
                    installAll()
                }
            }
        }
    }

    private var pluginSection: some View {
        VStack(spacing: 16) {
            sectionHeader("插件", topPadding: 18)

            if pluginSourceManager.isFetchingIndex &&
                pluginSourceManager.remotePlugins.isEmpty &&
                pluginSourceManager.sourceURLs.isEmpty {
                statusCard(
                    icon: "arrow.clockwise",
                    title: "正在加载内容...",
                    message: "正在读取插件订阅源，请稍候。"
                )
            } else if pluginSourceManager.remotePlugins.isEmpty {
                statusCard(
                    icon: "tray.fill",
                    title: "暂无可用内容",
                    message: pluginSourceManager.sourceURLs.isEmpty ? "先添加订阅源，再在这里管理插件。" : "当前订阅源暂无可用插件。"
                )
            } else {
                ForEach(pluginSourceManager.remotePlugins) { item in
                    pluginRow(item)
                }
            }
        }
    }

    private var sourceSection: some View {
        VStack(spacing: 16) {
            sectionHeader("订阅源", topPadding: 18)

            ForEach(pluginSourceManager.sourceURLs, id: \.self) { url in
                sourceRow(url)
            }
        }
    }

    private func pluginRow(_ item: RemotePluginDisplayItem) -> some View {
        Button {
            handlePrimaryAction(for: item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(item.displayName)
                            .font(.system(size: 32))
                            .foregroundColor(.primary)
                        if item.item.auth?.required == true
                            || pluginAvailability.requiresLogin(for: item.id) {
                            RequiresLoginTag(size: .regular)
                        }
                    }
                    pluginSubtitle(for: item)
                }

                Spacer()

                pluginStatusView(for: item)

                if canTriggerPrimaryAction(for: item) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 50)
        .contextMenu {
            if pluginSourceManager.installedVersion(for: item.id) != nil {
                Button("卸载插件", role: .destructive) {
                    pluginIdToUninstall = item.id
                }
            }
        }
    }

    private func sourceRow(_ url: String) -> some View {
        let health = pluginSourceManager.health(for: url)
        return Button {
            // 选中失败的源即重试 —— tvOS 上 contextMenu 需要长按,选中重试更顺手。
            if health.isFailed {
                Task { await pluginSourceManager.refreshSource(url) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: sourceIconName(for: health))
                    .font(.system(size: 28))
                    .frame(width: 40)
                    .foregroundStyle(sourceTint(for: health))

                VStack(alignment: .leading, spacing: 4) {
                    Text(url)
                        .font(.system(size: 24))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    Text(sourceSubtitle(for: health))
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                sourceTrailing(for: health)
            }
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 50)
        .contextMenu {
            if health.isFailed {
                Button("重试") {
                    Task { await pluginSourceManager.refreshSource(url) }
                }
            }
            Button("删除订阅源", role: .destructive) {
                sourceToRemove = url
            }
        }
    }

    // MARK: - 订阅源健康状态展示

    private func sourceIconName(for health: PluginSourceHealth) -> String {
        health.isFailed ? "exclamationmark.triangle.fill" : "link.circle.fill"
    }

    private func sourceTint(for health: PluginSourceHealth) -> Color {
        switch health {
        case .failed: return .orange
        case .healthy: return .green
        case .checking, .unknown: return .secondary
        }
    }

    private func sourceSubtitle(for health: PluginSourceHealth) -> String {
        switch health {
        case .unknown, .healthy: return "长按可删除订阅源"
        case .checking: return "正在检查..."
        case .failed(let reason): return reason
        }
    }

    @ViewBuilder
    private func sourceTrailing(for health: PluginSourceHealth) -> some View {
        switch health {
        case .unknown:
            Text("已添加")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
        case .healthy(let count):
            Text("\(count) 个插件")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        case .failed:
            Text("异常 · 选中重试")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
        }
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 50)
        .padding(.top, topPadding)
    }

    private func statusCard(icon: String, title: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 32))

                Text(message)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 50)
    }

    private func actionRow(
        title: String,
        subtitle: String,
        iconName: String,
        trailing: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 32))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 50)
        .disabled(disabled)
    }

    private func infoRow(
        title: String,
        subtitle: String,
        iconName: String,
        trailing: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 28))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 32))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 50)
    }

    @ViewBuilder
    private func pluginSubtitle(for item: RemotePluginDisplayItem) -> some View {
        if let installedVersion = pluginSourceManager.installedVersion(for: item.id) {
            if pluginSourceManager.hasUpdate(for: item.id) {
                Text("已安装 \(installedVersion) · 可更新到 \(item.item.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("已安装 \(installedVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("远程版本 \(item.item.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func pluginStatusView(for item: RemotePluginDisplayItem) -> some View {
        switch item.installState {
        case .failed:
            Text("失败")
                .font(.system(size: 28))
        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                Text("安装中")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        case .notInstalled:
            if pluginSourceManager.updatingPluginIds.contains(item.id) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("更新中")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            } else if pluginSourceManager.hasUpdate(for: item.id) {
                Text("更新")
                    .font(.system(size: 28))
            } else if pluginSourceManager.installedVersion(for: item.id) != nil {
                Text("已安装")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            } else {
                Text("安装")
                    .font(.system(size: 28))
            }
        case .installed:
            if pluginSourceManager.updatingPluginIds.contains(item.id) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("更新中")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            } else if pluginSourceManager.hasUpdate(for: item.id) {
                Text("更新")
                    .font(.system(size: 28))
            } else {
                Text("已安装")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func canTriggerPrimaryAction(for item: RemotePluginDisplayItem) -> Bool {
        switch item.installState {
        case .failed, .installing:
            return false
        case .notInstalled:
            return !pluginSourceManager.updatingPluginIds.contains(item.id) &&
                (pluginSourceManager.hasUpdate(for: item.id) ||
                pluginSourceManager.installedVersion(for: item.id) == nil)
        case .installed:
            return pluginSourceManager.hasUpdate(for: item.id) && !pluginSourceManager.updatingPluginIds.contains(item.id)
        }
    }

    private func handlePrimaryAction(for item: RemotePluginDisplayItem) {
        guard canTriggerPrimaryAction(for: item) else { return }

        Task {
            let success: Bool
            if pluginSourceManager.hasUpdate(for: item.id) {
                success = await pluginSourceManager.updatePlugin(pluginId: item.id)
            } else if pluginSourceManager.installedVersion(for: item.id) == nil {
                success = await pluginSourceManager.installPlugin(item)
            } else {
                return
            }

            if success {
                PluginAppGroupSync.syncToAppGroup()
                await pluginAvailability.refresh()
                await pluginSourceManager.refreshAvailableUpdates()
            }
        }
    }

    private var canInstallAll: Bool {
        !pluginSourceManager.isInstalling &&
        pluginSourceManager.remotePlugins.contains {
            $0.installState == .notInstalled && pluginSourceManager.installedVersion(for: $0.id) == nil
        }
    }

    private func installAll() {
        guard canInstallAll else { return }
        Task {
            let count = await pluginSourceManager.installAll()
            if count > 0 {
                PluginAppGroupSync.syncToAppGroup()
                await pluginAvailability.refresh()
            }
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }

    private func reloadPluginCatalog() async {
        await pluginSourceManager.fetchAllSourceIndexes()
        await pluginSourceManager.refreshAvailableUpdates()
    }

    /// cover mount 后由 .task 调用,处理外部触发的自动安装动作(一键安装 / deep link 等)。
    private func runAutoAction(_ action: PluginManagementAutoAction) async {
        switch action {
        case .oneClickInstall:
            await appViewModel.pluginSourceSyncService.performOneClickInstall(
                pluginSourceManager: pluginSourceManager,
                pluginAvailability: pluginAvailability,
                consentRequester: consentService
            )
        case .deepLinkInstall(let input):
            let added = await pluginSourceManager.addSourceFromInput(input)
            guard !added.isEmpty else { return }
            await pluginSourceManager.fetchAllSourceIndexes()
            let count = await pluginSourceManager.installAll()
            if count > 0 {
                PluginAppGroupSync.syncToAppGroup()
                await pluginAvailability.refresh()
            }
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }
}
