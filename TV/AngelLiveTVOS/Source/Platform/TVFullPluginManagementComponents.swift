import SwiftUI
import AngelLiveCore

nonisolated enum TVPluginLayout {
    static let pageMargin: CGFloat = 96
    static let topMargin: CGFloat = 54
    static let sectionSpacing: CGFloat = 44
    static let headingSpacing: CGFloat = 20
    static let titleSpacing: CGFloat = 30
    static let cardSpacing: CGFloat = 44
    static let cardWidth: CGFloat = 260
    static let cardHeight: CGFloat = 160
    /// 128px artwork draws 1:1 at 2x. Smaller bitmaps stay at pixel size / scale.
    static let iconSide: CGFloat = 64
    /// Unfocused system card and bordered-row fill sampled on the 4K capture.
    static let installedSurface = Color(.sRGB, red: 25.0 / 255.0, green: 25.0 / 255.0, blue: 25.0 / 255.0, opacity: 1)
    static let brandWashOpacity: CGFloat = 0.12
    static let discoveryWidth: CGFloat = 420
    static let discoveryHeight: CGFloat = 140
    static let discoveryIconSide: CGFloat = 86
    static let cornerRadius: CGFloat = 22
    static let summaryHeight: CGFloat = 190
    static let actionContentHeight: CGFloat = 50
    static let actionSpacing: CGFloat = 24
    static let actionSymbolSide: CGFloat = 36
    static let cardStatusSymbolSide: CGFloat = 58
    static let progressLineWidth: CGFloat = 3
    static let progressStopSide: CGFloat = 12
    static let completionFeedbackDuration: Duration = .milliseconds(900)
    static let destructiveSpacing: CGFloat = 44
    static let infoSpacing: CGFloat = 14
    static let detailIcon: CGFloat = 240
    static let qrSide: CGFloat = 280
    static let focusBleed: CGFloat = 48
    // Measured system-font side bearings on the native 2x television capture.
    static let titleInkInset: CGFloat = 2
    static let headingInkInset: CGFloat = 2
    static let installedHeadingInkInset: CGFloat = 4
    static let captionBottomInset: CGFloat = 6
    static let failure = Color.red
    static let success = Color.green
    static let activity = Color.blue
}

enum TVPluginStatus {
    static func resolve(manager: PluginSourceManager, ids: [String], hasChecked: Bool) -> PluginManagementSummaryState {
        PluginManagementSummaryState.resolve(
            isRunning: manager.activeInstallationCount > 0,
            hasFailures: !manager.updateBatch.failedPluginIds.isEmpty ||
                !manager.installBatch.failedPluginIds.isEmpty ||
                manager.sourceHealth.values.contains(where: \.isFailed),
            updateCount: ids.filter { manager.hasUpdate(for: $0) }.count,
            isChecking: manager.isFetchingIndex || manager.isCheckingUpdates,
            isVerifiedCurrent: hasChecked)
    }

    static func phase(_ id: String, manager: PluginSourceManager) -> PluginManagementRowPhase {
        let action = manager.managementActionState(for: id, remote: manager.remotePlugins.first { $0.id == id })
        let isWaiting = manager.isPendingInstallation(for: id) &&
            manager.installBatch.currentPluginId != id && manager.updateBatch.currentPluginId != id
        return PluginManagementRowPhase.resolve(
            actionState: action,
            isWaiting: isWaiting,
            isSuccessful: action == .installed &&
                (manager.updateBatch.outcomes[id] == .updated || manager.installBatch.outcomes[id] == .installed))
    }

