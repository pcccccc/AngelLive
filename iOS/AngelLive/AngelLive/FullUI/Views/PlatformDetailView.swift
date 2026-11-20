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
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?

    /// 根据平台类型生成登录相关的错误标题
    private func authErrorTitle(for liveType: LiveType) -> String {
        let platformName = LiveParseTools.getLivePlatformName(liveType)
        return "加载失败-请登录\(platformName)账号"
    }

    var body: some View {

        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // 如果加载分类失败，显示错误视图
            if let error = viewModel.categoryError {
                ErrorView(
                    title: error.isAuthRequired ? authErrorTitle(for: viewModel.platform.liveType) : "加载失败",
                    message: error.liveParseMessage,
                    detailMessage: error.liveParseDetail,
                    curlCommand: error.liveParseCurl,
                    showRetry: true,
                    showLoginButton: error.showsLoginAction,
                    showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
                    onRetry: {
                        Task {
                            await viewModel.loadCategories()
                        }
                    },
                    onLogin: error.showsLoginAction ? {
                        authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                            pluginIDs: SandboxPluginCatalog.platform(for: viewModel.platform.liveType)
                                .map { [$0.pluginId] } ?? []
                        )
                    } : nil
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
                        .onChange(of: viewModel.selectedSubCategoryIndex) { _, newValue in
                            Task {
                                await viewModel.activateCategory(
                                    mainCategoryIndex: viewModel.selectedMainCategoryIndex,
                                    subCategoryIndex: newValue
                                )
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
        .sheet(item: $authenticationRecoveryRequest) { request in
            NavigationStack {
                PlatformAccountLoginView(recoveryPluginIDs: request.pluginIDs)
            }
        }
    }

    // MARK: - 房间列表页面（用于 PageView）
    @ViewBuilder
    private func roomListPage(for index: Int) -> some View {
        let mainIndex = viewModel.selectedMainCategoryIndex
        let rooms = viewModel.rooms(mainCategoryIndex: mainIndex, subCategoryIndex: index)
        let phase = viewModel.roomListPhase(mainCategoryIndex: mainIndex, subCategoryIndex: index)
        let isLoading = viewModel.isLoadingRooms(mainCategoryIndex: mainIndex, subCategoryIndex: index)

        GeometryReader { geometry in
            switch phase {
            case .skeleton:
                loadingSkeletonView(geometry: geometry)
            case .failure:
                if let error = viewModel.roomError(mainCategoryIndex: mainIndex, subCategoryIndex: index) {
                    ErrorView(
                        title: error.isAuthRequired ? authErrorTitle(for: viewModel.platform.liveType) : "加载失败",
                        message: error.liveParseMessage,
                        detailMessage: error.liveParseDetail,
                        curlCommand: error.liveParseCurl,
                        showRetry: true,
                        showLoginButton: error.showsLoginAction,
                        showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
                        isRetrying: isLoading,
                        onRetry: {
                            Task {
                                await viewModel.loadRoomList(mainCategoryIndex: mainIndex, subCategoryIndex: index)
                            }
                        },
                        onLogin: error.showsLoginAction ? {
                            authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                                pluginIDs: SandboxPluginCatalog.platform(for: viewModel.platform.liveType)
                                    .map { [$0.pluginId] } ?? []
                            )
                        } : nil
                    )
                }
            case .empty:
                roomEmptyView(mainIndex: mainIndex, subIndex: index, isRetrying: isLoading)
            case .content:
                roomGridView(geometry: geometry, rooms: rooms, pageIndex: index)
            }
        }
    }

    // MARK: - 一级分类导航

    private var mainCategoryNavigator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(viewModel.categories.enumerated()), id: \.element.id) { index, _ in
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
        let columns = horizontalSizeClass == .regular ? 3 : 2
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width

        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        RoomListSkeletonGrid(
            cardSize: CGSize(width: cardWidth, height: cardHeight),
            columns: columns,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            horizontalPadding: horizontalPadding
        )
    }

    // MARK: - 空状态视图

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
    private func roomEmptyView(mainIndex: Int, subIndex: Int, isRetrying: Bool) -> some View {
        ContentUnavailableView {
            Label("暂无直播", systemImage: "video.slash")
        } description: {
            Text("换个分类看看，或稍后再试")
        } actions: {
            Button {
                guard !isRetrying else { return }
                Task {
                    await viewModel.loadRoomList(mainCategoryIndex: mainIndex, subCategoryIndex: subIndex)
                }
            } label: {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("重试")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func roomGridView(geometry: GeometryProxy, rooms: [LiveModel], pageIndex: Int) -> some View {
        let columns = horizontalSizeClass == .regular ? 3 : 2
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
                ForEach(rooms, id: \.id) { room in
                    LiveRoomCard(room: room, liveCheckMode: .none)
                        .frame(width: cardWidth, height: cardHeight)
                        .onAppear {
                            guard viewModel.selectedSubCategoryIndex == pageIndex,
                                  room.roomId == rooms.last?.roomId else { return }
                            Task {
                                await viewModel.loadMoreRooms(
                                    mainCategoryIndex: viewModel.selectedMainCategoryIndex,
                                    subCategoryIndex: pageIndex
                                )
                            }
                        }
                }

                if viewModel.isLoadingMoreRooms(
                    mainCategoryIndex: viewModel.selectedMainCategoryIndex,
                    subCategoryIndex: pageIndex
                ) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppConstants.Spacing.md)
                        .gridCellColumns(columns)
                } else if !viewModel.canLoadMoreRooms(
                    mainCategoryIndex: viewModel.selectedMainCategoryIndex,
                    subCategoryIndex: pageIndex
                ) && !rooms.isEmpty {
                    Text("已经到底了")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppConstants.Spacing.md)
                        .gridCellColumns(columns)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppConstants.Spacing.lg)
        }
    }
}
