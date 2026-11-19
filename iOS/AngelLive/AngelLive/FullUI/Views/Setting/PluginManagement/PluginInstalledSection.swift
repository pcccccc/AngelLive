import SwiftUI
import AngelLiveCore

struct PluginInstalledSection: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    let items: [ManagedPluginItem]
    let highlightedIDs: Set<String>
    let searchIsEmpty: Bool
    let canOperate: Bool
    let open: (ManagedPluginItem) -> Void
    let action: (ManagedPluginItem, UUID?) -> Void
    let uninstall: (String) -> Void
    let login: (String) -> Void

    var body: some View {
        let separatorLeading = PluginManagementLayout.iconSize + PluginManagementLayout.iconTextSpacing
        let separatorTrailingInset = PluginManagementLayout.contentInset
        return Section {
            if items.isEmpty {
                PluginManagementEmptyState(title: searchIsEmpty ? "还没有安装插件" : "没有匹配的插件", message: searchIsEmpty ? "从下面的发现里选择你需要的插件。" : "请尝试其他搜索词。")
                    .listRowInsets(PluginManagementLayout.zeroInsets)
            }
            ForEach(items) { item in
                PluginManagementInstalledRow(item: item, highlighted: highlightedIDs.contains(item.pluginID), canOperate: canOperate, open: { open(item) }, action: { action(item, $0) })
                    .listRowInsets(PluginManagementLayout.rowInsets)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in separatorLeading }
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width + separatorTrailingInset }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { uninstall(item.pluginID) } label: { Label("卸载", systemImage: "trash") }
                            .tint(.red).disabled(!canOperate)
                            .accessibilityLabel("卸载 \(item.name)")
                        if manager.hasUpdate(for: item.pluginID) {
                            Button { action(item, nil) } label: { Label("更新", systemImage: "arrow.down") }
                                .tint(.blue).disabled(!canOperate)
                                .accessibilityLabel("更新 \(item.name)")
                        }
                    }
                    .contextMenu {
                        if manager.hasUpdate(for: item.pluginID) {
                            Button {
                                action(item, nil)
                            } label: {
                                Label(manager.updateBatch.failedPluginIds.contains(item.pluginID) ? "重试更新" : "更新到 \(manager.latestVersion(for: item.pluginID) ?? "")", systemImage: "arrow.down")
                            }.disabled(!canOperate)
                                .accessibilityLabel(manager.updateBatch.failedPluginIds.contains(item.pluginID) ? "重试更新 \(item.name)" : "更新 \(item.name)")
                        }
                        if availability.requiresLogin(for: item.pluginID), !credentials.isLoggedIn(pluginId: item.pluginID) {
                            Button("登录账号", systemImage: "key") { login(item.pluginID) }
                                .accessibilityLabel("登录 \(item.name) 账号")
                        }
                        Button("查看详情", systemImage: "info.circle") { open(item) }
                            .accessibilityLabel("查看 \(item.name) 详情")
                        Button("卸载", systemImage: "trash", role: .destructive) { uninstall(item.pluginID) }.disabled(!canOperate)
                            .accessibilityLabel("卸载 \(item.name)")
                    } preview: {
                        PluginManagementRowContent(item: item)
                            .environment(manager)
                            .environment(availability)
                            .padding(.horizontal, PluginManagementLayout.contentInset).padding(.vertical, PluginManagementLayout.rowVerticalInset)
                            .background(PluginManagementLayout.cardBackground)
                    }
                    .accessibilityAction(named: Text("查看 \(item.name) 详情")) { open(item) }
                    .accessibilityAction(named: Text("卸载 \(item.name)")) { uninstall(item.pluginID) }
            }
        } header: {
            PluginManagementSectionHeading(title: "已安装", subtitle: "\(items.count) 个", includesSectionSpacing: true)
        }
        .listRowInsets(PluginManagementLayout.zeroInsets)
    }
}

struct PluginManagementInstalledRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginManagementFeedback.self) private var feedback
    let item: ManagedPluginItem
    let highlighted: Bool
    let canOperate: Bool
    let open: () -> Void
    let action: (UUID) -> Void
    @State private var flash = false

    private var showsAction: Bool {
        manager.managementActionState(for: item.pluginID, remote: item.remote) != .installed
            || manager.isPendingInstallation(for: item.pluginID)
            || feedback.recentSuccessIDs.contains(item.pluginID)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: open) {
                        HStack(spacing: PluginManagementLayout.iconTextSpacing) { PluginManagementRowContent(item: item); chevron }
                    }.buttonStyle(PluginPressButtonStyle())
                    if showsAction {
                        PluginActionButton(item: item, canOperate: canOperate, action: action)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(actionTransition)
                    }
                }
            } else {
                HStack(spacing: PluginManagementLayout.iconTextSpacing) {
                    Button(action: open) { PluginManagementRowContent(item: item) }
                        .buttonStyle(PluginPressButtonStyle())
                    if showsAction {
                        PluginActionButton(item: item, canOperate: canOperate, action: action)
                            .transition(actionTransition)
                    }
                    chevron
                }
            }
        }
        .padding(.vertical, PluginManagementLayout.rowVerticalInset)
        .listRowBackground(flash ? PluginManagementLayout.primaryAction.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.15), value: showsAction)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: typeSize)
        .task(id: highlighted) {
            guard highlighted else { flash = false; return }
            flash = true
            do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.4)) { flash = false }
        }
    }

    private var actionTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .trailing))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

struct PluginManagementRowContent: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    let item: ManagedPluginItem

    private var version: String { manager.installedVersion(for: item.pluginID) ?? item.remote?.item.version ?? "未知" }
    private var metadata: String {
        var parts = [version]
        if manager.hasUpdate(for: item.pluginID), let next = manager.latestVersion(for: item.pluginID) { parts[0] += " → \(next)" }
        if availability.requiresLogin(for: item.pluginID) || item.remote?.item.auth?.required == true {
            parts.append(credentials.isLoggedIn(pluginId: item.pluginID) ? "已登录" : "需要登录")
        }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: PluginManagementLayout.iconTextSpacing) {
            PluginManagementIcon(pluginID: item.pluginID, displayName: item.name, remoteIcon: item.remote?.item.icon)
            VStack(alignment: .leading, spacing: PluginManagementLayout.textSpacing) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = item.installationFailure(in: manager) {
                    PluginInstallationFailureReason(reason: reason)
                } else {
                    Text(metadata).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: version)
    }
}
