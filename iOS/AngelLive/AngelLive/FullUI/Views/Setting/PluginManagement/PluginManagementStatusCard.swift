import SwiftUI
import AngelLiveCore

struct PluginManagementStatusCard: View {
    let manager: PluginSourceManager
    let installedIDs: [String]
    let isPreparing: Bool
    let preparationTitle: String?
    let preparationError: String?
    let lastChecked: Date?
    let canStop: Bool
    let update: ([String]) -> Void
    let retryInstall: () -> Void
    let check: () -> Void
    let retryPreparation: () -> Void
    let stop: () -> Void
    let consentHostID: UUID
    let showsConsent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var updates: [String] { installedIDs.filter { $0 != manager.pendingUninstallPluginId && manager.hasUpdate(for: $0) } }
    private var sourceFailures: [String] { manager.sourceURLs.filter { manager.health(for: $0).isFailed } }
    private var hasFailures: Bool { preparationError != nil || manager.errorMessage != nil || !sourceFailures.isEmpty || !manager.installBatch.failedPluginIds.isEmpty || !manager.updateBatch.failedPluginIds.isEmpty }
    private var running: Bool { manager.installBatch.isRunning || manager.updateBatch.isRunning }
    private var state: PluginManagementSummaryState {
        .resolve(isRunning: running, hasFailures: hasFailures, updateCount: updates.count,
                 isChecking: isPreparing || manager.isFetchingIndex || manager.isCheckingUpdates,
                 isVerifiedCurrent: !installedIDs.isEmpty && !manager.sourceURLs.isEmpty && manager.sourceURLs.allSatisfy { if case .healthy = manager.health(for: $0) { true } else { false } } && installedIDs.allSatisfy { manager.latestVersion(for: $0) != nil })
    }
    private var title: LocalizedStringResource {
        switch state {
        case .running: manager.installBatch.isRunning ? "正在安装插件" : "正在更新插件"
        case .failed:
            if preparationError != nil { "准备安装失败" }
            else if !manager.installBatch.failedPluginIds.isEmpty { "\(manager.installBatch.failedPluginIds.count) 个插件安装失败" }
            else if !manager.updateBatch.failedPluginIds.isEmpty { "\(manager.updateBatch.failedPluginIds.count) 个更新失败" }
            else if manager.errorMessage != nil { "操作未完成" }
            else { "部分来源未能检查" }
        case .updates(let count): "\(count) 个更新"
        case .checking: "正在检查更新"
        case .current: "全部最新"
        case .unchecked: installedIDs.isEmpty ? "还没有安装插件" : "尚未完成检查"
        }
    }
    private var subtitle: String {
        if manager.installBatch.isRunning {
            let batch = manager.installBatch
            return "\(batch.completedCount) / \(batch.pluginIds.count) · \(batch.currentPluginId.flatMap { batch.displayNames[$0] } ?? "准备中")"
        }
        if manager.updateBatch.isRunning {
            let batch = manager.updateBatch
            return "\(batch.completedCount) / \(batch.pluginIds.count) · \(batch.currentPluginId.map { manager.managementDisplayName(for: $0) } ?? "准备中")"
        }
        if let preparationError { return SupportDiagnosticSanitizer.text(preparationError) }
        if let error = manager.errorMessage { return SupportDiagnosticSanitizer.text(error) }
        if !manager.installBatch.failedPluginIds.isEmpty { return "安装结果：\(manager.installBatch.successCount) 成功 · \(manager.installBatch.failedPluginIds.count) 失败 · \(manager.installBatch.cancelledCount) 取消" }
        if !manager.updateBatch.failedPluginIds.isEmpty { return "旧版本仍可用，可以重试失败项" }
        if !sourceFailures.isEmpty { return "\(sourceFailures.count) 个来源异常，请重试" }
        if !updates.isEmpty { return updates.map { manager.managementDisplayName(for: $0) }.joined(separator: "、") }
        if isPreparing { return preparationTitle ?? "正在读取插件列表…" }
        if manager.isFetchingIndex || manager.isCheckingUpdates { return "正在读取 \(manager.sourceURLs.count) 个来源" }
        if !manager.installBatch.pluginIds.isEmpty { return "安装结果：\(manager.installBatch.successCount) 成功 · \(manager.installBatch.failedPluginIds.count) 失败 · \(manager.installBatch.cancelledCount) 取消" }
        if !manager.updateBatch.pluginIds.isEmpty { return "已更新 \(manager.updateBatch.successCount) 个 · 取消 \(manager.updateBatch.outcomes.values.filter { $0 == .cancelled }.count) 个" }
        if installedIDs.isEmpty { return "从下面的发现里选择你需要的插件" }
        if let lastChecked { return "上次检查：\(lastChecked.formatted(date: .omitted, time: .shortened))" }
        return manager.sourceURLs.isEmpty ? "添加来源以获取更新" : "已安装 \(installedIDs.count) 个插件"
    }
    private var symbol: String {
        switch state {
        case .running, .updates: "arrow.down"
        case .failed: "exclamationmark.triangle.fill"
        case .checking: "arrow.clockwise"
        case .current: "checkmark"
        case .unchecked: "puzzlepiece.extension"
        }
    }
    private var color: Color { state == .failed ? .red : state == .current ? .green : PluginManagementLayout.primaryAction }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: PluginManagementLayout.iconTextSpacing)) : AnyLayout(HStackLayout(spacing: PluginManagementLayout.iconTextSpacing))
            layout {
                if case .updates = state {
                    HStack(spacing: -12) {
                        ForEach(Array(updates.prefix(3)), id: \.self) { id in
                            PluginManagementIcon(pluginID: id, displayName: manager.managementDisplayName(for: id), remoteIcon: manager.latestRemoteItemsByPluginId[id]?.icon, size: 36)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2.5))
                        }
                    }.accessibilityHidden(true).transition(.opacity)
                } else {
                    Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(color)
                        .frame(width: 36, height: 36).background(color.opacity(0.12), in: Circle()).accessibilityHidden(true)
                        .contentTransition(.opacity).transition(.opacity)
                }
                VStack(alignment: .leading, spacing: PluginManagementLayout.textSpacing) {
                    Text(title).font(.headline).contentTransition(.opacity)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true).monospacedDigit()
                        .contentTransition(.opacity)
                }.frame(maxWidth: .infinity, alignment: .leading)
                PluginSummaryAction(state: state, manager: manager, canStop: canStop,
                                    updateIDs: updates, preparationFailed: preparationError != nil,
                                    update: update, retryInstall: retryInstall, check: check,
                                    retryPreparation: retryPreparation, stop: stop)
            }.padding(.horizontal, PluginManagementLayout.contentInset).padding(.vertical, PluginManagementLayout.summaryVerticalInset)
            if running {
                ProgressView(value: Double(manager.installBatch.isRunning ? manager.installBatch.completedCount : manager.updateBatch.completedCount), total: Double(max(1, manager.installBatch.isRunning ? manager.installBatch.pluginIds.count : manager.updateBatch.pluginIds.count)))
                    .padding(.horizontal, PluginManagementLayout.contentInset).padding(.bottom, PluginManagementLayout.summaryVerticalInset)
                    .transition(.opacity)
            }
            if state == .failed && (!manager.installBatch.failedPluginIds.isEmpty || !manager.updateBatch.failedPluginIds.isEmpty) {
                PluginBatchFailures(manager: manager).padding(.horizontal, PluginManagementLayout.contentInset)
                    .transition(.opacity)
            }
            if !running && !manager.installBatch.pluginIds.isEmpty {
                Text("安装：\(manager.installBatch.successCount) 成功 · \(manager.installBatch.failedPluginIds.count) 失败 · \(manager.installBatch.cancelledCount) 取消")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, PluginManagementLayout.contentInset).padding(.bottom, PluginManagementLayout.summaryVerticalInset)
            }
            if !running && !manager.updateBatch.pluginIds.isEmpty {
                Text("更新：\(manager.updateBatch.successCount) 成功 · \(manager.updateBatch.failedPluginIds.count) 失败 · \(manager.updateBatch.outcomes.values.filter { $0 == .cancelled }.count) 取消")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, PluginManagementLayout.contentInset).padding(.bottom, PluginManagementLayout.summaryVerticalInset)
            }
            if showsConsent { PluginInstallConsentPanel(hostID: consentHostID) }
        }
        .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: state)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: subtitle)
    }
}

