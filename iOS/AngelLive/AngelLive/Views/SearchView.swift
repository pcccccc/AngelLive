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
    @State private var viewModel = SearchViewModel()
    @State private var searchResults: [LiveModel] = []
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 搜索类型选择器
                    Picker("搜索类型", selection: $viewModel.searchTypeIndex) {
                        ForEach(viewModel.searchTypeArray.indices, id: \.self) { index in
                            Text(viewModel.searchTypeArray[index])
                                .tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .padding(.horizontal, 8)
                    )
                    .padding(.bottom, 8)

                    // 搜索结果列表
                    if searchResults.isEmpty && !isSearching {
                        searchEmptyState
                    } else if isSearching {
                        ProgressView("搜索中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(.white)
                    } else {
                        searchResultsList
                    }
                }
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

    private var searchEmptyState: some View {
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
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults, id: \.roomId) { room in
                    SearchResultCard(room: room)
                }
            }
            .padding()
        }
    }

    private func performSearch() {
        guard !viewModel.searchText.isEmpty else { return }

        isSearching = true

        // TODO: Implement actual search logic
        // Simulating search delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Mock results - replace with actual API call
            searchResults = []
            isSearching = false
        }
    }
}

// MARK: - Search Result Card Component
struct SearchResultCard: View {
    let room: LiveModel
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            // 封面图
            ZStack(alignment: .topLeading) {
                AsyncImage(url: URL(string: room.roomCover)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 直播状态
                if let liveState = room.liveState, !liveState.isEmpty {
                    Text(liveState)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.red.gradient)
                        )
                        .padding(4)
                }
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    AsyncImage(url: URL(string: room.userHeadImg)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())

                    Text(room.userName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(room.liveType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.blue.opacity(0.2))
                    )
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .onTapGesture {
            // TODO: Navigate to player view
        }
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

#Preview {
    SearchView()
}
