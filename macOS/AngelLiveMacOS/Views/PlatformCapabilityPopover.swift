//
//  PlatformCapabilityPopover.swift
//  AngelLiveMacOS
//
//  Created by Claude on 2026/2/25.
//

import SwiftUI
import AngelLiveCore

struct PlatformCapabilityPopover: View {
    let liveType: LiveType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LiveParseTools.getLivePlatformName(liveType))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(PlatformCapability.features(for: liveType), id: \.0) { feature, status in
                        let auth = PlatformCapability.auth(for: feature, liveType: liveType)
                        HStack(spacing: 10) {
                            Image(systemName: feature.iconName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

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
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer()

                            statusBadge(status)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 440)
    }

    @ViewBuilder
    private func statusBadge(_ status: FeatureStatus) -> some View {
        switch status {
        case .available:
            PanelStatusBadge("可用", tint: AppConstants.Colors.success)
        case .partial(let reason):
            PanelStatusBadge(reason, tint: .orange)
        case .unavailable:
            PanelStatusBadge("不可用")
        }
    }
}

#Preview {
    PlatformCapabilityPopover(liveType: .placeholder)
        .padding()
}
