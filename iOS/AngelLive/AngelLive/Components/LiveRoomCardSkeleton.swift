//
//  LiveRoomCardSkeleton.swift
//  AngelLive
//
//  Created by pangchong on 10/20/25.
//

import SwiftUI
import AngelLiveDependencies

struct LiveRoomCardSkeleton: View {
    let width: CGFloat

    init(width: CGFloat = 280) {
        self.width = max(width, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图骨架（与 LiveRoomCard 保持一致的比例）
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))

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
        .shimmering()
    }
}

#Preview {
    LiveRoomCardSkeleton()
}
