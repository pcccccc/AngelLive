import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct TVPlatformCapabilitySheet: View {
    let liveType: LiveType
    @Environment(AppState.self) private var app

    var body: some View {
        TVPlatformCapabilityContent(snapshot: currentSnapshot)
            .task { await app.pluginSourceManager.refreshAvailableUpdates() }
    }

    private var currentSnapshot: TVPlatformCapabilityContent.Snapshot {
        let manager = app.pluginSourceManager
        let id = SandboxPluginCatalog.platform(for: liveType)?.pluginId
        let installedVersion: String? = id.flatMap { manager.installedVersion(for: $0) }
        let latestVersion: String? = id.flatMap { manager.latestVersion(for: $0) }
        let changelog: [String] = id.flatMap { manager.latestRemoteItemsByPluginId[$0]?.changelog } ?? []
        let hasUpdate = id.map { manager.hasUpdate(for: $0) } ?? false
        let features: [TVPlatformCapabilityContent.Feature] = PlatformCapability.features(for: liveType).map { feature, status in
            let auth = PlatformCapability.auth(for: feature, liveType: liveType)
            return TVPlatformCapabilityContent.Feature(feature: feature, status: status,
                                                       auth: .init(level: auth.level, reason: auth.reason))
        }
        return .init(name: LiveParseTools.getLivePlatformName(liveType), installedVersion: installedVersion,
                     latestVersion: latestVersion, hasUpdate: hasUpdate, changelog: changelog, features: features)
    }
}

struct TVPlatformCapabilityContent: View {
    struct Feature: Identifiable {
        let feature: PlatformFeature
        let status: FeatureStatus
        let auth: FeatureAuthRequirement
        var id: String { feature.rawValue }
    }

    struct Snapshot {
        let name: String
        let installedVersion: String?
        let latestVersion: String?
        let hasUpdate: Bool
        let changelog: [String]
        let features: [Feature]

        var summary: String {
            let version = installedVersion.map { "当前版本 \($0)" } ?? "未安装"
            guard let latestVersion else { return "\(version) · 更新状态未知" }
            return "\(version) · " + (hasUpdate ? "可更新至 \(latestVersion)" : "最新版本 \(latestVersion)")
        }
    }

    let snapshot: Snapshot
    @Environment(\.dismiss) private var dismiss
    @FocusState private var closeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVPlayerPanelHeader(title: Text(snapshot.name), subtitle: Text(snapshot.summary)) {
                TVPlayerPanelCloseButton(isFocused: closeFocused) { dismiss() }
                    .focused($closeFocused)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if !snapshot.changelog.isEmpty {
                        sectionTitle("更新信息")
                        ForEach(snapshot.changelog.indices, id: \.self) { index in
                            TVReadableCard { Text(snapshot.changelog[index]) }
                        }
                    }
                    sectionTitle("功能支持")
                    ForEach(snapshot.features) { item in
                        TVReadableCard {
                            HStack(spacing: 20) {
                                Image(systemName: item.feature.iconName).frame(width: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 12) {
                                        Text(item.feature.displayName)
                                        if let badge = item.auth.level.badgeTitle {
                                            Text(badge).font(.system(size: 22, weight: .medium))
                                        }
                                    }
                                    if item.auth.level != .none, let reason = item.auth.reason {
                                        Text(reason).font(.system(size: 22))
                                    }
                                }
                                Spacer(minLength: 16)
                                switch item.status {
                                case .available: Label("可用", systemImage: "checkmark.circle")
                                case .unavailable: Label("不可用", systemImage: "minus.circle")
                                case .partial(let reason): Text(reason)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .clipped()
            .padding(.horizontal, -12)
        }
        .padding(32)
        .frame(maxWidth: 1120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .focusSection()
        .onAppear { closeFocused = true }
        .tvFullUIBackCommand { dismiss() }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }
}
