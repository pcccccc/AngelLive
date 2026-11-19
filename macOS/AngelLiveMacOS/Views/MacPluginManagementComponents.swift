import AppKit
import ImageIO
import SwiftUI
import AngelLiveCore

nonisolated enum MacPluginLayout {
    static let sheetMinimumWidth: CGFloat = 850
    static let sheetIdealWidth: CGFloat = 920
    static let sheetMinimumHeight: CGFloat = 580
    static let sheetIdealHeight: CGFloat = 640
    static let sidebarMinimumWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 250
    static let sidebarMaximumWidth: CGFloat = 280
    static let pageInset: CGFloat = 30
    static let columnInset: CGFloat = 18
    static let sectionSpacing: CGFloat = 24
    static let titleGap: CGFloat = 6
    static let rowGap: CGFloat = 10
    static let cardInset: CGFloat = 12
    static let cornerRadius: CGFloat = 9
    static let rowIcon: CGFloat = 32
    static let detailIcon: CGFloat = 56
    static let headerTrailingInset: CGFloat = 20
    static let headerGap: CGFloat = 16
    static let headerVerticalInset: CGFloat = 16
    static let searchWidth: CGFloat = 160
    static let activityMaximumWidth: CGFloat = 420
    static let toolbarControlHeight: CGFloat = 26
    static let tagSpacing: CGFloat = 8
    // Native sidebar headers extend beyond row content. The original 2× captures
    // place header ink 3 px before the icons and counts 26 px past row actions.
    static let sectionHeadingOpticalInset: CGFloat = 1.5
    static let sectionHeadingTrailingInset: CGFloat = 13
}

extension EnvironmentValues {
    @Entry var macPluginConsentHost: UUID?
    @Entry var macPluginConsentOrigin: Binding<MacPluginConsentOrigin?>?
}

struct MacPluginConsentOrigin {
    let buttonID: UUID
    let pluginID: String

    func matches(_ reason: PluginInstallConsentReason?) -> Bool {
        switch reason {
        case .installingLoginPlugin(let id, _): id == pluginID
        case .installingLoginPluginsBatch(let plugins): plugins.count == 1 && plugins.first?.pluginId == pluginID
        default: false
        }
    }
}

struct MacManagedPlugin: Identifiable {
    let id: String
    let name: String
    let sourceURL: String?
    let remote: RemotePluginDisplayItem?
    let installed: Bool
    var host: String { sourceURL.flatMap { URL(string: $0)?.host() } ?? "本地插件" }

    @MainActor func phase(in manager: PluginSourceManager, isSuccessful: Bool) -> PluginManagementRowPhase {
        if manager.installationProgress(for: id) != nil { return .progress }
        let state = manager.managementActionState(for: id, remote: remote)
        let isWaiting = manager.isPendingInstallation(for: id)
            && manager.installBatch.currentPluginId != id && manager.updateBatch.currentPluginId != id
        return .resolve(actionState: state, isWaiting: isWaiting, isSuccessful: isSuccessful)
    }
}

struct MacPluginManagementHeader: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @Binding var searchText: String
    let searchFocusRequest: Int
    @Binding var showSources: Bool
    @Binding var showAddSource: Bool
    let canAdd: Bool
    let lastChecked: Date?
    let preparationError: String?
    let installedIDs: [String]
    let update: () -> Void
    let retry: () -> Void
    let check: () -> Void
    let stop: () -> Void
    let reloadCatalog: () async -> Void
    let commitPending: () -> Bool

    var body: some View {
        MacPluginHeaderLayout(layoutDirection: layoutDirection) {
            Text("插件").font(.headline).fixedSize()
            MacPluginActivity(
                installedIDs: installedIDs, lastChecked: lastChecked,
                preparationError: preparationError,
                update: update, retry: retry, check: check, stop: stop
            )
            HStack(spacing: MacPluginLayout.headerGap) {
                MacPluginSearchField(text: $searchText, focusRequest: searchFocusRequest)
                    .frame(width: MacPluginLayout.searchWidth)
                Button {
                    showAddSource = false
                    showSources.toggle()
                } label: {
                    Image(systemName: "link").frame(width: 24, height: MacPluginLayout.toolbarControlHeight)
                }
                .buttonStyle(.borderless).help("来源").accessibilityLabel("来源")
                .disabled(!canAdd)
                .popover(isPresented: $showSources, arrowEdge: .bottom) {
                    MacPluginSourcesView(reloadCatalog: reloadCatalog, commitPending: commitPending)
                        .frame(width: 360)
                        .onExitCommand { showSources = false }
                }
                Button {
                    showSources = false
                    showAddSource.toggle()
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: MacPluginLayout.toolbarControlHeight)
                }
                .buttonStyle(.borderless).help("添加来源").accessibilityLabel("添加来源")
                .disabled(!canAdd)
                .popover(isPresented: $showAddSource, arrowEdge: .bottom) {
                    MacPluginAddSourceView(reloadCatalog: reloadCatalog)
                        .frame(width: 350)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, MacPluginLayout.headerVerticalInset)
    }
}

