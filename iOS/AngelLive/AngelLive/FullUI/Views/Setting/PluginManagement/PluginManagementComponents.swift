import SwiftUI
import UIKit
import AngelLiveCore
import Combine
import Kingfisher
import Observation

@MainActor
@Observable
final class PluginManagementFeedback {
    var recentSuccessIDs: Set<String> = []
    var recentInstallIDs: Set<String> = []
    var consentOrigin: PluginActionConsentOrigin?
    @ObservationIgnored private var rows: [String: PluginManagementRowState] = [:]

    func row(for pluginID: String, namespace: ManagedPluginItem.Namespace) -> PluginManagementRowState {
        let id = namespace.itemID(pluginID)
        if let row = rows[id] { return row }
        let row = PluginManagementRowState(
            action: namespace == .installed ? .installed : .install,
            loggedIn: PlatformCredentialSyncService.shared.isLoggedIn(pluginId: pluginID)
        )
        rows[id] = row
        return row
    }
}

struct PluginActionConsentOrigin {
    enum Surface { case row, detail }
    let buttonID: UUID
    let itemID: String
    let pluginID: String
    let surface: Surface

    func matches(_ reason: PluginInstallConsentReason?) -> Bool {
        switch reason {
        case .installingLoginPlugin(let id, _): id == pluginID
        case .installingLoginPluginsBatch(let plugins): plugins.count == 1 && plugins.first?.pluginId == pluginID
        default: false
        }
    }
}

extension EnvironmentValues {
    @Entry var pluginConsentButtonID: UUID? = nil
}

struct ManagedPluginItem: Identifiable, Equatable {
    enum Namespace: String {
        case installed, catalog

        // The catalog is already deduplicated by plugin ID. A source or
        // version change updates the card in place.
        func itemID(_ pluginID: String) -> String { "\(rawValue):\(pluginID)" }
    }
    let pluginID: String
    let name: String
    let sourceURL: String?
    let remote: RemotePluginDisplayItem?
    let namespace: Namespace
    let row: PluginManagementRowState
    var id: String { namespace.itemID(pluginID) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.sourceURL == rhs.sourceURL && lhs.remote === rhs.remote
    }
}

@MainActor
@Observable
final class PluginManagementRowState {
    struct Action: Equatable {
        var state: RemotePluginCatalogActionState
        var pending = false
        var succeeded = false
        var updateVersion: String?
        var updateFailed = false

        var failure: String? {
            guard !pending, case .failed(let reason) = state else { return nil }
            return reason
        }
    }

    struct Metadata: Equatable {
        var version = "未知"
        var isInstalled = false
        var requiresLogin = false
    }

    var action: Action
    var metadata = Metadata()
    var progress: PluginInstallationProgress?
    var loggedIn: Bool

    init(action: RemotePluginCatalogActionState, loggedIn: Bool) {
        self.action = Action(state: action)
        self.loggedIn = loggedIn
    }
}

/// Subscribes once for the page and writes only changed row values. Keep
/// metadata and progress in separate views so download ticks do not scan disk.
struct PluginManagementRowUpdates: View {
    let items: [ManagedPluginItem]