private struct PluginSummaryAction: View {
    let state: PluginManagementSummaryState
    let manager: PluginSourceManager
    let canStop: Bool
    let updateIDs: [String]
    let preparationFailed: Bool
    let update: ([String]) -> Void
    let retryInstall: () -> Void
    let check: () -> Void
    let retryPreparation: () -> Void
    let stop: () -> Void
    var body: some View {
        VStack {
            switch state {
            case .running:
                if canStop { PluginSummaryButton(title: "停止", color: .secondary, isSecondary: true, action: stop) }
            case .failed:
                PluginSummaryButton(title: "重试", color: .red) {
                    if preparationFailed { retryPreparation() }
                    else if !manager.installBatch.failedPluginIds.isEmpty { retryInstall() }
                    else if !manager.updateBatch.failedPluginIds.isEmpty { update(manager.updateBatch.failedPluginIds) }
                    else { check() }
                }.disabled(manager.isManagementBusy)
            case .updates:
                PluginSummaryButton(title: "全部更新", color: PluginManagementLayout.primaryAction) { update(updateIDs) }.disabled(manager.isManagementBusy)
                    .accessibilityIdentifier("plugins.updateAll")
            case .checking: ProgressView().accessibilityLabel("正在检查更新")
            case .unchecked:
                if !manager.sourceURLs.isEmpty { PluginSummaryButton(title: "检查", color: PluginManagementLayout.primaryAction, action: check) }
            case .current: EmptyView()
            }
        }.frame(minHeight: PluginManagementLayout.minimumTarget)
    }
}