private struct MacPluginHeaderLayout: Layout {
    let layoutDirection: LayoutDirection

    // The three children are the title, centered activity, and trailing controls.
    // Reserve the wider edge on both sides so unequal controls cannot shift the activity.
    private func edgeReservation(subviews: Subviews) -> CGFloat {
        max(MacPluginLayout.pageInset + subviews[0].sizeThatFits(.unspecified).width,
            MacPluginLayout.headerTrailingInset + subviews[2].sizeThatFits(.unspecified).width)
            + MacPluginLayout.headerGap
    }

    private func activityWidth(in width: CGFloat, subviews: Subviews) -> CGFloat {
        min(MacPluginLayout.activityMaximumWidth, max(0, width - 2 * edgeReservation(subviews: subviews)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = 2 * edgeReservation(subviews: subviews) + MacPluginLayout.activityMaximumWidth
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let activitySize = subviews[1].sizeThatFits(
            ProposedViewSize(width: activityWidth(in: width, subviews: subviews), height: nil)
        )
        let height = max(activitySize.height,
                         subviews[0].sizeThatFits(.unspecified).height,
                         subviews[2].sizeThatFits(.unspecified).height)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let titleSize = subviews[0].sizeThatFits(.unspecified)
        let controlsSize = subviews[2].sizeThatFits(.unspecified)
        let isRightToLeft = layoutDirection == .rightToLeft
        let titleX = isRightToLeft
            ? bounds.maxX - MacPluginLayout.pageInset - titleSize.width / 2
            : bounds.minX + MacPluginLayout.pageInset + titleSize.width / 2
        let controlsX = isRightToLeft
            ? bounds.minX + MacPluginLayout.headerTrailingInset + controlsSize.width / 2
            : bounds.maxX - MacPluginLayout.headerTrailingInset - controlsSize.width / 2

        subviews[0].place(at: CGPoint(x: titleX, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[1].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
            proposal: ProposedViewSize(width: activityWidth(in: bounds.width, subviews: subviews), height: nil)
        )
        subviews[2].place(at: CGPoint(x: controlsX, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}

struct MacPluginActivity: View {
    @Environment(PluginSourceManager.self) private var manager
    let installedIDs: [String]
    let lastChecked: Date?
    let preparationError: String?
    let update: () -> Void
    let retry: () -> Void
    let check: () -> Void
    let stop: () -> Void

    private var updateCount: Int { installedIDs.filter { manager.hasUpdate(for: $0) }.count }
    private var hasFailures: Bool {
        preparationError != nil || manager.errorMessage != nil ||
        !manager.updateBatch.failedPluginIds.isEmpty || !manager.installBatch.failedPluginIds.isEmpty ||
        manager.sourceHealth.values.contains { $0.isFailed }
    }
    private var state: PluginManagementSummaryState {
        .resolve(
            isRunning: manager.activeInstallationCount > 0,
            hasFailures: hasFailures, updateCount: updateCount,
            isChecking: manager.isFetchingIndex || manager.isCheckingUpdates,
            isVerifiedCurrent: !installedIDs.isEmpty && !manager.sourceURLs.isEmpty &&
                manager.sourceURLs.allSatisfy { if case .healthy = manager.health(for: $0) { true } else { false } } &&
                installedIDs.allSatisfy { manager.latestVersion(for: $0) != nil }
        )
    }
    private var title: LocalizedStringResource {
        switch state {
        case .running: "正在安装 \(manager.activeInstallationCount) 个插件"
        case .failed:
            if preparationError != nil { "准备安装失败" }
            else if !manager.installBatch.failedPluginIds.isEmpty { "\(manager.installBatch.failedPluginIds.count) 个安装失败" }
            else if !manager.updateBatch.failedPluginIds.isEmpty { "\(manager.updateBatch.failedPluginIds.count) 个更新失败" }
            else if manager.errorMessage != nil { "操作未完成" }
            else { "来源读取失败" }
        case .updates(let count): "\(count) 个更新"
        case .checking: "正在检查更新"
        case .current: "全部最新"
        case .unchecked: installedIDs.isEmpty ? "还没有安装插件" : "尚未完成检查"
        }
    }
    private var subtitle: String {
        let cancelled = manager.installBatch.cancelledCount
        if !manager.installBatch.isRunning, state != .running, state != .failed, cancelled > 0 {
            return "\(cancelled) 个安装已取消"
        }
        return switch state {
        case .current: lastChecked.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        case .checking: "\(manager.sourceURLs.count) 个来源"
        case .failed: SupportDiagnosticSanitizer.text(preparationError ?? manager.errorMessage ?? "可以重试")
        default: ""
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if state != .running {
                Group {
                    if state == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: state == .failed ? "exclamationmark.triangle" :
                                state == .current ? "checkmark.circle" : "arrow.down.circle")
                            .foregroundStyle(state == .failed ? Color.red : state == .current ? Color.green : Color.accentColor)
                    }
                }
                .frame(width: 16)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.callout).lineLimit(1).layoutPriority(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                switch state {
                case .running: Button("全部停止", action: stop)
                case .failed: Button("重试", action: retry).foregroundStyle(.red).disabled(manager.isManagementBusy)
                case .updates: Button("全部更新", action: update).disabled(manager.isManagementBusy)
                case .checking: EmptyView()
                default: Button("检查更新", action: check).disabled(manager.sourceURLs.isEmpty || manager.isManagementBusy)
                }
            }
            .buttonStyle(.borderless).font(.callout)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .frame(height: MacPluginLayout.toolbarControlHeight)
        .background(state == .failed ? Color.red.opacity(0.1) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: MacPluginLayout.cornerRadius))
        .contentTransition(.numericText())
        .help(SupportDiagnosticSanitizer.text(subtitle))
        .modifier(MacPluginConsentPopover(buttonID: nil))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plugins.activity")
    }
}

struct MacPluginSidebar: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: String?
    let installed: [MacManagedPlugin]
    let discovered: [MacManagedPlugin]
    let installedCount: Int
    let query: String
    let discoverySourceLabels: [String: String]
    let canOperate: Bool
    let recentSuccessIDs: Set<String>
    let clearSearch: () -> Void
    let addSource: () -> Void
    let retrySources: () -> Void
    let action: (MacManagedPlugin, UUID?) -> Void
    let uninstall: (String) -> Void
    let login: (String) -> Void

    var body: some View {
        List(selection: $selection) {
                Section {
                    if installed.isEmpty {
                        MacPluginEmptyState(
                            title: query.isEmpty ? "暂无已安装插件" : "没有匹配的已安装插件",
                            message: query.isEmpty ? "从发现中选择需要的插件进行安装。" : "请尝试其他名称或清除搜索。",
                            systemImage: query.isEmpty ? "puzzlepiece.extension" : "magnifyingglass",
                            actionTitle: query.isEmpty ? nil : "清除搜索",
                            action: query.isEmpty ? nil : clearSearch
                        )
                    }
                    ForEach(installed) { item in
                        MacPluginSidebarRow(
                            item: item, canOperate: canOperate,
                            sourceLabel: nil,
                            isSelected: selection == item.id,
                            isSuccessful: recentSuccessIDs.contains(item.id),
                            action: { action(item, $0) }, uninstall: { uninstall(item.id) },
                            login: { login(item.id) }
                        )
                        .tag(item.id)
                    }
                } header: {
                    MacPluginSectionHeading(title: "已安装", count: installedCount)
                }
                Section {
                    if discovered.isEmpty {
                        MacPluginEmptyState(
                            title: discoveryEmptyTitle, message: discoveryEmptyMessage,
                            systemImage: manager.sourceHealth.values.contains { $0.isFailed } ? "exclamationmark.triangle" : "magnifyingglass",
                            actionTitle: !query.isEmpty ? "清除搜索" : manager.sourceURLs.isEmpty ? "添加来源" : "重新读取",
                            action: !query.isEmpty ? clearSearch : manager.sourceURLs.isEmpty ? addSource : retrySources,
                            actionDisabled: !canOperate,
                            isFailure: query.isEmpty && manager.sourceHealth.values.contains { $0.isFailed }
                        )
                    }
                    ForEach(discovered) { item in
                        MacPluginSidebarRow(
                            item: item, canOperate: canOperate,
                            sourceLabel: discoverySourceLabels[item.id],
                            isSelected: selection == item.id,
                            isSuccessful: recentSuccessIDs.contains(item.id),
                            action: { action(item, $0) }, uninstall: { uninstall(item.id) },
                            login: { login(item.id) }
                        )
                        .tag(item.id)
                    }
                } header: {
                    MacPluginSectionHeading(title: "发现", count: discovered.count)
                }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.background.secondary)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3), value: installed.map(\.id))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3), value: discovered.map(\.id))
        .accessibilityLabel("插件列表")
    }

    private var discoveryEmptyTitle: LocalizedStringKey {
        if !query.isEmpty { return "没有匹配的可安装插件" }
        if manager.sourceHealth.values.contains(where: { $0.isFailed }) { return "来源读取失败" }
        return manager.sourceURLs.isEmpty ? "还没有来源" : "暂无可安装插件"
    }

    private var discoveryEmptyMessage: LocalizedStringKey {
        if !query.isEmpty { return "请尝试其他名称或清除搜索。" }
        if manager.sourceHealth.values.contains(where: { $0.isFailed }) { return "在来源气泡中查看原因并重试。" }
        return manager.sourceURLs.isEmpty ? "添加来源后，选择需要安装的插件。" : "当前来源中的插件均已安装。"
    }
}