    var body: some View {
        ZStack {
            PluginManagementMetadataUpdates(items: items)
            PluginManagementProgressUpdates(items: items)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PluginManagementMetadataUpdates: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(PluginManagementFeedback.self) private var feedback
    let items: [ManagedPluginItem]

    private struct Update {
        let metadata: PluginManagementRowState.Metadata
        let action: PluginManagementRowState.Action
    }

    var body: some View {
        Color.clear
            .task(id: items) { await observeMetadata() }
            .onReceive(PlatformCredentialSyncService.shared.$loggedInByPluginId.removeDuplicates()) { statuses in
                for item in items {
                    let loggedIn = statuses[item.pluginID] ?? false
                    if item.row.loggedIn != loggedIn { item.row.loggedIn = loggedIn }
                }
            }
    }

    private func observeMetadata() async {
        while !Task.isCancelled {
            let (changes, continuation) = AsyncStream<Void>.makeStream()
            let updates = withObservationTracking {
                metadataUpdates()
            } onChange: {
                continuation.finish()
            }
            for (item, update) in zip(items, updates) {
                if item.row.metadata != update.metadata { item.row.metadata = update.metadata }
                if item.row.action != update.action { item.row.action = update.action }
            }
            // Observation's callback is leading-edge. Computing again in
            // this task reads the completed main-actor changes.
            var iterator = changes.makeAsyncIterator()
            _ = await iterator.next()
        }
    }

    private func metadataUpdates() -> [Update] {
        // Re-read installed versions after local installs and in-place updates.
        _ = availability.catalogRevision
        let successes = feedback.recentSuccessIDs
        let failedUpdates = Set(manager.updateBatch.failedPluginIds)
        return items.map { item in
            let id = item.pluginID
            let installedVersion = manager.installedVersion(for: id)
            let latest = manager.latestVersion(for: id)
            let updateVersion = latest.flatMap { candidate in
                installedVersion.flatMap { semverCompare(candidate, $0) > 0 ? candidate : nil }
            }
            return Update(
                metadata: .init(version: installedVersion ?? item.remote?.item.version ?? "未知",
                                isInstalled: installedVersion != nil,
                                requiresLogin: availability.requiresLogin(for: id)),
                action: .init(state: manager.managementActionState(for: id, remote: item.remote),
                              pending: manager.isPendingInstallation(for: id),
                              succeeded: successes.contains(id),
                              updateVersion: updateVersion, updateFailed: failedUpdates.contains(id))
            )
        }
    }
}

private struct PluginManagementProgressUpdates: View {
    @Environment(PluginSourceManager.self) private var manager
    let items: [ManagedPluginItem]

    private struct Update: Equatable {
        let id: String
        let progress: PluginInstallationProgress?
    }

    var body: some View {
        let updates = items.map { Update(id: $0.id, progress: manager.installationProgress(for: $0.pluginID)) }
        Color.clear.onChange(of: updates, initial: true) { _, updates in
            for (item, update) in zip(items, updates) where item.row.progress != update.progress {
                item.row.progress = update.progress
            }
        }
    }
}

struct PluginInstallationFailureReason: View {
    let reason: String
    var font: Font = .footnote

    var body: some View {
        let message = SupportDiagnosticSanitizer.text(reason, limit: 512)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        (message.isEmpty ? Text("操作失败，请重试") : Text(message))
            .font(font).foregroundStyle(.secondary).lineLimit(1)
    }
}

struct PluginManagementSectionHeading: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    var subtitle: LocalizedStringKey? = nil
    var subtitleCount: Int? = nil
    var actionTitle: LocalizedStringKey? = nil
    var actionDisabled = false
    var action: (() -> Void)? = nil
    var includesSectionSpacing = false
    private var hasAccessory: Bool { subtitle != nil || subtitleCount != nil || (actionTitle != nil && action != nil) }
    private var accessory: some View {
        PluginManagementHeadingAccessory(subtitle: subtitle, subtitleCount: subtitleCount,
                                          actionTitle: actionTitle, disabled: actionDisabled, action: action)
    }
    var body: some View {
        let metrics = PluginManagementTextMetrics(text: title, style: .sectionTitle, locale: locale, dynamicTypeSize: dynamicTypeSize)
        ViewThatFits(in: .horizontal) {
            PluginManagementHeadingGap(inkAscent: metrics.inkBounds.maxY, sectionSpacing: PluginManagementLayout.sectionSpacing, includesSectionSpacing: includesSectionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    PluginManagementEdgeText(text: title, style: .sectionTitle).foregroundStyle(PluginManagementLayout.primaryText)
                    Spacer(minLength: PluginManagementLayout.itemSpacing)
                    if hasAccessory {
                        accessory
                    }
                }
            }
            PluginManagementHeadingGap(inkAscent: metrics.inkBounds.maxY, sectionSpacing: PluginManagementLayout.sectionSpacing, includesSectionSpacing: includesSectionSpacing) {
                VStack(alignment: .leading, spacing: PluginManagementLayout.itemSpacing) {
                    PluginManagementEdgeText(text: title, style: .sectionTitle).foregroundStyle(PluginManagementLayout.primaryText)
                    if hasAccessory {
                        accessory
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .frame(minHeight: includesSectionSpacing ? nil : PluginManagementLayout.minimumTarget, alignment: .bottom)
        .textCase(nil)
        .padding(.bottom, PluginManagementLayout.headerToCard)
        .listRowInsets(PluginManagementLayout.zeroInsets)
    }
}

private struct PluginManagementHeadingAccessory: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let subtitle: LocalizedStringKey?
    let subtitleCount: Int?
    let actionTitle: LocalizedStringKey?
    let disabled: Bool
    let action: (() -> Void)?
    var body: some View {
        Group {
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(minHeight: PluginManagementLayout.minimumTarget, alignment: .bottom)
                        .contentShape(Rectangle())
                }.disabled(disabled)
                    .accessibilityIdentifier("plugins.installAll")
            } else if let subtitleCount {
                Text("\(subtitleCount) 个").foregroundStyle(PluginManagementLayout.secondaryText)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: subtitleCount)
            } else if let subtitle {
                Text(subtitle).foregroundStyle(PluginManagementLayout.secondaryText)
            }
        }.font(.subheadline).tint(PluginManagementLayout.primaryAction)
    }
}

struct PluginManagementToolIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.body).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct PluginManagementIcon: View {
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(\.displayScale) private var displayScale
    let pluginID: String
    let displayName: String
    var remoteIcon: String? = nil
    var size: CGFloat = PluginManagementLayout.iconSize
    @State private var localIcon: LocalIcon?
    @State private var failedRemoteIcon: URL?

    private final class LocalIcon {
        let image: UIImage?

        init(_ image: UIImage?) { self.image = image }
    }

