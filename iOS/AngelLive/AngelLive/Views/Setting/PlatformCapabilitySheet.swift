//
//  PlatformCapabilitySheet.swift
//  AngelLive
//
//  Created by Claude on 2026/2/25.
//

import SwiftUI
import LiveParse
import AngelLiveCore

struct PlatformCapabilitySheet: View {
    let liveType: LiveType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PlatformCapability.features(for: liveType), id: \.0) { feature, status in
                    HStack(spacing: 12) {
                        Image(systemName: feature.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text(feature.displayName)
                            .font(.body)

                        Spacer()

                        statusBadge(status)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle(LiveParseTools.getLivePlatformName(liveType))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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

#Preview {
    PlatformCapabilitySheet(liveType: .huya)
}