struct MacPluginSectionHeading: View {
    let title: LocalizedStringKey
    let count: Int
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number).monospacedDigit()
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.leading, MacPluginLayout.sectionHeadingOpticalInset)
        .padding(.trailing, MacPluginLayout.sectionHeadingTrailingInset)
    }
}

struct MacPluginSidebarRow: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    let item: MacManagedPlugin
    let canOperate: Bool
    let sourceLabel: String?
    let isSelected: Bool
    let isSuccessful: Bool
    let action: (UUID?) -> Void
    let uninstall: () -> Void
    let login: () -> Void

    private var phase: PluginManagementRowPhase {
        item.phase(in: manager, isSuccessful: isSuccessful)
    }
    private var version: String { manager.installedVersion(for: item.id) ?? item.remote?.item.version ?? "未知" }
    private var metadata: String {
        var values = [manager.hasUpdate(for: item.id) ? "\(version) → \(manager.latestVersion(for: item.id) ?? version)" : version]
        if availability.requiresLogin(for: item.id) || item.remote?.item.auth?.required == true {
            values.append(credentials.isLoggedIn(pluginId: item.id) ? "已登录" : "需要登录")
        }
        if let sourceLabel { values.append(sourceLabel) }
        return values.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: MacPluginLayout.rowGap) {
            MacPluginIcon(pluginID: item.id, displayName: item.name, remoteIcon: item.remote?.item.icon, size: MacPluginLayout.rowIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text(metadata).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).contentTransition(.numericText())
                if case .failed(let reason) = phase {
                    MacPluginInstallationFailure(reason: reason)
                }
            }
            Spacer(minLength: 2)
            MacPluginActionButton(
                item: item, phase: phase, large: false, isSelected: isSelected,
                canOperate: canOperate,
                action: action
            )
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            MacPluginContextActions(item: item, phase: phase, canOperate: canOperate,
                                    action: { action(nil) }, uninstall: uninstall, login: login)
        }
    }
}

