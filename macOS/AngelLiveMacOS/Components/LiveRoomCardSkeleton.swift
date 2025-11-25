//
//  LiveRoomCardSkeleton.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/22/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct LiveRoomCardSkeleton: View {
    let width: CGFloat

    init(width: CGFloat = 280) {
        self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图骨架
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // 主播信息骨架
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: min(width * 0.6, 180), height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: min(width * 0.4, 120), height: 12)
                }
                Spacer()
            }
        }
        .frame(width: width)
        .padding(AppConstants.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .fill(AppConstants.Colors.materialBackground)
                .shadow(
                    color: AppConstants.Shadow.md.color,
                    radius: AppConstants.Shadow.md.radius,
                    x: AppConstants.Shadow.md.x,
                    y: AppConstants.Shadow.md.y
                )
        )
        .shimmering()  // 只在整个卡片上应用一次 shimmer
    }
}

#Preview {
    LiveRoomCardSkeleton()
}
