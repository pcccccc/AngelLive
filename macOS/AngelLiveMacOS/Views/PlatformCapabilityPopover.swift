//
//  PlatformCapabilityPopover.swift
//  AngelLiveMacOS
//
//  Created by Claude on 2026/2/25.
//

import SwiftUI
import LiveParse
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
                        HStack(spacing: 10) {
                            Image(systemName: feature.iconName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            Text(feature.displayName)
                                .font(.body)

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
    PlatformCapabilityPopover(liveType: .ks)
        .padding()
}