struct MacPluginContextActions: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(PluginAvailabilityService.self) private var availability
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    let item: MacManagedPlugin
    let phase: PluginManagementRowPhase
    let canOperate: Bool
    let action: () -> Void
    let uninstall: () -> Void
    let login: () -> Void

    var body: some View {
        Group {
            switch phase {
            case .update: Button("更新", action: action).disabled(!canOperate)
            case .failed: Button("重试", action: action).disabled(!canOperate)
            case .install: Button("安装", action: action).disabled(!canOperate)
            case .progress, .queued:
                Button("停止") { manager.cancelInstallation(pluginId: item.id) }
                    .disabled(consent.isPresenting || !manager.isPendingInstallation(for: item.id))
            default: EmptyView()
            }
            if item.installed, availability.requiresLogin(for: item.id), !credentials.isLoggedIn(pluginId: item.id) {
                Button("登录账号…", action: login).disabled(!canOperate)
            }
            if let source = item.sourceURL {
                Button("拷贝来源地址") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source, forType: .string)
                }
            }
            if item.installed {
                Divider()
                Button("卸载", role: .destructive, action: uninstall)
                    .keyboardShortcut(.delete, modifiers: .command).disabled(!canOperate)
            }
        }
    }
}

struct MacPluginActionButton: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(\.macPluginConsentOrigin) private var consentOrigin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MacManagedPlugin
    let phase: PluginManagementRowPhase
    let large: Bool
    let isSelected: Bool
    let canOperate: Bool
    let action: (UUID) -> Void
    @State private var buttonID = UUID()
    @State private var isHovered = false

    private var title: LocalizedStringResource {
        switch phase {
        case .install: "安装"
        case .update: large ? "更新到 \(manager.latestVersion(for: item.id) ?? "")" : "更新"
        case .failed: "重试"
        case .queued: "取消排队"
        case .progress: pending ? "停止" : "正在处理"
        case .success, .idle: "已安装"
        }
    }

    private var progress: PluginInstallationProgress? { manager.installationProgress(for: item.id) }
    private var busy: Bool { phase == .queued || phase == .progress }
    private var pending: Bool { manager.isPendingInstallation(for: item.id) }
    private var isEnabled: Bool { busy ? pending && !consent.isPresenting : canOperate && phase != .success }
    private var progressDescription: Text {
        if phase == .queued { return Text("等待中") }
        switch progress {
        case .downloading(let fraction):
            if let fraction { return Text("已下载 \(fraction, format: .percent.precision(.fractionLength(0)))") }
            return Text("正在下载")
        case .verifyingAndExtracting: return Text("正在校验和解压")
        case .activating: return Text("正在激活")
        case nil: return busy ? Text("正在准备") : Text("")
        }
    }

    var body: some View {
        if phase != .idle {
            button
                .onScrollVisibilityChange(threshold: 0.01) { visible in
                    if !visible { clearConsentOrigin() }
                }
                .onDisappear(perform: clearConsentOrigin)
        }
    }

    private var button: some View {
        let shape = RoundedRectangle(cornerRadius: large ? 7 : 11)
        return Button {
            if busy {
                manager.cancelInstallation(pluginId: item.id)
            } else {
                action(buttonID)
            }
        } label: {
            Group {
                if busy {
                    MacPluginInstallationRing(
                        fraction: phase == .queued ? 0 : progress?.fractionCompleted,
                        showsStop: pending
                    )
                    .frame(width: large ? 22 : 18, height: large ? 22 : 18)
                } else {
                    Text(title).lineLimit(1)
                        .padding(.horizontal, large ? 14 : 10)
                }
            }
            .font(.callout.weight(.semibold))
            .frame(minWidth: large ? 132 : 48, minHeight: large ? 28 : 22)
            .foregroundStyle(buttonForeground)
            .background(buttonBackground, in: shape)
            .overlay {
                shape.strokeBorder(Color(nsColor: .controlTextColor).opacity(isSelected && isPill ? 0.6 : 0))
            }
            .overlay {
                shape.fill(Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .modifier(MacPluginConsentPopover(buttonID: buttonID))
        .help(Text(title))
        .accessibilityLabel(Text("\(String(localized: title)) \(item.name)"))
        .accessibilityValue(progressDescription)
        .accessibilityIdentifier("plugins.action.\(item.name)")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
    }

    private func clearConsentOrigin() {
        if consentOrigin?.wrappedValue?.buttonID == buttonID { consentOrigin?.wrappedValue = nil }
    }

    private var buttonBackground: Color {
        if isSelected && isPill { return Color(nsColor: .controlBackgroundColor) }
        if isPill { return large ? (isFailed ? .red : .accentColor) : (isFailed ? .red.opacity(0.1) : .accentColor.opacity(0.12)) }
        if busy { return .primary.opacity(0.07) }
        return .clear
    }

    private var buttonForeground: Color {
        if isSelected { return Color(nsColor: .controlTextColor) }
        if phase == .success { return .secondary }
        return large && isPill ? .white : isFailed ? .red : .accentColor
    }

    private var isFailed: Bool { if case .failed = phase { true } else { false } }
    private var isPill: Bool {
        switch phase { case .install, .update, .failed: true; default: false }
    }
}

private struct MacPluginInstallationRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double?
    let showsStop: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 2).opacity(0.18)
            if let fraction {
                arc(fraction).rotationEffect(.degrees(-90))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    let rotation = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    arc(0.72).rotationEffect(.degrees(reduceMotion ? -90 : rotation))
                }
            }
            if showsStop {
                Image(systemName: "stop.fill").font(.system(size: 7))
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(_ fraction: Double) -> some View {
        Circle().inset(by: 1).trim(from: 0, to: CGFloat(fraction))
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}

private struct MacPluginInstallationFailure: View {
    let reason: String

    var body: some View {
        let message = SupportDiagnosticSanitizer.text(reason, limit: 512)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        (message.isEmpty ? Text("操作失败，请重试") : Text(message))
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}

private struct MacPluginConsentPopover: ViewModifier {
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(\.macPluginConsentHost) private var hostID
    @Environment(\.macPluginConsentOrigin) private var consentOrigin
    let buttonID: UUID?

    private var presentsConsent: Bool {
        guard let hostID, consent.isPresenting(for: hostID) else { return false }
        let origin = consentOrigin?.wrappedValue
        let activeButton = origin?.matches(consent.pendingReason) == true ? origin?.buttonID : nil
        return activeButton == buttonID
    }

    func body(content: Content) -> some View {
        let reason = consent.pendingReason
        let isPresenter = presentsConsent
        func presentsRequest() -> Bool {
            isPresenter && presentsConsent && reason != nil && consent.pendingReason == reason
        }
        return content.popover(isPresented: Binding(
            get: presentsRequest,
            set: { if !$0, presentsRequest() { consent.resolve(false) } }
        ), arrowEdge: .bottom) {
            MacPluginConsentPanel { approved in
                if presentsRequest() { consent.resolve(approved) }
            }
        }
    }
}

private struct MacPluginConsentPanel: View {
    @Environment(PluginInstallConsentService.self) private var consent
    let resolve: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(consent.alertTitle).font(.headline)
            Text(consent.alertMessage).font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消安装") { resolve(false) }
                Button(consent.continueButtonTitle) { resolve(true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16).frame(width: 320)
        .onExitCommand { resolve(false) }
    }
}

struct MacPluginDetail: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    let item: MacManagedPlugin
    let canOperate: Bool
    let isSuccessful: Bool
    let action: (UUID?) -> Void
    let uninstall: () -> Void
    let login: () -> Void
    @State private var features: [PlatformFeature] = []

    private var version: String { manager.installedVersion(for: item.id) ?? item.remote?.item.version ?? "未知" }
    private var phase: PluginManagementRowPhase {
        item.phase(in: manager, isSuccessful: isSuccessful)
    }
    private var needsLogin: Bool { availability.requiresLogin(for: item.id) || item.remote?.item.auth?.required == true }
    private var verifiedCurrent: Bool {
        guard item.installed, !manager.hasUpdate(for: item.id),
              manager.latestVersion(for: item.id) != nil, let source = item.sourceURL,
              case .healthy = manager.health(for: source) else { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacPluginLayout.sectionSpacing) {
                MacPluginDetailHero(
                    item: item, phase: phase, version: version,
                    verifiedCurrent: verifiedCurrent, needsLogin: needsLogin,
                    canOperate: canOperate,
                    action: action
                )
                MacPluginDetailInformation(
                    version: version, capabilityCount: features.isEmpty ? nil : features.count,
                    needsLogin: needsLogin, loggedIn: credentials.isLoggedIn(pluginId: item.id),
                    installed: item.installed, canOperate: canOperate, login: login
                )
                if !features.isEmpty { MacPluginDetailCapabilities(features: features) }
                if item.installed { MacPluginDetailRemoval(canOperate: canOperate, uninstall: uninstall) }
            }
            .padding(MacPluginLayout.pageInset)
            .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }
        .task(id: availability.catalogRevision) { features = PlatformCapability.declaredFeatures(forPluginId: item.id) ?? [] }
    }
}

