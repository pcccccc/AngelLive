//
//  PlatformDetailSkeletonView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 平台详情页的骨架屏视图
struct PlatformDetailSkeletonView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // 检测是否为 iPad
    private var isIPad: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        VStack(spacing: 0) {
            // 主分类导航骨架
            mainCategorySkeletonView

            // 二级分类分段控制器骨架
            subCategorySkeletonView

            // 房间列表骨架
            GeometryReader { geometry in
                roomListSkeletonView(geometry: geometry)
            }
        }
        .background(AppConstants.Colors.primaryBackground)
    }

    // MARK: - 主分类导航骨架

    private var mainCategorySkeletonView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(height: 56)
        .background(AppConstants.Colors.primaryBackground)
    }

    // MARK: - 二级分类分段控制器骨架

    private var subCategorySkeletonView: some View {
        HStack(spacing: 20) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 20)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppConstants.Colors.primaryBackground)
    }

    // MARK: - 房间列表骨架

    @ViewBuilder
    private func roomListSkeletonView(geometry: GeometryProxy) -> some View {
        let columns = isIPad ? 3 : 2
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width

        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)

        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                spacing: verticalSpacing
            ) {
                // 显示 6 个骨架卡片
                ForEach(0..<6, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppConstants.Spacing.lg)
        }
        .shimmering()  // 在最外层应用一次 shimmer
    }
}

#Preview {
    PlatformDetailSkeletonView()
}
