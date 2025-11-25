//
//  PlatformDetailView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct PlatformDetailView: View {
    @Environment(PlatformDetailViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var dragProgress: CGFloat = 0.0  // 拖动进度

    var body: some View {
        
        @Bindable var viewModel = viewModel
        
        VStack(spacing: 0) {
            // 如果加载分类失败，显示错误视图
            if let error = viewModel.categoryError {
                ErrorView(
                    title: "加载失败",
                    message: "无法获取分类列表",
                    details: error.localizedDescription,
                    retryAction: {
                        Task {
                            await viewModel.loadCategories()
                        }
                    }
                )
            } else {
                // 一级分类导航
                if !viewModel.categories.isEmpty {
                    mainCategoryNavigator
                }

                // 二级分类分段控制器 + 可滑动的房间列表
                if !viewModel.currentSubCategories.isEmpty {
                    VStack(spacing: 0) {
                        InteractiveSegmentedControl(
                            items: viewModel.currentSubCategories.map { $0.title },
                            selectedIndex: $viewModel.selectedSubCategoryIndex,
                            dragProgress: $dragProgress
                        )

                        // 使用自定义 PageView 实现左右滑动切换
                        PageView(
                            pageCount: viewModel.currentSubCategories.count,
                            currentPage: $viewModel.selectedSubCategoryIndex,
                            dragProgress: $dragProgress
                        ) { index in
                            roomListPage(for: index)
                        }
                        .onChange(of: viewModel.selectedSubCategoryIndex) { oldValue, newValue in
                            // 切换分类时加载数据
                            Task {
                                // 检查缓存，如果没有数据则加载
                                let key = "\(viewModel.selectedMainCategoryIndex)-\(newValue)"
                                if viewModel.roomListCache[key]?.isEmpty ?? true {
                                    await viewModel.loadRoomList()
                                }
                            }
                        }
                    }
                } else {
                    // 没有子分类时显示空状态
                    emptyView()
                }
            }
        }
        .navigationTitle(viewModel.platform.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadCategories()
        }
    }

    // MARK: - 房间列表页面（用于 PageView）
    @ViewBuilder
    private func roomListPage(for index: Int) -> some View {
        let cacheKey = "\(viewModel.selectedMainCategoryIndex)-\(index)"
        let rooms = viewModel.roomListCache[cacheKey] ?? []
        let isCurrentPage = viewModel.selectedSubCategoryIndex == index

        GeometryReader { geometry in
            // 显示骨架屏的条件：
            // 1. 正在加载分类
            // 2. 或者当前页面正在加载房间且房间列表为空
            if viewModel.isLoadingCategories || (isCurrentPage && viewModel.isLoadingRooms && rooms.isEmpty) {
                loadingSkeletonView(geometry: geometry)
            } else if let error = viewModel.roomError, isCurrentPage && rooms.isEmpty {
                // 如果当前页且加载房间列表失败，显示错误视图
                ErrorView(
                    title: "加载失败",
                    message: "无法获取直播间列表",
                    details: error.localizedDescription,
                    retryAction: {
                        Task {
                            await viewModel.loadRoomList()
                        }
                    }
                )
            } else if rooms.isEmpty && !viewModel.isLoadingRooms && isCurrentPage {
                emptyView()
            } else {
                roomGridView(geometry: geometry, rooms: rooms)
            }
        }
    }

    // MARK: - 一级分类导航

    private var mainCategoryNavigator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.categories.indices, id: \.self) { index in
                    mainCategoryButton(for: index)
                }
            }
            .padding(.horizontal, AppConstants.Spacing.lg)
            .padding(.vertical, AppConstants.Spacing.md)
        }
        .background(AppConstants.Colors.primaryBackground)
    }

    @ViewBuilder
    private func mainCategoryButton(for index: Int) -> some View {
        let category = viewModel.categories[index]
        let isSelected = viewModel.selectedMainCategoryIndex == index

        Button(action: {
            Task {
                await viewModel.selectMainCategory(index: index)
            }
        }) {
            HStack(spacing: 8) {
                // 图标
                if !category.icon.isEmpty, let image = UIImage(named: category.icon) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }

                Text(category.title)
                    .font(isSelected ? .headline : .subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .foregroundStyle(isSelected ? .white : AppConstants.Colors.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? AppConstants.Colors.accent : AppConstants.Colors.secondaryBackground)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 加载骨架屏

    @ViewBuilder
    private func loadingSkeletonView(geometry: GeometryProxy) -> some View {
        let columns = AppConstants.Device.isIPad ? 3 : 2
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width

        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                spacing: verticalSpacing
            ) {
                // 显示 6 个骨架卡片
                ForEach(0..<6, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                        .frame(width: cardWidth, height: cardHeight)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppConstants.Spacing.lg)
        }
    }

    // MARK: - 加载和空状态视图

    @ViewBuilder
    private func loadingView() -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("加载中...")
                .font(.subheadline)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func emptyView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "tv.slash")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))

            Text("暂无直播间")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func roomGridView(geometry: GeometryProxy, rooms: [LiveModel]) -> some View {
        let columns = AppConstants.Device.isIPad ? 3 : 2
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width

        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                spacing: verticalSpacing
            ) {
                ForEach(rooms, id: \.roomId) { room in
                    LiveRoomCard(room: room, skipLiveCheck: true)
                        .frame(width: cardWidth, height: cardHeight)
                        .onAppear {
                            // 加载更多逻辑
                            if room.roomId == rooms.last?.roomId {
                                Task {
                                    await viewModel.loadMore()
                                }
                            }
                        }
                }

                // 加载更多指示器
                if viewModel.isLoadingRooms {
                    HStack {
                        ProgressView()
                        Text("加载更多...")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .gridCellColumns(columns)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppConstants.Spacing.lg)
        }
    }
}
