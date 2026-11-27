//
//  PlatformCapabilitySheet.swift
//  AngelLive
//
//  Created by Claude on 2026/2/25.
//

import SwiftUI
import AngelLiveCore

struct PlatformCapabilitySheet: View {
    let liveType: LiveType
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @State private var hasRefreshedUpdates = false

    var body: some View {
        VStack(spacing: 0) {
            FullUISheetHeader(title: Text(verbatim: LiveParseTools.getLivePlatformName(liveType))) {
                dismiss()
            }
            List {
                pluginInfoSection

                if !latestChangelog.isEmpty {
                    Section("更新信息") {
                        ForEach(latestChangelog, id: \.self) { line in
                            Text("• \(line)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(PlatformCapability.features(for: liveType), id: \.0) { feature, status in
                    let auth = PlatformCapability.auth(for: feature, liveType: liveType)
                    HStack(spacing: 12) {
                        Image(systemName: feature.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(feature.displayName)
                                    .font(.body)
                                // manifest capabilities.<feature>.auth：需登录 / 登录增强
                                if let badgeTitle = auth.level.badgeTitle {
                                    RequiresLoginTag(badgeTitle)
                                }
                            }
                            if auth.level != .none, let reason = auth.reason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        statusBadge(status)
                    }
                    .padding(.vertical, 2)
                }
            }
            .task {
                guard !hasRefreshedUpdates else { return }
                hasRefreshedUpdates = true
                await pluginSourceManager.refreshAvailableUpdates()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var pluginInfoSection: some View {
        Section("插件信息") {
            infoRow(title: "当前版本", value: installedVersion ?? "未安装")

            if let latestVersion {
                HStack {
                    Text("最新版本")
                    Spacer()
                    if hasUpdate {
                        (
                            Text(installedVersion ?? "未知").foregroundStyle(.red) +
                            Text(" → ").foregroundStyle(.secondary) +
                            Text(latestVersion).foregroundStyle(.green)
                        )
                        .font(.subheadline)
                    } else {
                        Text(latestVersion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("更新状态")
                Spacer()
                if hasUpdate {
                    Text("可更新")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else if latestVersion != nil {
                    Text("已最新")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Text("未知")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var pluginId: String? {
        SandboxPluginCatalog.platform(for: liveType)?.pluginId
    }

    private var installedVersion: String? {
        guard let pluginId else { return nil }
        return pluginSourceManager.installedVersion(for: pluginId)
    }

    private var latestVersion: String? {
        guard let pluginId else { return nil }
        return pluginSourceManager.latestVersion(for: pluginId)
    }

    private var hasUpdate: Bool {
        guard let pluginId else { return false }
        return pluginSourceManager.hasUpdate(for: pluginId)
    }

    private var latestChangelog: [String] {
        guard let pluginId else { return [] }
        return pluginSourceManager.latestRemoteItemsByPluginId[pluginId]?.changelog ?? []
    }

    @ViewBuilder
    private func statusBadge(_ status: FeatureStatus) -> some View {
        switch status {
        case .available:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("可用")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        case .partial(let reason):
            HStack(spacing: 4) {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        case .unavailable:
            HStack(spacing: 4) {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("不可用")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
    }
}

struct FullUISheetHeader: View {
    let title: Text
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            title
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

#Preview {
    PlatformCapabilitySheet(liveType: .placeholder)
}
