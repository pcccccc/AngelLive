import SwiftUI
import AngelLiveCore

struct PluginDiscoveryShelf: View {
    let items: [ManagedPluginItem]
    let isLoading: Bool
    let hasSources: Bool
    let sourcesVerified: Bool
    let searchIsEmpty: Bool
    let canOperate: Bool
    let canStop: Bool
    let consentHostID: UUID
    let consentAnchor: String
    let open: (ManagedPluginItem) -> Void
    let action: (ManagedPluginItem) -> Void
    let addSource: () -> Void

    var body: some View {
        VStack {
            if items.isEmpty {
                if isLoading {
                    PluginManagementEmptyState(title: "正在读取插件…", message: "正在读取来源里的插件。", isLoading: true)
                } else if !searchIsEmpty {
                    PluginManagementEmptyState(title: "没有匹配的插件", message: "请尝试其他搜索词。")
                } else if hasSources && sourcesVerified {
                    PluginManagementEmptyState(title: "来源里的插件都装好了", message: "添加其他来源以发现更多插件。")
                } else if hasSources {
                    PluginManagementEmptyState(title: "来源尚未读取成功", message: "请检查来源状态后重试。")
                } else {
                    PluginManagementEmptyState(title: "添加来源，发现更多插件", message: "添加插件来源后，可以选择需要的插件。", actionTitle: "添加来源", action: addSource)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: PluginManagementLayout.iconTextSpacing) {
                        ForEach(items) { item in
                            PluginDiscoveryCard(item: item, canOperate: canOperate, canStop: canStop, consentHostID: consentHostID, showsConsent: consentAnchor == item.id, open: { open(item) }, action: { action(item) })
                        }
                    }.fixedSize(horizontal: false, vertical: true).scrollTargetLayout()
                }.fixedSize(horizontal: false, vertical: true)
                    .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

struct PluginDiscoveryCard: View {
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var maximumReadingWidth: CGFloat = 266
    let item: ManagedPluginItem
    let canOperate: Bool
    let canStop: Bool
    let consentHostID: UUID
    let showsConsent: Bool
    let open: () -> Void
    let action: () -> Void
    private var confirming: Bool { showsConsent && consent.isPresenting(for: consentHostID) }
    private var installationMetadata: String {
        let login = item.remote?.item.auth?.required == true ? "需要登录" : "不需要登录"
        guard let version = item.remote?.item.version, !version.isEmpty else { return login }
        return "\(login) · \(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if confirming {
                PluginInstallConsentPanel(hostID: consentHostID).padding(-PluginManagementLayout.contentInset)
            } else {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 6) {
                        PluginManagementIcon(pluginID: item.pluginID, displayName: item.name, remoteIcon: item.remote?.item.icon)
                        Text(item.name).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let description = item.remote?.item.platformDescription, !description.isEmpty {
                            Text(description).font(.footnote).foregroundStyle(.secondary).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let source = item.sourceURL {
                            Text(pluginSourceHost(source)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(PluginPressButtonStyle())
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(installationMetadata).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        PluginActionButton(item: item, canOperate: canOperate, canStop: canStop, action: action)
                    }
                    VStack(alignment: .leading) {
                        Text(installationMetadata).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PluginActionButton(item: item, canOperate: canOperate, canStop: canStop, action: action)
                    }
                }
            }
        }
        .padding(PluginManagementLayout.contentInset)
        .containerRelativeFrame(.horizontal, alignment: .leading) { availableWidth, _ in
            min(availableWidth * (dynamicTypeSize.isAccessibilitySize ? 1 : 0.70), maximumReadingWidth)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: confirming)
    }
}