    static func failureReason(_ reason: String) -> String {
        SupportDiagnosticSanitizer.text(reason, limit: 512)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum TVPluginInstallationActivity: Equatable {
    case queued
    case preparing
    case progress(PluginInstallationProgress)

    init?(phase: PluginManagementRowPhase, manager: PluginSourceManager, pluginID: String) {
        switch phase {
        case .queued: self = .queued
        case .progress: self = manager.installationProgress(for: pluginID).map(Self.progress) ?? .preparing
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .queued: "等待中"
        case .preparing: "正在准备"
        case .progress(.downloading(let fraction)):
            if let fraction {
                "已下载 \(fraction.formatted(.percent.precision(.fractionLength(0))))"
            } else {
                "正在下载"
            }
        case .progress(.verifyingAndExtracting): "校验和解压中"
        case .progress(.activating): "正在激活"
        }
    }
}

struct TVPluginManagementHeader: View {
    let manager: PluginSourceManager
    let ids: [String]
    let hasChecked: Bool
    let focus: FocusState<TVFullPluginFocus?>.Binding
    let summaryAction: () -> Void
    let check: () -> Void
    let sources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TVPluginLayout.titleSpacing) {
            Text("插件").font(.largeTitle.bold())
                .padding(.leading, -TVPluginLayout.titleInkInset)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: TVPluginLayout.cardSpacing) {
                TVPluginSummaryCard(manager: manager, ids: ids, hasChecked: hasChecked, action: summaryAction)
                    .focused(focus, equals: .summary)
                    .frame(maxWidth: .infinity)
                VStack(spacing: TVPluginLayout.actionSpacing) {
                    TVFullOperationRow(title: manager.isFetchingIndex ? "检查中" : "检查更新",
                        symbol: "arrow.clockwise", disabled: manager.isManagementBusy, action: check)
                        .focused(focus, equals: .check)
                    TVFullOperationRow(title: "来源", symbol: "link",
                        trailing: String(manager.sourceURLs.count + PlaylistInstanceStore.shared.all().count),
                        action: sources)
                        .focused(focus, equals: .sources)
                }
                .frame(maxWidth: .infinity)
            }
            .focusSection()
        }
    }
}

private struct TVPluginSummaryCard: View {
    let manager: PluginSourceManager
    let ids: [String]
    let hasChecked: Bool
    let action: () -> Void
    private var state: PluginManagementSummaryState { TVPluginStatus.resolve(manager: manager, ids: ids, hasChecked: hasChecked) }
    private var updates: [String] { ids.filter { manager.hasUpdate(for: $0) } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 28) {
                if case .updates = state {
                    HStack(spacing: -22) {
                        ForEach(Array(updates.prefix(3)), id: \.self) { id in
                            TVPluginManagementIcon(pluginID: id, name: manager.managementDisplayName(for: id),
                                remote: manager.remotePlugins.first { $0.id == id }?.item, size: 76)
                        }
                    }
                } else {
                    Image(systemName: symbol).font(.system(size: 52, weight: .medium))
                        .foregroundStyle(color).frame(width: 76)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.title3.bold()).lineLimit(1)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 32)
            .frame(height: TVPluginLayout.summaryHeight)
        }
        .buttonStyle(.card)
        .accessibilityIdentifier("plugins.summary")
    }

    private var title: String {
        switch state {
        case .running:
            let count = manager.activeInstallationCount
            return manager.updateBatch.isRunning ? "正在更新 \(count) 个插件" : "正在安装 \(count) 个插件"
        case .failed: return "部分操作未完成"
        case .updates(let count): return "\(count) 个更新可用"
        case .checking: return "正在检查更新"
        case .current: return "全部最新"
        case .unchecked: return ids.isEmpty ? "还没有安装插件" : "检查插件更新"
        }
    }

    private var subtitle: String {
        switch state {
        case .running:
            let id = manager.updateBatch.currentPluginId ?? manager.installBatch.currentPluginId
            return id.map { manager.managementDisplayName(for: $0) } ?? "正在准备"
        case .failed: return "打开来源可查看连接状态，旧版本仍可用"
        case .updates: return updates.map { manager.managementDisplayName(for: $0) }.joined(separator: "、")
        case .checking: return "正在读取 \(manager.sourceURLs.count) 个订阅源"
        case .current: return "已安装 \(ids.count) 个插件"
        case .unchecked: return manager.sourceURLs.isEmpty ? "添加来源以发现插件" : "从发现货架选择插件"
        }
    }

    private var hint: String {
        switch state {
        case .running: "全部停止"
        case .failed: "按下重试"
        case .updates: "按下全部更新"
        case .checking: "请稍候"
        case .current, .unchecked: "按下检查更新"
        }
    }

    private var symbol: String {
        switch state {
        case .running: "arrow.down.circle"
        case .failed: "exclamationmark.triangle"
        case .checking: "arrow.clockwise"
        case .current: "checkmark.circle"
        default: "puzzlepiece.extension"
        }
    }

    private var color: Color {
        switch state {
        case .failed: TVPluginLayout.failure
        case .current: TVPluginLayout.success
        default: TVPluginLayout.activity
        }
    }
}

