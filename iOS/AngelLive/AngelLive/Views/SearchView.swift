//
//  SearchView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct SearchView: View {
    @Environment(SearchViewModel.self) private var viewModel
    @State private var searchResults: [LiveModel] = []
    @State private var isSearching = false
    @State private var searchError: Error?
    @State private var hasSearched = false

    /// 共享导航状态 - 在旋转时保持稳定，避免重复请求API
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace

    var body: some View {

        @Bindable var viewModel = viewModel
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 搜索类型选择器
                    Picker("搜索类型", selection: $viewModel.searchTypeIndex) {
                        ForEach(viewModel.searchTypeArray.indices, id: \.self) { index in
                            Text(viewModel.searchTypeArray[index])
                                .tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, AppConstants.Spacing.sm)
                    .padding(.bottom, AppConstants.Spacing.md)

                    // 搜索结果
                    Group {
                        if isSearching {
                            searchSkeletonGrid(geometry: geometry)
                        } else if let searchError {
                            searchErrorState(error: searchError)
                        } else if searchResults.isEmpty {
                            if hasSearched {
                                searchNoResultsState()
                            } else {
                                searchEmptyState()
                            }
                        } else {
                            searchResultsGrid(geometry: geometry)
                        }
                    }
                    .animation(.easeInOut, value: isSearching)
                    .animation(.easeInOut, value: searchResults.count)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt
            )
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: viewModel.searchText) { _, newValue in
                // 当搜索框清空时，恢复到初始状态
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResults = []
                    searchError = nil
                    hasSearched = false
                }
            }
            .fullScreenCover(isPresented: playerPresentedBinding) {
                playerDestination
            }
        }
    }

    // MARK: - 播放器导航

    private var playerPresentedBinding: Binding<Bool> {
        Binding(
            get: { navigationState.showPlayer },
            set: { navigationState.showPlayer = $0 }
        )
    }

    @ViewBuilder
    private var playerDestination: some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                .navigationTransition(.zoom(sourceID: room.roomId, in: roomTransitionNamespace))
                .toolbar(.hidden, for: .tabBar)
        }
    }

    private var searchPrompt: String {
        switch viewModel.searchTypeIndex {
        case 0:
            return "输入链接、分享口令或房间号..."
        case 1:
            return "输入关键词搜索..."
        case 2:
            return "输入 YouTube 链接或 Video ID..."
        default:
            return "搜索直播间..."
        }
    }

    @ViewBuilder
    private func searchEmptyState() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))

            Text("搜索直播间")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(.blue)
                    Text("链接/口令：直接打开分享链接或房间号")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(.purple)
                    Text("关键词：搜索主播名或直播间标题（不推荐）")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "3.circle.fill")
                        .foregroundStyle(.red)
                    Text("YouTube：搜索 YouTube 直播")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                    .fill(AppConstants.Colors.materialBackground)
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func searchNoResultsState() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))

            Text("暂无搜索结果")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("换个关键词试试吧")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    
    private func searchResultsGrid(geometry: GeometryProxy) -> some View {
        let isIPad = AppConstants.Device.isIPad
        let columns = isIPad ? 3 : 2
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width
        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                spacing: verticalSpacing
            ) {
                ForEach(searchResults, id: \.roomId) { room in
                    LiveRoomCard(room: room)
                        .environment(\.liveRoomNavigationState, navigationState)
                        .environment(\.roomTransitionNamespace, roomTransitionNamespace)
                        .frame(width: cardWidth, height: cardHeight)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppConstants.Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func searchSkeletonGrid(geometry: GeometryProxy) -> some View {
        let isIPad = AppConstants.Device.isIPad
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
                ForEach(0..<columns * 2, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppConstants.Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func searchErrorState(error: Error) -> some View {
        ErrorView(
            title: error.isBilibiliAuthRequired ? "搜索失败-请登录B站账号并检查官方页面" : "搜索失败",
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showDismiss: false,
            showRetry: true,
            showLoginButton: error.isBilibiliAuthRequired,
            showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
            onDismiss: nil,
            onRetry: { performSearch() },
            onLogin: error.isBilibiliAuthRequired ? {
                NotificationCenter.default.post(name: .switchToSettings, object: nil)
            } : nil
        )
    }

    private func performSearch() {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        searchError = nil
        searchResults = []
        isSearching = true
        hasSearched = true

        Task {
            do {
                if viewModel.searchTypeIndex == 1 {
                    // 关键词搜索
                    let rooms = try await LiveService.searchRooms(keyword: keyword, page: 1)
                    await MainActor.run {
                        searchResults = rooms
                        isSearching = false
                    }
                } else {
                    // 链接/口令 或 YouTube 搜索
                    let room = try await LiveService.searchRoomWithShareCode(shareCode: keyword)
                    await MainActor.run {
                        if let room {
                            searchResults = [room]
                        }
                        isSearching = false
                    }
                }
            } catch {
                await MainActor.run {
                    // 检查是否是空结果错误（搜索时空结果是正常情况，不应显示错误）
                    if let liveParseError = error as? LiveParseError,
                       liveParseError.detail.contains("返回结果为空") {
                        // 空结果不是错误，只是没有搜索到内容
                        print("🔍 搜索无结果: \(liveParseError.liveParseMessage)")
                        searchResults = []
                        searchError = nil
                    } else {
                        // 真正的错误才显示
                        print("❌ 搜索错误: \(error)")
                        searchResults = []
                        searchError = error
                    }
                    isSearching = false
                }
            }
        }
    }
}

#Preview {
    SearchView()
}