private struct PluginSummaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    let color: Color
    var isSecondary = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(isSecondary ? PluginManagementLayout.primaryText : .white)
                .padding(.horizontal, PluginManagementLayout.contentInset)
                .padding(.vertical, 6)
                .background(isSecondary ? Color(uiColor: .tertiarySystemFill) : color, in: Capsule())
                .frame(minHeight: PluginManagementLayout.minimumTarget)
                .contentShape(Rectangle())
        }.buttonStyle(PluginPressButtonStyle()).opacity(isEnabled ? 1 : 0.45)
    }
}

private struct PluginBatchFailures: View {
    let manager: PluginSourceManager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(manager.installBatch.failedPluginIds, id: \.self) { id in
                if case .failed(let reason) = manager.installBatch.outcomes[id] {
                    Text("\(manager.installBatch.displayNames[id] ?? id)：\(SupportDiagnosticSanitizer.text(reason))")
                }
            }
            ForEach(manager.updateBatch.failedPluginIds, id: \.self) { id in
                if case .failed(let reason) = manager.updateBatch.outcomes[id] {
                    Text("\(manager.managementDisplayName(for: id))：\(SupportDiagnosticSanitizer.text(reason))")
                }
            }
        }.font(.footnote).foregroundStyle(.secondary).padding(.bottom, PluginManagementLayout.summaryVerticalInset)
    }
}

struct PluginInstallationScopeNotice: View {
    @Environment(PluginSourceManager.self) private var manager
    let sourceURLs: [String]
    let showAll: () -> Void
    let retry: (String) -> Void
    var body: some View {
        Section {
            ForEach(sourceURLs, id: \.self) { url in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pluginSourceHost(url)).font(.subheadline.weight(.semibold))
                    PluginSourceHealthLabel(health: manager.health(for: url))
                    if case .failed(let reason) = manager.health(for: url) {
                        Text(SupportDiagnosticSanitizer.text(reason)).font(.footnote).foregroundStyle(.secondary)
                        Button("重试") { retry(url) }.disabled(manager.isManagementBusy)
                    }
                }
            }
            Button("查看所有来源的插件", action: showAll).disabled(manager.isManagementBusy)
        } header: {
            VStack(alignment: .leading, spacing: 0) {
                PluginManagementSectionGap()
                Text("本次安装来源")
            }
        }
    }
}
