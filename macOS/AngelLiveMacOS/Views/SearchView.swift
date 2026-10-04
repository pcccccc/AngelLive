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

struct SearchView: View {
    @Environment(SearchViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @State private var searchRequest = SearchRequestModel(
        fetchOutcome: SearchView.fetchOutcome,
        onAccepted: SearchView.recordAcceptedSearch
    )
    @State private var authenticationRecoveryRequest: AuthenticationRecoveryRequest?

    var body: some View {
        @Bindable var viewModel = viewModel

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
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // 搜索结果
                Group {
                    if searchRequest.isLoading {
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
        .navigationTitle("搜索")
        .searchable(
            text: $viewModel.searchText,
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
                MacAccountManagementView(recoveryPluginIDs: request.pluginIDs)
                    .frame(minWidth: 620, minHeight: 420)
            }
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
    private func searchEmptyState() -> some View {
        ErrorView.empty(
            title: "搜索直播间",
            message: "输入链接、分享口令或房间号开始搜索，也可以使用关键词搜索主播名或标题。",
            symbolName: "magnifyingglass",
            tint: .secondary
        )
    }

    @ViewBuilder
    private func searchNoResultsState() -> some View {
        ErrorView.empty(
            title: "暂无搜索结果",
            message: "换个关键词，或者改用链接、分享口令和房间号试试。",
            symbolName: "magnifyingglass",
            tint: .secondary
        )
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
                    Label("部分平台需要登录", systemImage: "person.crop.circle.badge.exclamationmark")
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
        ErrorView(
            title: error.isAuthRequired ? "搜索失败-请登录相关账号并检查官方页面" : "搜索失败",
            message: error.isAuthRequired ? "请登录对应平台后重试" : error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showRetry: true,
            showLoginButton: error.isAuthRequired,
            onRetry: { performSearch() },
            onLogin: error.isAuthRequired ? {
                authenticationRecoveryRequest = AuthenticationRecoveryRequest(
                    pluginIDs: error.authRequiredPluginIDs
                )
            } : nil
        )
    }

    private func performSearch() {
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
