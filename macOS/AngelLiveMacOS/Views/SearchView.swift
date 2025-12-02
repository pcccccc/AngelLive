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
    @State private var searchError: String?

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
                        searchErrorState(message: searchError)
                    } else if searchResults.isEmpty {
                        searchEmptyState()
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
    }

    private var searchPrompt: String {
        switch viewModel.searchTypeIndex {
        case 0:
            return "输入关键词搜索..."
        case 1:
            return "输入链接、分享口令或房间号..."
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
                    Text("关键词：搜索主播名或直播间标题")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(.purple)
                    Text("链接：直接打开分享链接或房间号")
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal)
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
    private func searchErrorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("搜索失败")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                performSearch()
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func performSearch() {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        searchError = nil
        searchResults = []
        isSearching = true

        Task {
            do {
                if viewModel.searchTypeIndex == 0 {
                    let rooms = try await LiveService.searchRooms(keyword: keyword, page: 1)
                    await MainActor.run {
                        searchResults = rooms
                        isSearching = false
                    }
                } else {
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
                    searchResults = []
                    searchError = error.localizedDescription
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
