import SwiftUI
import AngelLiveCore

struct PluginDiscoveryShelf: View {
    let items: [ManagedPluginItem]
    let isLoading: Bool
    let hasSources: Bool
    let sourcesVerified: Bool
    let searchIsEmpty: Bool
    let canOperate: Bool
    let open: (ManagedPluginItem) -> Void
    let action: (ManagedPluginItem, UUID) -> Void
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
                            PluginDiscoveryCard(item: item, canOperate: canOperate, open: { open(item) }, action: { action(item, $0) })
                        }
                    }.fixedSize(horizontal: false, vertical: true).scrollTargetLayout()
                }.fixedSize(horizontal: false, vertical: true)
                    .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

struct PluginDiscoveryCard: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var maximumReadingWidth: CGFloat = 266
    let item: ManagedPluginItem
    let canOperate: Bool
    let open: () -> Void
    let action: (UUID) -> Void
    private var installationMetadata: String {
        let login = item.remote?.item.auth?.required == true ? "需要登录" : "不需要登录"
        guard let version = item.remote?.item.version, !version.isEmpty else { return login }
        return "\(login) · \(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    metadata(wraps: false).layoutPriority(1)
                    Spacer(minLength: PluginManagementLayout.itemSpacing)
                    PluginActionButton(item: item, canOperate: canOperate, action: action)
                }
                VStack(alignment: .leading) {
                    metadata(wraps: true)
                    PluginActionButton(item: item, canOperate: canOperate, action: action)
                }
            }
        }
        .padding(PluginManagementLayout.contentInset)
        .containerRelativeFrame(.horizontal, alignment: .leading) { availableWidth, _ in
            min(availableWidth * (dynamicTypeSize.isAccessibilitySize ? 1 : 0.70), maximumReadingWidth)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
    }

    private func metadata(wraps: Bool) -> some View {
        let reason = item.installationFailure(in: manager)
        return Text(installationMetadata).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: !wraps, vertical: wraps)
            .opacity(reason == nil ? 1 : 0).accessibilityHidden(reason != nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if let reason { PluginInstallationFailureReason(reason: reason, font: .caption) }
            }
    }
}