struct TVPluginShelf: View {
    let title: String
    let ids: [String]
    let installed: Bool
    let completingIDs: Set<String>
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let focus: FocusState<TVFullPluginFocus?>.Binding
    let open: (String, TVFullPluginFocus) -> Void
    let action: (String) -> Void
    let emptyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TVPluginLayout.headingSpacing) {
            TVFullPluginSectionHeader(title: title, count: ids.count,
                leadingInkInset: installed ? TVPluginLayout.installedHeadingInkInset : TVPluginLayout.headingInkInset)
            if ids.isEmpty {
                TVPluginEmptyState(title: installed ? "还没有安装插件" : "没有可安装的插件",
                    message: manager.sourceURLs.isEmpty ? "添加来源以获取插件。" :
                        (installed ? "从发现货架中选择插件安装。" : "可以在来源中刷新目录。"),
                    actionTitle: "管理来源", action: emptyAction)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: TVPluginLayout.cardSpacing) {
                        ForEach(ids, id: \.self) { id in
                            TVPluginShelfCard(pluginID: id, installed: installed, manager: manager,
                                availability: availability, showsCompletion: completingIDs.contains(id), focus: focus,
                                open: { open(id, .detailAction) }, action: { action(id) },
                                uninstall: { open(id, .detailUninstall) })
                        }
                    }
                    .padding(.vertical, TVPluginLayout.focusBleed / 2)
                }
                .contentMargins(.horizontal, TVPluginLayout.focusBleed / 2, for: .scrollContent)
                .padding(.horizontal, -TVPluginLayout.focusBleed / 2)
                .padding(.vertical, -TVPluginLayout.focusBleed / 2)
            }
        }
        .padding(.bottom, installed && !ids.isEmpty ? -TVPluginLayout.captionBottomInset : 0)
        .focusSection()
    }
}

private struct TVPluginShelfCard: View {
    let pluginID: String
    let installed: Bool
    let manager: PluginSourceManager
    let availability: PluginAvailabilityService
    let showsCompletion: Bool
    let focus: FocusState<TVFullPluginFocus?>.Binding
    let open: () -> Void
    let action: () -> Void
    let uninstall: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    private var phase: PluginManagementRowPhase { TVPluginStatus.phase(pluginID, manager: manager) }

    var body: some View {
        let name = manager.managementDisplayName(for: pluginID)
        let remote = manager.remotePlugins.first { $0.id == pluginID }?.item
        let phase = phase
        let activity = TVPluginInstallationActivity(phase: phase, manager: manager, pluginID: pluginID)
        let subtitle = subtitle(phase: phase, activity: activity, requiresLogin: remote?.auth?.required == true)
        Button(action: open) {
            if installed {
                TVPluginInstalledArtwork(pluginID: pluginID, name: name, remote: remote,
                    revision: availability.catalogRevision, phase: phase, activity: activity,
                    showsCompletion: showsCompletion)
                    .hoverEffect(.highlight)
                Text(name).font(.headline).lineLimit(2, reservesSpace: true)
                    .frame(width: TVPluginLayout.cardWidth, alignment: .leading)
                Text(subtitle).font(.caption).foregroundStyle(captionColor(phase)).lineLimit(1)
                    .frame(width: TVPluginLayout.cardWidth, alignment: .leading)
            } else {
                HStack(spacing: 24) {
                    TVPluginCardProgress(activity: activity, showsCompletion: showsCompletion) {
                        TVPluginManagementIcon(pluginID: pluginID, name: name, remote: remote,
                            size: TVPluginLayout.discoveryIconSide, revision: availability.catalogRevision)
                    }
                    .frame(width: TVPluginLayout.discoveryIconSide, height: TVPluginLayout.discoveryIconSide)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name).font(.headline).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(captionColor(phase)).lineLimit(1)
                            .padding(.trailing, phase.isFailure ? TVPluginLayout.actionContentHeight : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .frame(width: TVPluginLayout.discoveryWidth, height: TVPluginLayout.discoveryHeight)
                .overlay(alignment: .topTrailing) { TVPluginCardBadge(phase: phase) }
            }
        }
        .modifier(TVPluginShelfButtonStyle(installed: installed))
        .focused(focus, equals: installed ? .installed(pluginID) : .available(pluginID))
        .contextMenu {
            TVPluginContextActions(pluginID: pluginID, manager: manager,
                action: action, open: open, uninstall: uninstall)
        }
        .accessibilityIdentifier("plugins.item.\(pluginID)")
        .accessibilityLabel(name)
        .accessibilityValue(subtitle)
        .frame(width: installed ? TVPluginLayout.cardWidth : TVPluginLayout.discoveryWidth, alignment: .leading)
    }

    private func subtitle(phase: PluginManagementRowPhase, activity: TVPluginInstallationActivity?, requiresLogin: Bool) -> String {
        if let activity { return activity.title }
        switch phase {
        case .idle: return manager.installedVersion(for: pluginID) ?? "已安装"
        case .install: return requiresLogin ? "需要登录" : "不需要登录"
        case .update: return "有更新"
        case .success: return showsCompletion ? "已完成" : "已安装"
        case .failed(let reason): return TVPluginStatus.failureReason(reason)
        case .queued, .progress: return ""
        }
    }

    private func captionColor(_ phase: PluginManagementRowPhase) -> Color {
        switch phase {
        case .failed: contrast == .increased ? .primary : TVPluginLayout.failure
        case .success where showsCompletion: contrast == .increased ? .primary : TVPluginLayout.success
        default: .secondary
        }
    }
}

private extension PluginManagementRowPhase {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

private struct TVPluginShelfButtonStyle: ViewModifier {
    let installed: Bool
    func body(content: Content) -> some View {
        if installed {
            content.buttonStyle(.borderless)
        } else {
            content.buttonStyle(.card)
        }
    }
}

private struct TVPluginInstalledArtwork: View {
    let pluginID: String
    let name: String
    let remote: LiveParseRemotePluginItem?
    let revision: UInt
    let phase: PluginManagementRowPhase
    let activity: TVPluginInstallationActivity?
    let showsCompletion: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var wash: Color?
    @State private var loaded = false

