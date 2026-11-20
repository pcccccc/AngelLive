//
//  SearchView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct PlatformRoomSearchView: View {
    let platform: Platformdescription
    @State private var viewModel = SearchViewModel()

    var body: some View {
        SearchView(platform: platform)
            .environment(viewModel)
    }

    static func availableSearchKinds(
        for platform: Platformdescription,
        pluginAvailability: PluginAvailabilityService
    ) -> [RoomSearchKind] {
        // An update can change capabilities without changing the installed plugin IDs.
        _ = pluginAvailability.catalogRevision
        let isInstalled = pluginAvailability.isPluginInstalled(for: platform.pluginId)
        let isPlaylist = PlaylistPlatformIdentity.isPlaylist(platform.liveType)
        guard isInstalled || isPlaylist else { return [] }
        return RoomSearchKind.platformOptions(for: platform.liveType)
    }
}

struct SearchView: View {
    @Environment(SearchViewModel.self) private var viewModel
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchRequest = SearchRequestModel(
        fetchOutcome: SearchView.fetchOutcome,
        onAccepted: SearchView.recordAcceptedSearch
    )
    @State private var selectedSearchPluginID: String?
    @State private var searchPlatformOptions: [LiveParseJSPlatform] = []
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?
    @State private var isSearchPresented: Bool
    @State private var platformSearchKind: RoomSearchKind = .keyword

    private let platform: Platformdescription?

    /// 共享导航状态 - 在旋转时保持稳定，避免重复请求API
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace

    init(platform: Platformdescription? = nil) {
        self.platform = platform
        _isSearchPresented = State(initialValue: platform != nil)
    }

    var body: some View {
        searchPage
            .roomPlayerZoomCover(navigationState) {
                playerDestination(.zoom)
            }
    }

    // MARK: - 播放器导航

