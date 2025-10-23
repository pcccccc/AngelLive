//
//  FavoriteView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var viewModel
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    if viewModel.isLoading {
                        skeletonView(geometry: geometry)
                    } else if viewModel.cloudKitReady {
                        if viewModel.roomList.isEmpty {
                            emptyStateView
                        } else {
                            favoriteContentView(geometry: geometry)
                        }
                    } else {
                        cloudKitErrorView
                    }
                }
                .scrollBounceBehavior(.basedOnSize) // iOS 26: 智能弹性滚动
                .scrollIndicators(.visible, axes: .vertical) // iOS 26: 改进的滚动指示器
                .refreshable {
                    await refreshFavorites()
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadFavorites()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.slash")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))

            Text("暂无收藏")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("在其他页面添加您喜欢的直播间")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    @ViewBuilder
    private func skeletonView(geometry: GeometryProxy) -> some View {
        LazyVStack(spacing: 20) {
            // 第一个分组：正在直播（网格布局）
            skeletonLiveSection(geometry: geometry)
        }
        .padding(.top)
        .padding(.bottom, 80)  // 增加底部间距，与实际内容保持一致
        .shimmering()  // 在最外层应用一次 shimmer，提升性能
    }

    @ViewBuilder
    private func skeletonLiveSection(geometry: GeometryProxy) -> some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let columns = isIPad ? 3 : 2
        let horizontalSpacing: CGFloat = 15  // 卡片之间的水平间距
        let verticalSpacing: CGFloat = 24    // 卡片之间的垂直间距
        let horizontalPadding: CGFloat = 20  // 左右边距
        let screenWidth = geometry.size.width

        // 计算卡片宽度：(屏幕宽度 - 左边距 - 右边距 - 卡片间距) / 列数
        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)

        VStack(alignment: .leading, spacing: 12) {
            // 分组标题骨架
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 24)
                .padding(.horizontal)

            // 网格卡片骨架 - 只显示一行，减少内存占用
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                spacing: verticalSpacing
            ) {
                ForEach(0..<columns, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private func skeletonHorizontalSection(geometry: GeometryProxy) -> some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let visibleCards: CGFloat = isIPad ? 3.5 : 2.5
        let horizontalSpacing: CGFloat = 15  // 卡片之间的间距
        let horizontalPadding: CGFloat = 20  // 左右边距
        let screenWidth = geometry.size.width
        let totalSpacing = horizontalSpacing * (visibleCards - 1) + horizontalPadding
        let cardWidth = (screenWidth - totalSpacing) / visibleCards
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        VStack(alignment: .leading, spacing: 12) {
            // 分组标题骨架
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 24)
                .padding(.horizontal)

            // 横向滚动的卡片骨架 - 只显示 2 张卡片，减少动画数量
            HStack(spacing: horizontalSpacing) {
                ForEach(0..<2, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                        .frame(width: cardWidth, height: cardHeight)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var cloudKitErrorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 60))
                .foregroundStyle(.red.opacity(0.7))

            Text(viewModel.cloudKitStateString)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(action: {
                Task {
                    await loadFavorites()
                }
            }) {
                Label("重试", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.blue.gradient)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    @ViewBuilder
    private func favoriteContentView(geometry: GeometryProxy) -> some View {
        LazyVStack(spacing: 32) { // iOS 26: 增加分区间距，提升视觉层次
            ForEach(viewModel.groupedRoomList, id: \.id) { section in
                sectionView(section: section, geometry: geometry)
                    .transition(.opacity.combined(with: .move(edge: .top))) // iOS 26: 流畅的过渡动画
            }
        }
        .animation(.smooth(duration: 0.4), value: viewModel.groupedRoomList.count) // iOS 26: smooth 动画
    }

    @ViewBuilder
    private func sectionView(section: FavoriteLiveSectionModel, geometry: GeometryProxy) -> some View {
        let isLiveSection = section.title == "正在直播"
        let screenWidth = geometry.size.width
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        VStack(alignment: .leading, spacing: 16) { // iOS 26: 增加内部间距
            // 分组标题 - iOS 26 风格
            HStack(spacing: 8) {
                // 视觉指示器
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLiveSection ? Color.red.gradient : Color.blue.gradient) // iOS 26: gradient 效果
                    .frame(width: 4, height: 24)

                Text(section.title)
                    .font(.title2.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                // 房间数量标签
                Text("\(section.roomList.count)")
                    .font(.caption.monospacedDigit()) // iOS 26: 等宽数字
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.quaternary.opacity(0.5))
                    )

                Spacer()
            }
            .padding(.horizontal)

            if isLiveSection {
                // 正在直播：纵向网格布局
                liveSectionGrid(roomList: section.roomList, screenWidth: screenWidth, isIPad: isIPad)
            } else {
                // 其他分组：横向滚动布局
                horizontalScrollSection(roomList: section.roomList, screenWidth: screenWidth, isIPad: isIPad)
            }
        }
        .safeAreaPadding(.vertical, 8) // iOS 26: 使用 safeAreaPadding
    }

    // 正在直播的网格布局
    @ViewBuilder
    private func liveSectionGrid(roomList: [LiveModel], screenWidth: CGFloat, isIPad: Bool) -> some View {
        let columns = isIPad ? 3 : 2
        let horizontalSpacing: CGFloat = 15  // 卡片之间的水平间距
        let verticalSpacing: CGFloat = 24    // 卡片之间的垂直间距
        let horizontalPadding: CGFloat = 20  // 左右边距

        // 计算卡片宽度：(屏幕宽度 - 左边距 - 右边距 - 卡片间距) / 列数
        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
            spacing: verticalSpacing
        ) {
            ForEach(roomList, id: \.roomId) { room in
                LiveRoomCard(room: room)
                    .frame(width: cardWidth, height: cardHeight)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    // 其他分组的横向滚动布局
    @ViewBuilder
    private func horizontalScrollSection(roomList: [LiveModel], screenWidth: CGFloat, isIPad: Bool) -> some View {
        let visibleCards: CGFloat = isIPad ? 3.5 : 2.5
        let horizontalSpacing: CGFloat = 15  // 卡片之间的间距
        let horizontalPadding: CGFloat = 20  // 左右边距
        let totalSpacing = horizontalSpacing * (visibleCards - 1) + horizontalPadding
        let cardWidth = (screenWidth - totalSpacing) / visibleCards
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: horizontalSpacing) {
                ForEach(roomList, id: \.roomId) { room in
                    LiveRoomCard(room: room, width: cardWidth)
                        .frame(width: cardWidth, height: cardHeight)
                        .scrollTransition { content, phase in // iOS 26: 滚动过渡效果
                            content
                                .opacity(phase.isIdentity ? 1 : 0.8)
                                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                        }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .scrollTargetLayout() // iOS 26: 优化滚动目标
        }
        .scrollTargetBehavior(.viewAligned) // iOS 26: 视图对齐滚动
        .scrollBounceBehavior(.basedOnSize) // iOS 26: 智能弹性
        .frame(height: cardHeight)
    }

    private func loadFavorites() async {
        // 只有在需要同步时才同步（列表为空或超过1分钟）
        if viewModel.shouldSync() {
            await viewModel.syncWithActor()
        }
    }

    private func refreshFavorites() async {
        // 手动刷新时始终同步
        isRefreshing = true
        await viewModel.syncWithActor()
        isRefreshing = false
    }
}

#Preview {
    FavoriteView()
}
