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
import LiveParse

struct SearchView: View {
    @Environment(SearchViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @State private var searchResults: [LiveModel] = []
    @State private var isSearching = false
    @State private var searchError: Error?
    @State private var showBilibiliLogin = false
    @State private var hasSearched = false

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
                searchResults = []
                searchError = nil
                hasSearched = false
            }
        }
        .sheet(isPresented: $showBilibiliLogin) {
            BilibiliWebLoginView()
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
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
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
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20

        return ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 260), spacing: horizontalSpacing)
                ],
                spacing: verticalSpacing
            ) {
                ForEach(searchResults, id: \.roomId) { room in
                    LiveRoomCardButton(room: room) {
                        LiveRoomCard(room: room)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func searchSkeletonGrid(geometry: GeometryProxy) -> some View {
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width
        let columns = 3
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
            .padding(.vertical, 16)
        }
        .shimmering()
    }

    @ViewBuilder
    private func searchErrorState(error: Error) -> some View {
        ErrorView(
            title: error.isBilibiliAuthRequired ? "搜索失败-请登录B站账号并检查官方页面" : "搜索失败",
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showRetry: true,
            showLoginButton: error.isBilibiliAuthRequired,
            onRetry: { performSearch() },
            onLogin: error.isBilibiliAuthRequired ? {
                showBilibiliLogin = true
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
                        searchResults = []
                        searchError = nil
                    } else {
                        // 真正的错误才显示
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
        .environment(SearchViewModel())
}