    private static let localCache: NSCache<NSString, LocalIcon> = {
        let cache = NSCache<NSString, LocalIcon>()
        cache.countLimit = 128
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    private var localCacheKey: String {
        "\(availability.catalogRevision):\(size):\(displayScale):\(pluginID)"
    }

    private var remoteURL: URL? {
        guard let remoteIcon, let url = URL(string: remoteIcon),
              ["http", "https"].contains(url.scheme ?? "") else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            if let image = localIcon?.image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: size, height: size)
            } else if localIcon == nil {
                placeholder
            } else if let remoteURL {
                KFImage(remoteURL)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: size, height: size)))
                    .scaleFactor(displayScale)
                    .cacheMemoryOnly()
                    .cancelOnDisappear(true)
                    .placeholder {
                        if failedRemoteIcon == remoteURL { monogram } else { placeholder }
                    }
                    .onFailure { error in
                        if !error.isTaskCancelled { failedRemoteIcon = remoteURL }
                    }
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * PluginManagementLayout.iconRadius / PluginManagementLayout.iconSize, style: .continuous))
        .accessibilityHidden(true)
        .task(id: localCacheKey) {
            guard !Task.isCancelled else { return }
            let key = localCacheKey as NSString
            if let cached = Self.localCache.object(forKey: key) {
                localIcon = cached
                return
            }
            let platform = LiveParseJSPlatformManager.availablePlatforms.first { $0.pluginId == pluginID }
            let image = platform.flatMap {
                PlatformIconProvider.pluginManagementImage(for: $0.liveType, targetSide: size, displayScale: displayScale)
            }
            let bitmap = image?.cgImage
            let local = LocalIcon(bitmap == nil ? nil : image)
            let cost = bitmap.map { $0.bytesPerRow * $0.height } ?? 0
            Self.localCache.setObject(local, forKey: key, cost: cost)
            localIcon = local
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * PluginManagementLayout.iconRadius / PluginManagementLayout.iconSize, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.45))
            Image(systemName: "puzzlepiece.extension.fill").resizable().scaledToFit()
                .foregroundStyle(PluginManagementLayout.secondaryText).padding(size * 0.22)
        }
    }

    private var monogram: some View {
        PluginManagementMonogram(pluginID: pluginID, displayName: displayName, size: size)
    }
}

extension View {
    func pluginInstallConsentAlert(
        _ consent: PluginInstallConsentService,
        isActive: @escaping @MainActor () -> Bool
    ) -> some View {
        let reason = consent.pendingReason
        let isSelectedPresenter = isActive()
        func presentsRequest() -> Bool {
            isActive() && consent.isPresenting && reason != nil && consent.pendingReason == reason
        }
        return alert(consent.alertTitle, isPresented: Binding(
            get: { isSelectedPresenter && presentsRequest() },
            set: { if !$0, presentsRequest() { consent.resolve(false) } }
        )) {
            Button(consent.continueButtonTitle) { if presentsRequest() { consent.resolve(true) } }
            Button(consent.cancelButtonTitle, role: .cancel) { if presentsRequest() { consent.resolve(false) } }
        } message: {
            Text(consent.alertMessage)
        }
    }
}

struct PluginManagementEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringResource
    var isLoading = false
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: PluginManagementLayout.itemSpacing) {
            if isLoading { ProgressView().accessibilityHidden(true) }
            Text(title).font(.headline).foregroundStyle(PluginManagementLayout.primaryText)
            Text(message).font(.subheadline).foregroundStyle(PluginManagementLayout.secondaryText)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.large)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        .padding(.horizontal, PluginManagementLayout.contentInset)
        .padding(.vertical, PluginManagementLayout.detailSpacing)
        .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
        .tint(PluginManagementLayout.primaryAction)
    }
}

struct PluginUninstallUndoBar: View {
    let name: String
    let deadline: Date?
    let undo: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("已卸载 \(name)").font(.subheadline).lineLimit(2)
            Spacer(minLength: 0)
            Button(action: undo) {
                HStack(spacing: 8) {
                    if let deadline {
                        ProgressView(timerInterval: deadline.addingTimeInterval(-5)...deadline, countsDown: true) { EmptyView() }
                            .progressViewStyle(.circular).labelsHidden().frame(width: 18, height: 18)
                    }
                    Text("撤销").font(.subheadline.weight(.semibold))
                }.frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("撤销卸载 \(name)")
        }.padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .contain)
    }
}

func pluginSourceHost(_ url: String) -> String { URL(string: url)?.host() ?? url }

struct FullUIPluginSourceErrorCard: View {
    let title: LocalizedStringKey
    let message: String
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(SupportDiagnosticSanitizer.text(message)).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
    }
}

struct PluginSourceHealthLabel: View {
    let health: PluginSourceHealth
    var body: some View {
        HStack(spacing: 5) {
            if case .checking = health { ProgressView().controlSize(.mini) }
            else { Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true) }
            Text(title).foregroundStyle(.secondary)
        }.font(.footnote).accessibilityElement(children: .combine)
    }
    private var title: LocalizedStringResource {
        switch health {
        case .unknown: "尚未检查"
        case .checking: "正在检查…"
        case .healthy(let count): "正常 · \(count) 个插件"
        case .failed: "来源异常"
        }
    }
    private var symbol: String {
        switch health {
        case .healthy: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        default: "questionmark.circle"
        }
    }
    private var color: Color { if case .healthy = health { .green } else if case .failed = health { .orange } else { .secondary } }
}
