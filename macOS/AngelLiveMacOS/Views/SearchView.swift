//
//  SearchView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct MacPlatformSearchView: View {
    let platform: Platformdescription
    @State private var viewModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            SearchView(platform: platform)
                .environment(viewModel)
                .macSettingsPage("在\(platform.title)中搜索")
        }
        .macSettingsSheetPresentation()
        .frame(minWidth: 640, idealWidth: 720, minHeight: 460, idealHeight: 540)
    }
}

struct SearchView: View {
    @Environment(SearchViewModel.self) private var viewModel
    @FocusState private var searchFieldFocused: Bool
    @State private var searchRequest = SearchRequestModel(
        fetchOutcome: SearchView.fetchOutcome,
        onAccepted: SearchView.recordAcceptedSearch
    )
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?
    @State private var platformSearchKind: RoomSearchKind
    private let platform: Platformdescription?
    private let platformSearchKinds: [RoomSearchKind]

    init(platform: Platformdescription? = nil) {
        let kinds = platform.map { RoomSearchKind.platformOptions(for: $0.liveType) } ?? []
        self.platform = platform
        self.platformSearchKinds = kinds
        _platformSearchKind = State(initialValue: kinds.contains(.keyword) ? .keyword : .share)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if platform == nil {
                searchContent
                    .searchable(text: $viewModel.searchText, prompt: searchPrompt)
                    .onSubmit(of: .search, performSearch)
            } else {
                searchContent
            }
        }
        .navigationTitle(platform.map { "在\($0.title)中搜索" } ?? "搜索")
        .onChange(of: viewModel.searchText) { _, newValue in
            // 当搜索框清空时，恢复到初始状态
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchRequest.clear()
            }
        }
        .onChange(of: viewModel.searchTypeIndex) { _, _ in searchRequest.clear() }
        .onChange(of: platformSearchKind) { _, _ in
            searchRequest.clear()
            viewModel.searchText = ""
        }
        .onDisappear { searchRequest.cancel() }
        .sheet(item: $authenticationRecoveryRequest) { request in
            NavigationStack {
                MacAccountManagementView(recoveryPluginIDs: request.pluginIDs)
            }
            .macSettingsSheetPresentation()
            .frame(minWidth: 600, minHeight: 480)
        }
    }

    private var searchContent: some View {
        @Bindable var viewModel = viewModel

        return GeometryReader { geometry in
            VStack(spacing: 0) {
                Group {
                    if platform == nil {
                        Picker("搜索类型", selection: $viewModel.searchTypeIndex) {
                            ForEach(viewModel.searchTypeArray.indices, id: \.self) { index in
                                Text(viewModel.searchTypeArray[index])
                                    .tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        platformSearchControls(text: $viewModel.searchText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // 搜索结果
                Group {
                    if searchRequest.isLoading && searchRequest.rooms.isEmpty {
                        searchSkeletonGrid()
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

    private func platformSearchControls(text: Binding<String>) -> some View {
        VStack(spacing: 12) {
            if platformSearchKinds.count > 1 {
                Picker("搜索类型", selection: $platformSearchKind) {
                    ForEach(platformSearchKinds, id: \.self) { kind in
                        Text(kind == .share ? "链接/口令" : "关键词")
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 8) {
                TextField(isPlatformShareSearch ? "分享链接或口令" : "主播名或直播间标题", text: text)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFieldFocused)
                    .onSubmit(performSearch)

                Button(action: performSearch) {
                    Label(isPlatformShareSearch ? "解析" : "搜索", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(searchInput.isEmpty)
            }
        }
        .onAppear { searchFieldFocused = true }
    }

    private var isPlatformShareSearch: Bool {
        platform != nil && platformSearchKind == .share
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
    private func searchEmptyState() -> some View {
        ErrorView.empty(
            title: isPlatformShareSearch ? "解析分享链接或口令" : "搜索直播间",
            message: searchEmptyMessage,
            symbolName: "magnifyingglass",
            tint: .secondary
        )
    }

    private var searchEmptyMessage: String {
        guard platform != nil else {
            return "输入链接、分享口令或房间号开始搜索，也可以使用关键词搜索主播名或标题。"
        }
        return isPlatformShareSearch
            ? "粘贴当前平台的分享链接或口令，按回车解析。"
            : "输入主播名或直播间标题，按回车搜索。"
    }

    @ViewBuilder
    private func searchNoResultsState() -> some View {
        ErrorView.empty(
            title: isPlatformShareSearch ? "未找到直播间" : "暂无搜索结果",
            message: searchNoResultsMessage,
            symbolName: "magnifyingglass",
            tint: .secondary
        )
    }

    private var searchNoResultsMessage: String {
        guard platform != nil else {
            return "换个关键词，或者改用链接、分享口令和房间号试试。"
        }
        return isPlatformShareSearch
            ? "请检查分享链接或口令是否完整。"
            : "换个关键词试试。"
    }

    private func searchResultsGrid(geometry: GeometryProxy) -> some View {
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20

        return VStack(spacing: 0) {
            if !searchRequest.authenticationRequiredPluginIDs.isEmpty {
                Button {
                    authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                        pluginIDs: searchRequest.authenticationRequiredPluginIDs
                    )
                } label: {
                    Label(
                        platform.map { "登录\($0.title)" } ?? "部分平台需要登录",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
            }

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: horizontalSpacing)
                    ],
                    spacing: verticalSpacing
                ) {
                    ForEach(searchRequest.rooms, id: \.id) { room in
                        LiveRoomCardButton(room: room) {
                            LiveRoomCard(room: room, showsCoverBadge: true)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)

                if platform != nil {
                    if searchRequest.isLoading {
                        ProgressView("加载更多…")
                            .padding(.bottom, 16)
                    } else if searchRequest.hasMore {
                        Button("加载更多", action: searchRequest.loadMore)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func searchSkeletonGrid() -> some View {
        ScrollView {
            LiveRoomSkeletonGrid(count: 12)
                .padding(.vertical, 16)
        }
        .shimmering()
    }

    @ViewBuilder
    private func searchErrorState(error: Error) -> some View {
        let title = isPlatformShareSearch ? "解析失败" : "搜索失败"
        ErrorView(
            title: error.isAuthRequired ? "\(title)-请登录相关账号并检查官方页面" : title,
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showRetry: true,
            showLoginButton: error.showsLoginAction,
            onRetry: { performSearch() },
            onLogin: error.showsLoginAction ? {
                authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                    pluginIDs: error.authRequiredPluginIDs
                )
            } : nil
        )
    }

    private var searchInput: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performSearch() {
        let input = searchInput
        guard !input.isEmpty else { return }

        let kind: RoomSearchKind
        if platform != nil {
            guard platformSearchKinds.contains(platformSearchKind) else { return }
            kind = platformSearchKind
        } else {
            kind = viewModel.searchTypeIndex == 1 ? .keyword : .share
        }

        searchRequest.submit(
            input: input,
            kind: kind,
            pluginID: platform?.pluginId
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
}

#Preview {
    SearchView()
        .environment(SearchViewModel())
}