    var body: some View {
        ZStack {
            TVPluginLayout.installedSurface
            if let wash {
                wash.opacity(TVPluginLayout.brandWashOpacity)
            }
            TVPluginCardProgress(activity: activity, showsCompletion: showsCompletion, onDarkArtwork: true) { icon }
        }
        .frame(width: TVPluginLayout.cardWidth, height: TVPluginLayout.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: TVPluginLayout.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) { TVPluginCardBadge(phase: phase) }
        .task(id: [pluginID, String(revision), String(Double(displayScale))]) {
            let slot = CGSize(width: TVPluginLayout.iconSide, height: TVPluginLayout.iconSide)
            let loadedImage = TVPlatformIconProvider.managementImage(
                pluginID: pluginID, targetSize: slot, displayScale: displayScale, remote: remote)
            image = loadedImage
            if let loadedImage, let brand = TVPlatformIconProvider.managementShelfColor(
                pluginID: pluginID, revision: revision, image: loadedImage) {
                wash = TVPluginBrandWash.color(brand)
            } else {
                wash = nil
            }
            loaded = true
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let bitmap = image?.cgImage {
            let draw = PluginManagementMonogramStyle.bitmapDrawSize(
                pixelWidth: bitmap.width, pixelHeight: bitmap.height,
                targetSide: TVPluginLayout.iconSide, displayScale: displayScale)
            if draw.width >= 1, draw.height >= 1 {
                let pixels = max(displayScale, 1)
                let scalesDown = CGFloat(bitmap.width) > draw.width * pixels + 0.5
                    || CGFloat(bitmap.height) > draw.height * pixels + 0.5
                Image(decorative: bitmap, scale: pixels)
                    .interpolation(scalesDown ? .high : .none)
                    .resizable()
                    .frame(width: draw.width, height: draw.height)
                    .clipShape(RoundedRectangle(
                        cornerRadius: min(draw.width, draw.height) * PluginManagementMonogramStyle.cornerFraction,
                        style: .continuous))
            } else if loaded {
                PluginManagementMonogram(pluginID: pluginID, displayName: name, size: TVPluginLayout.iconSide)
            }
        } else if loaded {
            PluginManagementMonogram(pluginID: pluginID, displayName: name, size: TVPluginLayout.iconSide)
        } else {
            ProgressView()
        }
    }
}

/// Brand tint stays at or below 0.12, and only when the icon color still clears 3:1 on the result.
private enum TVPluginBrandWash {
    static func color(_ brand: UIColor) -> Color? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard brand.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0 else { return nil }
        let amount = TVPluginLayout.brandWashOpacity
        let base: CGFloat = 25 / 255
        let mixed = (
            red: base * (1 - amount) + red * amount,
            green: base * (1 - amount) + green * amount,
            blue: base * (1 - amount) + blue * amount
        )
        guard contrast(mixed, against: (red, green, blue)) >= 3 else { return nil }
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    private static func contrast(
        _ surface: (red: CGFloat, green: CGFloat, blue: CGFloat),
        against brand: (CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        let lighter = max(luminance(surface.red, surface.green, surface.blue), luminance(brand.0, brand.1, brand.2))
        let darker = min(luminance(surface.red, surface.green, surface.blue), luminance(brand.0, brand.1, brand.2))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGFloat {
        func channel(_ value: CGFloat) -> CGFloat {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

private struct TVPluginCardProgress<Artwork: View>: View {
    let activity: TVPluginInstallationActivity?
    let showsCompletion: Bool
    var onDarkArtwork = false
    @ViewBuilder let artwork: () -> Artwork
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            artwork().opacity(activity == nil && !showsCompletion ? 1 : 0)
            if let activity {
                if activity == .queued {
                    Image(systemName: "clock")
                        .font(.system(size: TVPluginLayout.cardStatusSymbolSide))
                        .foregroundStyle(statusColor(TVPluginLayout.activity))
                        .accessibilityHidden(true)
                } else {
                    TVPluginInstallationRing(activity: activity, onDarkArtwork: onDarkArtwork)
                        .frame(width: TVPluginLayout.cardStatusSymbolSide, height: TVPluginLayout.cardStatusSymbolSide)
                }
            } else if showsCompletion {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: TVPluginLayout.cardStatusSymbolSide))
                    .foregroundStyle(statusColor(TVPluginLayout.success))
                    .accessibilityHidden(true)
            }
        }
    }

    private func statusColor(_ color: Color) -> Color {
        guard contrast == .increased || isFocused else { return color }
        return onDarkArtwork ? .white : .primary
    }
}

private struct TVPluginInstallationRing: View {
    let activity: TVPluginInstallationActivity
    var onDarkArtwork = false
    var showsStop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isFocused) private var isFocused