struct MacPluginDetailHero: View {
    let item: MacManagedPlugin
    let phase: PluginManagementRowPhase
    let version: String
    let verifiedCurrent: Bool
    let needsLogin: Bool
    let canOperate: Bool
    let action: (UUID?) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.title2.bold()).lineLimit(1).truncationMode(.tail)
                Text(item.sourceURL == nil ? "本地插件" : "来自 \(item.host)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 10) {
                    if phase == .idle {
                        if verifiedCurrent {
                            Label("已是最新版本", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else { Text("当前版本 \(version)").foregroundStyle(.secondary) }
                    } else {
                        MacPluginActionButton(
                            item: item, phase: phase, large: true, isSelected: false,
                            canOperate: canOperate, action: action
                        )
                    }
                    if !item.installed && needsLogin {
                        Text("安装后需要登录").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.callout).padding(.top, 9)
                if case .failed(let reason) = phase {
                    MacPluginInstallationFailure(reason: reason)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MacPluginIcon(pluginID: item.id, displayName: item.name, remoteIcon: item.remote?.item.icon, size: MacPluginLayout.detailIcon)
        }
        .padding(.leading, MacPluginLayout.cardInset)
    }
}

struct MacPluginDetailInformation: View {
    let version: String
    let capabilityCount: Int?
    let needsLogin: Bool
    let loggedIn: Bool
    let installed: Bool
    let canOperate: Bool
    let login: () -> Void

    var body: some View {
        MacPluginDetailGroup(title: "信息") {
            VStack(spacing: 0) {
                MacPluginInformationRow(title: "版本", value: version)
                if let capabilityCount {
                    Divider().padding(.horizontal, MacPluginLayout.cardInset)
                    MacPluginInformationRow(title: "能力", value: "\(capabilityCount) 项")
                }
                Divider().padding(.horizontal, MacPluginLayout.cardInset)
                HStack {
                    Text("账号")
                    Spacer()
                    if needsLogin, installed, !loggedIn {
                        Button("登录…", action: login).disabled(!canOperate)
                    } else {
                        Text(needsLogin ? (loggedIn ? "已登录" : "安装后登录") : "不需要登录")
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, MacPluginLayout.cardInset).frame(minHeight: 36)
            }
        }
    }
}

struct MacPluginInformationRow: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .padding(.horizontal, MacPluginLayout.cardInset).frame(minHeight: 36)
    }
}

