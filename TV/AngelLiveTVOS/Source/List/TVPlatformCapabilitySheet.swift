//
//  PlatformCapabilitySheet.swift
//  AngelLiveTVOS
//
//  Created by Claude on 2026/2/25.
//

import SwiftUI
import LiveParse
import AngelLiveCore

struct TVPlatformCapabilitySheet: View {
    let liveType: LiveType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PlatformCapability.features(for: liveType), id: \.0) { feature, status in
                    HStack(spacing: 16) {
                        Image(systemName: feature.iconName)
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                            .frame(width: 40)

                        Text(feature.displayName)
                            .font(.body)

                        Spacer()

                        statusBadge(status)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(LiveParseTools.getLivePlatformName(liveType))
        }
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
    TVPlatformCapabilitySheet(liveType: .ks)
}
