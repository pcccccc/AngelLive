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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchRequest = SearchRequestModel(
        fetchOutcome: SearchView.fetchOutcome,
        onAccepted: SearchView.recordAcceptedSearch
    )
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?

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
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
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
                        if searchRequest.isLoading {
                            searchSkeletonGrid(geometry: geometry)
                        } else if let searchError = searchRequest.error {
                            searchErrorState(error: searchError)
                        } else if searchRequest.rooms.isEmpty {
                            if searchRequest.hasSearched {
                                searchNoResultsState()
                            } else {
                                searchEmptyState()
                            }
                        } else {
                            searchResultsGrid(geometry: geometry)
                        }
                    }
                    .animation(.easeInOut, value: searchRequest.isLoading)
                    .animation(.easeInOut, value: searchRequest.rooms.count)
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
                    searchRequest.clear()
                }
            }
            .onChange(of: viewModel.searchTypeIndex) { _, _ in searchRequest.clear() }
            .onDisappear { searchRequest.cancel() }
            .sheet(item: $authenticationRecoveryRequest) { request in
                NavigationStack {
                    PlatformAccountLoginView(recoveryPluginIDs: request.pluginIDs)
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
        let columns = horizontalSizeClass == .regular ? 3 : 2
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width
        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)
        let cardHeight = cardWidth / AppConstants.AspectRatio.card(width: cardWidth)

        return VStack(spacing: 0) {
            if !searchRequest.authenticationRequiredPluginIDs.isEmpty {
                Button {
                    authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                        pluginIDs: searchRequest.authenticationRequiredPluginIDs
                    )
                } label: {
                    Label("部分平台需要登录", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, AppConstants.Spacing.sm)
            }

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                    spacing: verticalSpacing
                ) {
                    ForEach(searchRequest.rooms, id: \.id) { room in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func searchSkeletonGrid(geometry: GeometryProxy) -> some View {
        let columns = horizontalSizeClass == .regular ? 3 : 2
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
            message: error.isAuthRequired ? "请登录对应平台后重试" : error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showDismiss: false,
            showRetry: true,
            showLoginButton: error.isAuthRequired,
            showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
            onDismiss: nil,
            onRetry: { performSearch() },
            onLogin: error.isAuthRequired ? {
                authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                    pluginIDs: error.authRequiredPluginIDs
                )
            } : nil
        )
    }

    private func performSearch() {
        hideKeyboard()
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        searchRequest.submit(
            input: keyword,
            kind: viewModel.searchTypeIndex == 1 ? .keyword : .share
        )
    }

    @MainActor
    private static func fetchOutcome(_ request: RoomSearchRequest) async throws -> RoomSearchOutcome {
        let operationID = SupportDiagnosticsService.shared.recordAction(
            .searched,
            context: request.kind == .keyword
                ? SupportDiagnosticActionContext.search(keyword: request.input, page: request.page, additional: ["searchKind": "keyword"])
                : SupportDiagnosticActionContext.shareSearch(page: request.page)
        )
        do {
            return try await SupportDiagnosticContext.$operationID.withValue(operationID) {
                switch request.kind {
                case .keyword:
                    return try await LiveService.searchRoomsWithOutcome(keyword: request.input, page: request.page)
                case .share:
                    return try await LiveService.searchRoomWithShareCodeWithOutcome(shareCode: request.input)
                }
            }
        } catch let error as LiveParseError where error.detail.contains("返回结果为空") {
            Logger.info("搜索无结果: \(error.liveParseMessage)", category: .network)
            return RoomSearchOutcome(rooms: [])
        }
    }

    @MainActor
    private static func recordAcceptedSearch(_ request: RoomSearchRequest, _ rooms: [LiveModel]) {
        guard request.kind == .share, let room = rooms.first else { return }
        SupportDiagnosticsService.shared.recordAction(
            .searched,
            context: SupportDiagnosticActionContext.room(
                room,
                additional: ["searchKind": "share", "entryPoint": "searchResult"]
            )
        )
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    SearchView()
}