struct MacPluginDetailGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: MacPluginLayout.titleGap) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, MacPluginLayout.cardInset)
            content
                .modifier(MacPluginCardSurface())
        }
    }
}

private struct MacPluginCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: MacPluginLayout.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: MacPluginLayout.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

struct MacPluginDetailCapabilities: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let features: [PlatformFeature]
    var body: some View {
        MacPluginDetailGroup(title: "支持") {
            MacPluginTagFlowLayout(spacing: MacPluginLayout.tagSpacing, layoutDirection: layoutDirection) {
                ForEach(features, id: \.rawValue) { feature in
                    Text(feature.displayName).font(.caption).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(MacPluginLayout.cardInset)
        }
    }
}

private struct MacPluginTagFlowLayout: Layout {
    let spacing: CGFloat
    let layoutDirection: LayoutDirection

    private struct Placement {
        let origins: [CGPoint]
        let size: CGSize
    }

    private func placement(width: CGFloat?, subviews: Subviews) -> Placement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
        let availableWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? naturalWidth
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            contentWidth = max(contentWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return Placement(origins: origins, size: CGSize(width: contentWidth, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        placement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = placement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let origin = placement.origins[index]
            let isRightToLeft = layoutDirection == .rightToLeft
            subview.place(
                at: CGPoint(x: isRightToLeft ? bounds.maxX - origin.x : bounds.minX + origin.x,
                            y: bounds.minY + origin.y),
                anchor: isRightToLeft ? .topTrailing : .topLeading,
                proposal: .unspecified
            )
        }
    }
}

struct MacPluginDetailRemoval: View {
    let canOperate: Bool
    let uninstall: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("卸载插件")
                Text("移除插件和本地数据，5 秒内可以撤销")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: uninstall) {
                Text("卸载").foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .disabled(!canOperate)
        }
        .padding(MacPluginLayout.cardInset)
        .modifier(MacPluginCardSurface())
    }
}