    @ViewBuilder
    private func playerDestination(_ animation: RoomEntryAnimation) -> some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
                .roomEntryTransition(animation, sourceID: room.roomId, namespace: roomTransitionNamespace)
                .fullUITabBarHidden()
        }
    }

    private var searchTitle: String {
        guard let platform else { return String(localized: "搜索") }
        return String(localized: "在 \(platform.title) 搜索")
    }

    private var searchPrompt: String {
        if platform != nil {
            return activePlatformSearchKind == .share
                ? String(localized: "输入分享链接或口令")
                : String(localized: "搜索主播名或直播间标题")
        }

        switch viewModel.searchTypeIndex {
        case 0:
            return "输入链接、分享口令或房间号..."
        case 1:
            return "输入关键词搜索..."
        default:
            return "搜索直播间..."
        }
    }

    private var searchPlatformFeature: PlatformFeature {
        viewModel.searchTypeIndex == 1 ? .search : .shareResolve
    }

    private var searchPlatformSelection: Binding<String?> {
        Binding(
            get: { selectedSearchPluginID },
            set: { updateSelectedSearchPlatform($0) }
        )
    }

    private var selectedSearchPlatformName: String? {
        guard let selectedSearchPluginID else { return nil }
        return searchPlatformOptions.first { $0.pluginId == selectedSearchPluginID }?.displayName
            ?? selectedSearchPluginID
    }

    private var platformSearchKinds: [RoomSearchKind] {
        guard let platform else { return [] }
        return PlatformRoomSearchView.availableSearchKinds(for: platform, pluginAvailability: pluginAvailability)
    }

    private var activePlatformSearchKind: RoomSearchKind? {
        let kinds = platformSearchKinds
        return kinds.contains(platformSearchKind) ? platformSearchKind : kinds.first
    }

    private var platformSearchKindSelection: Binding<RoomSearchKind> {
        Binding(get: { platformSearchKind }, set: selectPlatformSearchKind)
    }

    @ViewBuilder
    private var searchPage: some View {
        if platform != nil {
            searchContent
        } else {
            NavigationStack {
                searchContent
                    .fullUITabBarVisibilityRoot()
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        @Bindable var viewModel = viewModel
        let content = Group {
            if platform == nil || activePlatformSearchKind != nil {
                searchLayout
                    .searchable(
                        text: $viewModel.searchText,
                        isPresented: $isSearchPresented,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: searchPrompt
                    )
                    .onSubmit(of: .search) { performSearch() }
            } else {
                ErrorView.empty(
                    title: "暂时无法搜索",
                    message: "当前平台的搜索功能不可用。",
                    symbolName: "magnifyingglass.circle",
                    tint: .blue
                )
            }
        }
        .navigationTitle(searchTitle)
        .navigationBarTitleDisplayMode(platform == nil ? .large : .inline)
        .onChange(of: viewModel.searchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchRequest.clear()
            }
        }
        .onChange(of: viewModel.searchTypeIndex) { _, _ in
            guard platform == nil else { return }
            searchRequest.clear()
            refreshSearchPlatformOptions()
        }
        .onChange(of: pluginAvailability.catalogRevision) { _, _ in
            refreshSearchPlatformOptions()
        }
        .onChange(of: platformSearchKinds, initial: true) { _, kinds in
            guard platform != nil, !kinds.contains(platformSearchKind) else { return }
            if let kind = kinds.first {
                selectPlatformSearchKind(kind)
            } else {
                resetPlatformSearch()
                isSearchPresented = false
            }
        }
        .onAppear { refreshSearchPlatformOptions() }
        .onDisappear { searchRequest.cancel() }
        .sheet(item: $authenticationRecoveryRequest) { request in
            NavigationStack {
                PlatformAccountLoginView(recoveryPluginIDs: request.pluginIDs)
            }
        }

        content.roomPlayerPushDestination(navigationState) {
            playerDestination(.push)
        }
    }

    private var searchLayout: some View {
        @Bindable var viewModel = viewModel
        return GeometryReader { geometry in
            VStack(spacing: 0) {
                if platform == nil {
                    searchTypePicker(selection: $viewModel.searchTypeIndex) {
                        ForEach(viewModel.searchTypeArray.indices, id: \.self) { index in
                            Text(viewModel.searchTypeArray[index])
                                .tag(index)
                        }
                    }
                    SearchPlatformFilter(
                        platforms: searchPlatformOptions,
                        selection: searchPlatformSelection
                    )
                } else if platformSearchKinds.count > 1 {
                    searchTypePicker(selection: platformSearchKindSelection) {
                        ForEach(platformSearchKinds, id: \.self) { kind in
                            Text(kind == .share ? "链接/口令 🔗" : "关键词 🔍")
                                .tag(kind)
                        }
                    }
                }

                Group {
                    if searchRequest.isLoading && (platform == nil || searchRequest.rooms.isEmpty) {
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
    }

    private func searchTypePicker<Selection: Hashable, Options: View>(
        selection: Binding<Selection>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        Picker("搜索类型", selection: selection, content: options)
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, AppConstants.Spacing.sm)
            .padding(.bottom, AppConstants.Spacing.md)
    }

    private var searchEmptyMessage: String {
        guard platform != nil else {
            return "支持分享链接、口令或房间号直达，也可以尝试搜索主播名和直播间标题。"
        }
        return activePlatformSearchKind == .share
            ? String(localized: "粘贴当前平台的分享链接或口令。")
            : String(localized: "输入主播名或直播间标题开始搜索。")
    }

    @ViewBuilder
    private func searchEmptyState() -> some View {
        ErrorView.empty(
            title: "搜索直播间",
            message: searchEmptyMessage,
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
            message: searchNoResultsMessage,
            symbolName: "magnifyingglass.circle.fill",
            tint: .indigo
        )
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
    }

    private var searchNoResultsMessage: String {
        if platform != nil {
            return activePlatformSearchKind == .share
                ? String(localized: "请检查分享链接或口令是否属于当前平台。")
                : String(localized: "换个主播名或直播间标题试试。")
        }

        if let selectedSearchPlatformName {
            return String(localized: "当前筛选平台：\(selectedSearchPlatformName)。换个关键词试试，或切换平台后重试。")
        }
        return String(localized: "换个关键词试试，或者直接粘贴分享链接和房间号，也可以切换平台筛选。")
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
                    Label(
                        platform == nil ? "部分平台需要登录" : "登录平台账号",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
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

                if platform != nil && searchRequest.hasMore {
                    Group {
                        if searchRequest.isLoading {
                            ProgressView()
                                .accessibilityLabel("正在加载更多直播间")
                        } else {
                            Button("加载更多") { searchRequest.loadMore() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.bottom, AppConstants.Spacing.md)
                }
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
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showDismiss: false,
            showRetry: true,
            showLoginButton: error.showsLoginAction,
            showDetailButton: error.liveParseDetail != nil && !error.liveParseDetail!.isEmpty,
            onDismiss: nil,
            onRetry: {
                if platform != nil, !searchRequest.rooms.isEmpty, searchRequest.hasMore {
                    searchRequest.loadMore()
                } else {
                    performSearch()
                }
            },
            onLogin: error.showsLoginAction ? {
                authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                    pluginIDs: error.authRequiredPluginIDs
                )
            } : nil
        )
    }

    private func performSearch() {
        let kind: RoomSearchKind
        let pluginID: String?
        if let platform {
            guard let activePlatformSearchKind else { return }
            kind = activePlatformSearchKind
            pluginID = platform.pluginId
        } else {
            kind = viewModel.searchTypeIndex == 1 ? .keyword : .share
            pluginID = selectedSearchPluginID
        }

        hideKeyboard()
        let input = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        searchRequest.submit(input: input, kind: kind, pluginID: pluginID)
    }

    private func selectPlatformSearchKind(_ kind: RoomSearchKind) {
        guard kind != platformSearchKind else { return }
        platformSearchKind = kind
        resetPlatformSearch()
    }

    private func resetPlatformSearch() {
        viewModel.searchText = ""
        searchRequest.clear()
    }

    private func updateSelectedSearchPlatform(_ pluginID: String?) {
        guard selectedSearchPluginID != pluginID else { return }
        selectedSearchPluginID = pluginID

        guard searchRequest.hasSearched,
              !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        performSearch()
    }

    private func refreshSearchPlatformOptions() {
        guard platform == nil else { return }
        searchPlatformOptions = SandboxPluginCatalog.availablePlatforms().filter {
            PlatformCapability.supports(searchPlatformFeature, for: $0.liveType)
        }

        guard let selectedSearchPluginID,
              !searchPlatformOptions.contains(where: { $0.pluginId == selectedSearchPluginID }) else {
            return
        }

        updateSelectedSearchPlatform(nil)
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
                    return try await LiveService.searchRoomsWithOutcome(
                        keyword: request.input,
                        page: request.page,
                        pluginID: request.pluginID
                    )
                case .share:
                    return try await LiveService.searchRoomWithShareCodeWithOutcome(
                        shareCode: request.input,
                        pluginID: request.pluginID
                    )
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

private struct SearchPlatformFilter: View {
    let platforms: [LiveParseJSPlatform]
    @Binding var selection: String?

    private var selectedPlatformAccessibilityValue: String {
        guard let selection else { return "全部平台" }
        return platforms.first { $0.pluginId == selection }?.displayName ?? selection
    }

    @ViewBuilder
    private var selectedPlatformLabel: some View {
        if let selection {
            Text(platforms.first { $0.pluginId == selection }?.displayName ?? selection)
        } else {
            Text("全部平台")
        }
    }

    var body: some View {
        HStack {
            Text("平台")
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Menu {
                Picker("平台", selection: $selection) {
                    Text("全部平台")
                        .tag(String?.none)

                    ForEach(platforms, id: \.pluginId) { platform in
                        Text(platform.displayName)
                            .tag(Optional(platform.pluginId))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    selectedPlatformLabel
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .frame(minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("平台")
            .accessibilityValue(selectedPlatformAccessibilityValue)
            .accessibilityHint("选择搜索平台")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

#Preview {
    SearchView()
}
