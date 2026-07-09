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
        playerPresentation
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
                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: roomTransitionNamespace))
                .toolbar(.hidden, for: .tabBar)
        }
    }

    private var searchPrompt: String {
        switch viewModel.searchTypeIndex {
        case 0:
            return "输入链接、分享口令或房间号..."
        case 1:
            return "输入关键词搜索..."
        default:
            return "搜索直播间..."
        }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        @Bindable var viewModel = viewModel
        let baseView = NavigationStack {
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
        }
        if #available(iOS 18.0, *) {
            baseView
                .fullScreenCover(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        } else {
            baseView
                .navigationDestination(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        }
    }

    @ViewBuilder
    private func searchEmptyState() -> some View {
        ErrorView.empty(
            title: "搜索直播间",
            message: "支持分享链接、口令或房间号直达，也可以尝试搜索主播名和直播间标题。",
            symbolName: "magnifyingglass.circle",
            tint: .blue
        )
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
    }

    @ViewBuilder
    private func searchNoResultsState() -> some View {
        ErrorView.empty(
            title: "暂无搜索结果",
            message: "换个关键词试试，或者直接粘贴分享链接和房间号。",
            symbolName: "magnifyingglass.circle.fill",
            tint: .indigo
        )
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
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
                ForEach(searchResults, id: \.id) { room in
                    LiveRoomCard(room: room, showsCoverBadge: true)
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
            title: error.isAuthRequired ? "搜索失败-请登录相关账号并检查官方页面" : "搜索失败",
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showDismiss: false,
            showRetry: true,
            showLoginButton: error.isAuthRequired,
            showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
            onDismiss: nil,
            onRetry: { performSearch() },
            onLogin: error.isAuthRequired ? {
                NotificationCenter.default.post(name: .switchToSettings, object: nil)
            } : nil
        )
    }

    private func performSearch() {
        hideKeyboard()
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
                    // 链接/口令搜索
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
                        Logger.info("搜索无结果: \(liveParseError.liveParseMessage)", category: .network)
                        searchResults = []
                        searchError = nil
                    } else {
                        // 真正的错误才显示
                        Logger.warning("搜索错误: \(error)", category: .network)
                        searchResults = []
                        searchError = error
                    }
                    isSearching = false
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    SearchView()
}
