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
    var shimmers: Bool

    init(width: CGFloat = 280, shimmers: Bool = true) {
        self.width = max(width, 0)
        self.shimmers = shimmers
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
        .shimmering(active: shimmers)
    }
}

/// UIKit 房间列表的骨架网格。列数、卡片尺寸和间距由调用方按真实 cell 传入。
struct RoomListSkeletonGrid: View {
    let cardSize: CGSize
    let columns: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let horizontalPadding: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let columnCount = max(columns, 1)
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(cardSize.width), spacing: horizontalSpacing),
                    count: columnCount
                ),
                spacing: verticalSpacing
            ) {
                ForEach(0..<columnCount * 3, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardSize.width, shimmers: false)
                        .frame(width: cardSize.width, height: cardSize.height)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 20)
        }
        .shimmering(active: !reduceMotion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载")
    }
}

#Preview {
    LiveRoomCardSkeleton()
}
