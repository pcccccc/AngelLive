//
//  StreamerInfoView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies


/// 主播信息视图
struct StreamerInfoView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.presentToast) private var presentToast
    @State private var isFavoriteAnimating = false
    @State private var showStreamerInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { room in
            if !viewModel.currentRoom.userId.isEmpty, !room.userId.isEmpty {
                return room.liveType == viewModel.currentRoom.liveType && room.userId == viewModel.currentRoom.userId
            }
            return room.liveType == viewModel.currentRoom.liveType && room.roomId == viewModel.currentRoom.roomId
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TranslatedRoomTitle(viewModel.currentRoom.roomTitle.trimmingCharacters(in: .whitespacesAndNewlines).orDash)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            // 主播信息行
            HStack(spacing: 8) {
                // 主播头像（可点击）
                Button {
                    showStreamerInfo = true
                } label: {
                    Group {
                        if !viewModel.currentRoom.userHeadImg.isEmpty,
                           let avatarURL = URL(string: viewModel.currentRoom.userHeadImg) {
                            KFAnimatedImage(avatarURL)
                                .configure { view in
                                    view.framePreloadCount = 2
                                }
                                .placeholder {
                                    avatarFallback
                                }
                                .aspectRatio(contentMode: .fill)
                        } else {
                            avatarFallback
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("主播详情")
                .padding(.trailing, -4)

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.currentRoom.userName.orDash)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    FullUIRoomPopularity(count: viewModel.currentRoom.liveWatchedCount)
                }

                Spacer(minLength: 0)

                if let status = viewModel.danmakuConnectionStatus {
                    Label(status.title, systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.opacity)
                }

                Button {
                    Task {
                        await toggleFavorite()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if !isFavorited {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isFavorited ? "已关注" : "关注")
                    }
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 76, minHeight: FullUIPlayerDetailChrome.pillHeight)
                    .foregroundStyle(isFavorited ? Color.primary : Color.white)
                    .background(
                        isFavorited ? FullUIPlayerDetailChrome.pillFill : FullUIPlayerDetailChrome.accent,
                        in: Capsule()
                    )
                    .frame(minHeight: FullUIPlayerChrome.controlSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorited ? "已关注" : "关注")
                .accessibilityHint(isFavorited ? "取消关注主播" : "关注主播")
                .changeEffect(
                    .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                        Image(systemName: isFavorited ? "heart.fill" : "heart.slash.fill")
                            .foregroundStyle(.red)
                    }, value: isFavoriteAnimating
                )
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: viewModel.danmakuConnectionStatus
            )
        }
        .padding(.horizontal, FullUIPlayerDetailChrome.inset)
        .padding(.top, FullUIPlayerDetailChrome.inset)
        .roomPlayerSheet(isPresented: $showStreamerInfo) {
            StreamerInfoSheet(room: viewModel.currentRoom)
        }
    }

    /// 头像兜底（URL 为空 / 加载失败）
    private var avatarFallback: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(6)
            )
    }

    // MARK: - 收藏操作

    @MainActor
    private func toggleFavorite() async {
        let wasFavorited = isFavorited
        do {
            if wasFavorited {
                try await favoriteModel.removeFavoriteRoom(room: viewModel.currentRoom)
            } else {
                try await favoriteModel.addFavorite(room: viewModel.currentRoom)
            }
            // 成功后触发动画 + Toast(跟列表入口对齐)
            isFavoriteAnimating.toggle()
            if favoriteModel.favoriteICloudSyncEnabled, let syncError = favoriteModel.lastSyncError {
                presentToast(ToastValue(
                    icon: Image(systemName: "icloud.slash"),
                    message: (wasFavorited ? "已取消收藏" : "已收藏") + " · iCloud 同步失败：\(syncError.displayText)"
                ))
            } else {
                presentToast(ToastValue(
                    icon: Image(systemName: wasFavorited ? "heart.slash.fill" : "heart.fill"),
                    message: wasFavorited ? "已取消收藏" : "收藏成功"
                ))
            }
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            presentToast(ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: wasFavorited ? "取消收藏失败：\(errorMessage)" : "收藏失败：\(errorMessage)"
            ))
            Logger.warning("收藏操作失败: \(error)", category: .favorite)
        }
    }
}

struct FullUIRoomPopularity: View {
    let count: String?

    var body: some View {
        if let popularity = PlaybackDisplay.popularityTitle(count) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(popularity)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("热度 \(popularity)")
        }
    }
}