    private var lineWidth: CGFloat { TVPluginLayout.progressLineWidth + (contrast == .increased ? 1 : 0) }
    private var color: Color {
        guard contrast == .increased || isFocused else { return TVPluginLayout.activity }
        return onDarkArtwork ? .white : .primary
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(contrast == .increased ? 0.55 : 0.28), lineWidth: lineWidth)
            if case .progress(let progress) = activity, let fraction = progress.fractionCompleted {
                if fraction > 0 { arc(fraction).rotationEffect(.degrees(-90)) }
            } else if activity != .queued {
                if reduceMotion {
                    Circle().strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: [lineWidth]))
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                        arc(0.72).rotationEffect(.degrees(turns * 360))
                    }
                }
            }
            if showsStop {
                Image(systemName: "stop.fill").font(.system(size: TVPluginLayout.progressStopSide))
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(_ fraction: Double) -> some View {
        Circle().inset(by: lineWidth / 2).trim(from: 0, to: fraction)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

private struct TVPluginCardBadge: View {
    let phase: PluginManagementRowPhase
    var body: some View {
        Group {
            if phase == .update {
                Label("更新", systemImage: "arrow.down").font(.caption2.bold())
                    .padding(10).background(.regularMaterial, in: Capsule()).padding(12)
            } else if case .failed = phase {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                    .padding(10).background(TVPluginLayout.failure, in: Circle()).padding(12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TVPluginContextActions: View {
    let pluginID: String
    let manager: PluginSourceManager
    let action: () -> Void
    let open: () -> Void
    let uninstall: () -> Void
    var body: some View {
        let phase = TVPluginStatus.phase(pluginID, manager: manager)
        if phase == .update { Button("更新", systemImage: "arrow.down.circle", action: action) }
        if case .failed = phase { Button("重试", systemImage: "arrow.clockwise", action: action) }
        if manager.isPendingInstallation(for: pluginID) {
            Button(phase == .queued ? "取消排队" : "停止", systemImage: "stop", action: action)
        }
        if phase == .install { Button("安装", systemImage: "arrow.down.circle", action: open) }
        Button("查看详情", systemImage: "info.circle", action: open)
        if manager.installedVersion(for: pluginID) != nil {
            Button("卸载", systemImage: "trash", role: .destructive, action: uninstall)
        }
    }
}

struct TVFullOperationRow: View {
    let title: String
    let symbol: String
    var trailing: String? = nil
    var trailingColor: Color = .secondary
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: symbol).frame(width: TVPluginLayout.actionSymbolSide)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if let trailing { Text(trailing).foregroundStyle(trailingColor).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, minHeight: TVPluginLayout.actionContentHeight,
                   maxHeight: TVPluginLayout.actionContentHeight, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }
}

struct TVFullPluginSectionHeader: View {
    let title: String
    var count: Int? = nil
    var leadingInkInset: CGFloat = TVPluginLayout.headingInkInset
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title).font(.title3.bold())
            if let count { Text(count, format: .number).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.leading, -leadingInkInset)
        .accessibilityAddTraits(.isHeader)
    }
}

struct TVPluginConfirmRow: View {
    let title: String
    let symbol: String
    var confirmation: String? = nil
    var installation: TVPluginInstallationActivity? = nil
    var showsInstallationStop = false
    var destructive = false
    var disabled = false
    var cancel: () -> Void = {}
    let action: () -> Void
    @State private var deadline: Date?
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button {
            if confirmation != nil, deadline == nil {
                deadline = Date().addingTimeInterval(3)
            } else {
                deadline = nil
                action()
            }
        } label: {
            HStack(spacing: 20) {
                Group {
                    if let installation {
                        TVPluginInstallationRing(activity: installation, showsStop: showsInstallationStop)
                            .frame(height: TVPluginLayout.actionSymbolSide)
                    } else {
                        Image(systemName: symbol)
                    }
                }
                .frame(width: TVPluginLayout.actionSymbolSide)
                Text(deadline == nil ? title : confirmation ?? title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: TVPluginLayout.actionContentHeight,
                   maxHeight: TVPluginLayout.actionContentHeight, alignment: .leading)
            .overlay(alignment: .bottom) {
                if let deadline { TVPluginCountdown(deadline: deadline, duration: 3, color: .white) }
            }
        }
        .buttonStyle(.bordered)
        .tint(deadline != nil ? (destructive ? TVPluginLayout.failure : TVPluginLayout.activity) : nil)
        .foregroundStyle(deadline != nil ? .white : (destructive ? TVPluginLayout.failure : .primary))
        .disabled(disabled)
        .task(id: deadline) {
            guard let deadline else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self.deadline = nil
            cancel()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && deadline != nil { deadline = nil; cancel() }
        }
        .onDisappear { deadline = nil }
    }
}

struct TVPluginCountdown: View {
    let deadline: Date
    let duration: Double
    var color: Color = .accentColor
    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                Rectangle().fill(color)
                    .frame(width: geometry.size.width * max(0, min(1, deadline.timeIntervalSince(timeline.date) / duration)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct TVPluginEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Image(systemName: "puzzlepiece.extension").font(.title2)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(actionTitle).font(.callout).lineLimit(1)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: TVPluginLayout.discoveryHeight)
        }
        .buttonStyle(.card)
    }
}

struct TVFullDualColumnLayout<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: TVPluginLayout.pageMargin) {
                ScrollView {
                    left().frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, TVPluginLayout.focusBleed)
                }.scrollClipDisabled()
                ScrollView {
                    right().frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, TVPluginLayout.focusBleed)
                }.scrollClipDisabled()
            }
            .padding(.horizontal, TVPluginLayout.pageMargin)
            .padding(.vertical, TVPluginLayout.topMargin)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

struct TVPluginUndoNotice: View {
    let name: String
    let deadline: Date
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "playpause").font(.title3)
            VStack(alignment: .leading, spacing: 8) {
                Text("已卸载 \(name)").font(.headline).lineLimit(1)
                Text("6 秒内按播放/暂停键撤销").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: TVPluginLayout.cornerRadius))
        .overlay(alignment: .bottom) { TVPluginCountdown(deadline: deadline, duration: 6).padding(.horizontal, 24) }
        .accessibilityElement(children: .combine)
    }
}

struct TVPluginConsentSurface: View {
    let consent: PluginInstallConsentService
    @FocusState private var focusContinue: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: TVPluginLayout.actionSpacing) {
            Text(consent.alertTitle).font(.title2)
            Text(consent.alertMessage).font(.callout)
            TVPluginConfirmRow(title: consent.continueButtonTitle, symbol: "checkmark",
                confirmation: "再按一次继续", cancel: { consent.resolve(false) },
                action: { consent.resolve(true) })
                .focused($focusContinue)
            TVFullOperationRow(title: "取消", symbol: "chevron.left") { consent.resolve(false) }
        }
        .padding(TVPluginLayout.focusBleed).frame(maxWidth: 900)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TVPluginLayout.cornerRadius))
        .defaultFocus($focusContinue, true)
        .onAppear { focusContinue = true }
        .onExitCommand { consent.resolve(false) }
    }
}
