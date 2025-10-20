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
    @State private var viewModel = AppFavoriteModel()
    @State private var isRefreshing = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    skeletonView
                } else if viewModel.cloudKitReady {
                    if viewModel.roomList.isEmpty {
                        emptyStateView
                    } else {
                        favoriteContentView
                    }
                } else {
                    cloudKitErrorView
                }
            }
            .refreshable {
                await refreshFavorites()
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

    private var skeletonView: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 20) {
                    // 第一个分组：正在直播（网格布局）
                    skeletonLiveSection(geometry: geometry)

                    // 其他分组：横向滚动
                    ForEach(0..<2, id: \.self) { _ in
                        skeletonHorizontalSection(geometry: geometry)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    @ViewBuilder
    private func skeletonLiveSection(geometry: GeometryProxy) -> some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let columns = isIPad ? 3 : 2
        let spacing: CGFloat = 16
        let horizontalPadding: CGFloat = 16
        let screenWidth = geometry.size.width
        let totalSpacing = spacing * CGFloat(columns - 1) + horizontalPadding * 2
        let cardWidth = (screenWidth - totalSpacing) / CGFloat(columns)

        VStack(alignment: .leading, spacing: 12) {
            // 分组标题骨架
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 24)
                .padding(.horizontal)

            // 网格卡片骨架 - 只显示一行，减少内存占用
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(0..<columns, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .shimmering()  // 在整个分组上应用 shimmer，而不是每个元素
    }

    @ViewBuilder
    private func skeletonHorizontalSection(geometry: GeometryProxy) -> some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let visibleCards: CGFloat = isIPad ? 3.5 : 2.5
        let spacing: CGFloat = 16
        let horizontalPadding: CGFloat = 16
        let screenWidth = geometry.size.width
        let totalSpacing = spacing * (visibleCards - 1) + horizontalPadding
        let cardWidth = (screenWidth - totalSpacing) / visibleCards

        VStack(alignment: .leading, spacing: 12) {
            // 分组标题骨架
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 24)
                .padding(.horizontal)

            // 横向滚动的卡片骨架 - 减少卡片数量
            HStack(spacing: spacing) {
                ForEach(0..<Int(ceil(visibleCards)), id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .shimmering()  // 在整个分组上应用 shimmer，而不是每个元素
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

    private var favoriteContentView: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(viewModel.groupedRoomList, id: \.id) { section in
                        sectionView(section: section, geometry: geometry)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    @ViewBuilder
    private func sectionView(section: FavoriteLiveSectionModel, geometry: GeometryProxy) -> some View {
        let isLiveSection = section.title == "正在直播"
        let screenWidth = geometry.size.width
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        VStack(alignment: .leading, spacing: 12) {
            // 分组标题
            Text(section.title)
                .font(.title2.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)
                .padding(.horizontal)

            if isLiveSection {
                // 正在直播：纵向网格布局
                liveSectionGrid(roomList: section.roomList, screenWidth: screenWidth, isIPad: isIPad)
            } else {
                // 其他分组：横向滚动布局
                horizontalScrollSection(roomList: section.roomList, screenWidth: screenWidth, isIPad: isIPad)
            }
        }
    }

    // 正在直播的网格布局
    @ViewBuilder
    private func liveSectionGrid(roomList: [LiveModel], screenWidth: CGFloat, isIPad: Bool) -> some View {
        let columns = isIPad ? 3 : 2
        let spacing: CGFloat = 16
        let horizontalPadding: CGFloat = 16
        let totalSpacing = spacing * CGFloat(columns - 1) + horizontalPadding * 2
        let cardWidth = (screenWidth - totalSpacing) / CGFloat(columns)

        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(roomList, id: \.roomId) { room in
                LiveRoomCard(room: room, width: cardWidth)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    // 其他分组的横向滚动布局
    @ViewBuilder
    private func horizontalScrollSection(roomList: [LiveModel], screenWidth: CGFloat, isIPad: Bool) -> some View {
        let visibleCards: CGFloat = isIPad ? 3.5 : 2.5
        let spacing: CGFloat = 16
        let horizontalPadding: CGFloat = 16
        let totalSpacing = spacing * (visibleCards - 1) + horizontalPadding
        let cardWidth = (screenWidth - totalSpacing) / visibleCards

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(roomList, id: \.roomId) { room in
                    LiveRoomCard(room: room, width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private func loadFavorites() async {
        isLoading = true
        await viewModel.syncWithActor()
        isLoading = false
    }

    private func refreshFavorites() async {
        isRefreshing = true
        await viewModel.syncWithActor()
        isRefreshing = false
    }
}

#Preview {
    FavoriteView()
}
