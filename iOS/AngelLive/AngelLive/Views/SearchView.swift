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
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        
        @Bindable var viewModel = viewModel
        
        NavigationStack {
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

                // 搜索结果列表
                if searchResults.isEmpty && !isSearching {
                    searchEmptyState()
                } else if isSearching {
                    ProgressView("搜索中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    searchResultsList()
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
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                    .fill(AppConstants.Colors.materialBackground)
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func searchResultsList() -> some View {
        ScrollView {
            LazyVStack(spacing: 16) { // iOS 26: 增加间距
                ForEach(searchResults, id: \.roomId) { room in
                    SearchResultCard(room: room)
                        .transition(.opacity.combined(with: .move(edge: .top))) // iOS 26: 流畅过渡
                }
            }
            .padding()
            .animation(.smooth(duration: 0.3), value: searchResults.count) // iOS 26: smooth 动画
        }
        .scrollBounceBehavior(.basedOnSize) // iOS 26: 智能弹性滚动
        .scrollDismissesKeyboard(.interactively) // iOS 26: 交互式键盘消失
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
                        .fill(AppConstants.Colors.placeholderGradient())
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
                                .fill(AppConstants.Colors.liveStatus.gradient)
                        )
                        .padding(4)
                }
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)
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
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }

                Text(room.liveType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(AppConstants.Colors.link)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppConstants.Colors.link.opacity(0.2))
                    )
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.tertiaryText)
        }
        .padding(AppConstants.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                .fill(AppConstants.Colors.materialBackground)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.bouncy(duration: 0.3), value: isPressed) // iOS 26: bouncy 动画
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
