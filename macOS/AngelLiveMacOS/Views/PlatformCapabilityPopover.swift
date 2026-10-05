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
                .padding(.top, 12)
                .padding(.bottom, 8)

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
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 360)
    }

    @ViewBuilder
    private func statusBadge(_ status: FeatureStatus) -> some View {
        switch status {
        case .available:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("可用")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        case .partial(let reason):
            HStack(spacing: 4) {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        case .unavailable:
            HStack(spacing: 4) {
                Circle()
                    .fill(.gray)
                    .frame(width: 7, height: 7)
                Text("不可用")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
    }
}

#Preview {
    PlatformCapabilityPopover(liveType: .placeholder)
        .padding()
}