struct MacPluginFailureCard: View {
    let title: LocalizedStringKey
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold).foregroundStyle(.red)
                Text(SupportDiagnosticSanitizer.text(message)).font(.callout)
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(MacPluginLayout.cardInset).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: MacPluginLayout.cornerRadius))
    }
}

struct MacPluginIcon: View {
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(\.displayScale) private var displayScale
    let pluginID: String
    let displayName: String
    let remoteIcon: String?
    let size: CGFloat
    @State private var image: CGImage?
    @State private var isLoading = true
    var body: some View {
        Group {
            if let image {
                let drawSize = PluginManagementMonogramStyle.bitmapDrawSize(
                    pixelWidth: image.width, pixelHeight: image.height,
                    targetSide: size, displayScale: displayScale
                )
                Image(decorative: image, scale: displayScale).resizable()
                    .frame(width: drawSize.width, height: drawSize.height)
                    .clipShape(RoundedRectangle(
                        cornerRadius: min(drawSize.width, drawSize.height) * PluginManagementMonogramStyle.cornerFraction,
                        style: .continuous
                    ))
            } else if isLoading {
                MacPluginLoadingIcon(size: size)
            } else {
                PluginManagementMonogram(pluginID: pluginID, displayName: displayName, size: size)
            }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
        .task(id: [pluginID, String(availability.catalogRevision), remoteIcon ?? "", String(Double(size)), String(Double(displayScale))]) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard !Task.isCancelled else { return }
        image = nil
        isLoading = true
        if let platform = LiveParseJSPlatformManager.availablePlatforms.first(where: { $0.pluginId == pluginID }),
           let local = MacPlatformIconProvider.pluginManagementImage(
               for: platform.liveType, targetSide: size, displayScale: displayScale
           ),
           let bitmap = local.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            image = bitmap
            isLoading = false
            return
        }
        guard let remoteIcon, let url = URL(string: remoteIcon), ["http", "https"].contains(url.scheme ?? "") else {
            isLoading = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                isLoading = false
                return
            }
            if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }
}

