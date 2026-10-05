//
//  PlatformCapabilitySheet.swift
//  AngelLiveTVOS
//
//  Created by Claude on 2026/2/25.
//

import SwiftUI
import AngelLiveCore

struct TVPlatformCapabilitySheet: View {
    let liveType: LiveType
    @Environment(AppState.self) private var appViewModel
    @State private var hasRefreshedUpdates = false

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 40) {
                    HStack {
                        Text(LiveParseTools.getLivePlatformName(liveType))
                            .font(.title2)
                        Spacer()
                    }
                    .padding(.horizontal, 50)
                    .padding(.top, 50)

                    pluginInfoSection

                    if !latestChangelog.isEmpty {
                        changelogSection
                    }

                    featureSection

                    Spacer(minLength: 80)
                }
            }
        }
        .task {
            guard !hasRefreshedUpdates else { return }
            hasRefreshedUpdates = true
            await appViewModel.pluginSourceManager.refreshAvailableUpdates()
        }
    }

    // MARK: - 插件信息

    private var pluginInfoSection: some View {
        VStack(spacing: 40) {
            sectionHeader("插件信息")

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
                        .font(.callout)
                    } else {
                        Text(latestVersion)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 50)
            }

            HStack {
                Text("更新状态")
                Spacer()
                if hasUpdate {
                    Text("可更新")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if latestVersion != nil {
                    Text("已最新")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Text("未知")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 50)
        }
    }

    // MARK: - 更新信息

    private var changelogSection: some View {
        VStack(spacing: 40) {
            sectionHeader("更新信息")

            VStack(alignment: .leading, spacing: 16) {
                ForEach(latestChangelog, id: \.self) { line in
                    Text("• \(line)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 50)
        }
    }

    // MARK: - 功能支持

    private var featureSection: some View {
        VStack(spacing: 40) {
            sectionHeader("功能支持")

            let features = PlatformCapability.features(for: liveType)
            ForEach(features.indices, id: \.self) { index in
                let (feature, status) = features[index]
                let auth = PlatformCapability.auth(for: feature, liveType: liveType)
                Button {} label: {
                    HStack(spacing: 16) {
                        Image(systemName: feature.iconName)
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text(feature.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                // manifest capabilities.<feature>.auth：需登录 / 登录增强
                                if let badgeTitle = auth.level.badgeTitle {
                                    RequiresLoginTag(badgeTitle, size: .regular)
                                }
                            }
                            if auth.level != .none, let reason = auth.reason {
                                Text(reason)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        statusBadge(status)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.horizontal, 50)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 50)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 50)
    }

    private var pluginId: String? {
        SandboxPluginCatalog.platform(for: liveType)?.pluginId
    }

    private var installedVersion: String? {
        guard let pluginId else { return nil }
        return appViewModel.pluginSourceManager.installedVersion(for: pluginId)
    }

    private var latestVersion: String? {
        guard let pluginId else { return nil }
        return appViewModel.pluginSourceManager.latestVersion(for: pluginId)
    }

    private var hasUpdate: Bool {
        guard let pluginId else { return false }
        return appViewModel.pluginSourceManager.hasUpdate(for: pluginId)
    }

    private var latestChangelog: [String] {
        guard let pluginId else { return [] }
        return appViewModel.pluginSourceManager.latestRemoteItemsByPluginId[pluginId]?.changelog ?? []
    }

    @ViewBuilder
    private func statusBadge(_ status: FeatureStatus) -> some View {
        switch status {
        case .available:
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
                Text("可用")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        case .partial(let reason):
            HStack(spacing: 8) {
                Circle()
                    .fill(.orange)
                    .frame(width: 12, height: 12)
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        case .unavailable:
            HStack(spacing: 8) {
                Circle()
                    .fill(.gray)
                    .frame(width: 12, height: 12)
                Text("不可用")
                    .font(.callout)
                    .foregroundStyle(.gray)
            }
        }
    }
}

#Preview {
    TVPlatformCapabilitySheet(liveType: .placeholder)
}
