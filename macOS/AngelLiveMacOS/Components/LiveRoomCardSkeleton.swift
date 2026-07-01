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

/// 单个房间卡片骨架。填满所在网格单元格,轮廓与真实 `LiveRoomCard` 一致
/// (封面 16:9 + 头像/两行文字,无外层面板背景),切换到真实内容时不跳动。
/// shimmer 由外层容器统一施加,卡片自身不做,避免嵌套闪烁。
struct LiveRoomCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图骨架
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))

            // 主播信息骨架
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: 160)
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: 110)
                        .frame(height: 12)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 房间列表加载骨架网格。列宽/间距与真实列表的自适应网格完全一致,
/// 因此每行卡片数量会随窗口宽度动态变化,和加载完成后的真实列表保持同步。
struct LiveRoomSkeletonGrid: View {
    var count: Int = 12
    var minCardWidth: CGFloat = 180
    var maxCardWidth: CGFloat = 260
    var horizontalSpacing: CGFloat = 15
    var verticalSpacing: CGFloat = 24
    var horizontalPadding: CGFloat = 20

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: minCardWidth, maximum: maxCardWidth), spacing: horizontalSpacing)
            ],
            spacing: verticalSpacing
        ) {
            ForEach(0..<count, id: \.self) { _ in
                LiveRoomCardSkeleton()
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

#Preview {
    LiveRoomSkeletonGrid()
        .shimmering()
        .frame(width: 900)
}