private struct MacPluginLoadingIcon: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "puzzlepiece.extension.fill").font(.system(size: size * 0.46))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: size * 0.22))
    }
}

struct MacPluginEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var actionDisabled = false
    var isFailure = false
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isFailure ? Color.red : Color.primary)
        } description: { Text(message) } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).foregroundStyle(isFailure ? Color.red : Color.accentColor).disabled(actionDisabled)
            }
        }
        .padding(MacPluginLayout.columnInset)
    }
}

struct MacPluginManagementFooter: View {
    let pendingName: String?
    let deadline: Date?
    let closeDisabled: Bool
    let undo: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if let pendingName, let deadline {
                Text("已卸载 \(pendingName)").lineLimit(1)
                Button(action: undo) {
                    HStack(spacing: 6) {
                        TimelineView(.periodic(from: .now, by: 0.1)) { context in
                            ProgressView(value: max(0, deadline.timeIntervalSince(context.date)), total: 5)
                                .progressViewStyle(.circular).controlSize(.mini).frame(width: 16, height: 16)
                        }
                        Text("撤销 ⌘Z")
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("plugins.undoUninstall")
            } else {
                ViewThatFits(in: .horizontal) {
                    Text("⇧⌘U 全部更新    ⇧⌘R 检查更新    ⌘⌫ 卸载    ⌘Z 撤销")
                    Text("右键查看插件操作")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("完成", action: close).buttonStyle(.borderedProminent).disabled(closeDisabled)
        }
        .padding(.leading, MacPluginLayout.pageInset).padding(.trailing, 20)
        .padding(.top, 12).padding(.bottom, 20)
        .accessibilityElement(children: .contain)
    }
}

struct MacPluginSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "搜索插件"
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setAccessibilityLabel("搜索插件")
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastFocusRequest != focusRequest, let window = field.window {
            context.coordinator.lastFocusRequest = focusRequest
            window.makeFirstResponder(field)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 160, height: nsView.intrinsicContentSize.height)
    }
    @MainActor final class Coordinator: NSObject {
        var text: Binding<String>
        var lastFocusRequest = 0
        init(text: Binding<String>) { self.text = text }
        @objc func searchChanged(_ field: NSSearchField) { text.wrappedValue = field.stringValue }
    }
}
