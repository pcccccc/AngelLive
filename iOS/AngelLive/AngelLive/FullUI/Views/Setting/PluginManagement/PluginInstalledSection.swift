import SwiftUI
import AngelLiveCore

struct PluginInstalledSection: View {
    enum UninstallOrigin { case swipe, action }

    let items: [ManagedPluginItem]
    let highlightedIDs: Set<String>
    let searchIsEmpty: Bool
    let canOperate: Bool
    let open: (ManagedPluginItem) -> Void
    let action: (ManagedPluginItem, UUID?) -> Void
    let uninstall: (String, UninstallOrigin) -> Void
    let login: (String) -> Void

    var body: some View {
        Section {
            if items.isEmpty {
                PluginManagementEmptyState(title: searchIsEmpty ? "还没有安装插件" : "没有匹配的插件", message: searchIsEmpty ? "从下面的发现里选择你需要的插件。" : "请尝试其他搜索词。")
                    .listRowInsets(PluginManagementLayout.zeroInsets)
            }
            ForEach(items) { item in
                PluginManagementInstalledRow(
                    item: item, highlighted: highlightedIDs.contains(item.pluginID), canOperate: canOperate,
                    open: { open(item) }, action: { action(item, $0) },
                    uninstall: { uninstall(item.pluginID, $0) }, login: { login(item.pluginID) }
                )
                    .listRowInsets(PluginManagementLayout.rowInsets)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in
                        PluginManagementLayout.iconSize + PluginManagementLayout.iconTextSpacing
                    }
                    .alignmentGuide(.listRowSeparatorTrailing) { $0.width + PluginManagementLayout.contentInset }
            }
        } header: {
            PluginManagementSectionHeading(title: "已安装", subtitleCount: items.count, includesSectionSpacing: true)
        }
        .listRowInsets(PluginManagementLayout.zeroInsets)
    }
}

struct PluginManagementInstalledRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: ManagedPluginItem
    let highlighted: Bool
    let canOperate: Bool
    let open: () -> Void
    let action: (UUID?) -> Void
    let uninstall: (PluginInstalledSection.UninstallOrigin) -> Void
    let login: () -> Void
    @State private var flash = false

    private var showsAction: Bool {
        let action = item.row.action
        return action.state != .installed || action.pending || action.succeeded
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: open) {
                        HStack(spacing: PluginManagementLayout.iconTextSpacing) { PluginManagementRowContent(item: item); chevron }
                    }.buttonStyle(PluginPressButtonStyle())
                    if showsAction {
                        PluginActionButton(item: item, canOperate: canOperate, action: { action($0) })
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(actionTransition)
                    }
                }
            } else {
                HStack(spacing: PluginManagementLayout.iconTextSpacing) {
                    Button(action: open) { PluginManagementRowContent(item: item) }
                        .buttonStyle(PluginPressButtonStyle())
                    if showsAction {
                        PluginActionButton(item: item, canOperate: canOperate, action: { action($0) })
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { uninstall(.swipe) } label: { Label("卸载", systemImage: "trash") }
                .disabled(!canOperate)
                .accessibilityLabel("卸载 \(item.name)")
            if item.row.action.updateVersion != nil {
                Button { action(nil) } label: { Label("更新", systemImage: "arrow.down") }
                    .tint(.blue).disabled(!canOperate)
                    .accessibilityLabel("更新 \(item.name)")
            }
        }
        .contextMenu {
            if let version = item.row.action.updateVersion {
                let updateFailed = item.row.action.updateFailed
                Button { action(nil) } label: {
                    Label(updateFailed ? "重试更新" : "更新到 \(version)", systemImage: "arrow.down")
                }.disabled(!canOperate)
                    .accessibilityLabel(updateFailed ? "重试更新 \(item.name)" : "更新 \(item.name)")
            }
            if item.row.metadata.requiresLogin, !item.row.loggedIn {
                Button("登录账号", systemImage: "key", action: login)
                    .accessibilityLabel("登录 \(item.name) 账号")
            }
            Button("查看详情", systemImage: "info.circle", action: open)
                .accessibilityLabel("查看 \(item.name) 详情")
            Button("卸载", systemImage: "trash", role: .destructive) { uninstall(.action) }.disabled(!canOperate)
                .accessibilityLabel("卸载 \(item.name)")
        } preview: {
            PluginManagementRowContent(item: item)
                .padding(.horizontal, PluginManagementLayout.contentInset).padding(.vertical, PluginManagementLayout.rowVerticalInset)
                .background(PluginManagementLayout.cardBackground)
        }
        .accessibilityAction(named: Text("查看 \(item.name) 详情"), open)
        .accessibilityAction(named: Text("卸载 \(item.name)")) { uninstall(.action) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ManagedPluginItem

    private var version: String { item.row.metadata.version }
    private var metadata: String {
        var parts = [version]
        if let next = item.row.action.updateVersion { parts[0] += " → \(next)" }
        if item.row.metadata.requiresLogin || item.remote?.item.auth?.required == true {
            parts.append(item.row.loggedIn ? "已登录" : "需要登录")
        }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: PluginManagementLayout.iconTextSpacing) {
            PluginManagementIcon(pluginID: item.pluginID, displayName: item.name, remoteIcon: item.remote?.item.icon)
            VStack(alignment: .leading, spacing: PluginManagementLayout.textSpacing) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = item.row.action.failure {
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
