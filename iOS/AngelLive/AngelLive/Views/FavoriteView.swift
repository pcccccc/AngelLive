//
//  FavoriteView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct FavoriteView: View {
    @State private var viewModel = AppFavoriteModel()
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.cloudKitReady {
                    if viewModel.roomList.isEmpty {
                        emptyStateView
                    } else {
                        favoriteContentView
                    }
                } else {
                    cloudKitErrorView
                }
            }
            .refreshable {
                await refreshFavorites()
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadFavorites()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.slash")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))

            Text("暂无收藏")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("在其他页面添加您喜欢的直播间")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var cloudKitErrorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 60))
                .foregroundStyle(.red.opacity(0.7))

            Text(viewModel.cloudKitStateString)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(action: {
                Task {
                    await loadFavorites()
                }
            }) {
                Label("重试", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.blue.gradient)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var favoriteContentView: some View {
        LazyVStack(spacing: 20) {
            ForEach(viewModel.groupedRoomList, id: \.id) { section in
                VStack(alignment: .leading, spacing: 12) {
                    // 分组标题
                    Text(section.title)
                        .font(.title2.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .padding(.horizontal)

                    // 横向滚动的直播间卡片
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(section.roomList, id: \.roomId) { room in
                                LiveRoomCard(room: room)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.vertical)
    }

    private func loadFavorites() async {
        await viewModel.syncWithActor()
    }

    private func refreshFavorites() async {
        isRefreshing = true
        await viewModel.syncWithActor()
        isRefreshing = false
    }
}

// MARK: - Live Room Card Component
struct LiveRoomCard: View {
    let room: LiveModel
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: room.roomCover)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(AppConstants.Colors.placeholderGradient())
                }
                .frame(width: 280, height: 157)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // 直播状态标签
                if let liveState = room.liveState, !liveState.isEmpty {
                    Text(liveState)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(AppConstants.Colors.liveStatus.gradient)
                        )
                        .padding(8)
                }
            }

            // 主播信息
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: room.userHeadImg)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    Text(room.userName)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: 280)
        }
        .frame(width: 280)
        .padding(AppConstants.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .fill(AppConstants.Colors.materialBackground)
                .shadow(
                    color: AppConstants.Shadow.md.color,
                    radius: AppConstants.Shadow.md.radius,
                    x: AppConstants.Shadow.md.x,
                    y: AppConstants.Shadow.md.y
                )
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
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
    FavoriteView()
}
