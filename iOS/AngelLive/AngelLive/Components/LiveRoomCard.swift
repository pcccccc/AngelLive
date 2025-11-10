//
//  LiveRoomCard.swift
//  AngelLive
//
//  Created by pangchong on 10/20/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct LiveRoomCard: View {
    let room: LiveModel
    @State private var isPressed = false
    @State private var showPlayer = false
    @Namespace private var namespace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.presentToast) private var presentToast

    init(room: LiveModel, width: CGFloat? = nil) {
        self.room = room
    }

    // 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == room.roomId })
    }

    var body: some View {
        Group {
            if AppConstants.Device.isIPad {
                // iPad: 使用 fullScreenCover
                Button {
                    showPlayer = true
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    favoriteContextMenu
                }
                .fullScreenCover(isPresented: $showPlayer) {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                        .navigationTransition(.zoom(sourceID: room.roomId, in: namespace))
                        .toolbar(.hidden, for: .tabBar)
                }
            } else {
                // iPhone: 使用 NavigationLink
                NavigationLink {
                    DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                        .navigationTransition(.zoom(sourceID: room.roomId, in: namespace))
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    favoriteContextMenu
                }
            }
        }
    }

    private var cardContent: some View {
        VStack {
            // 封面图
            KFImage(URL(string: room.roomCover))
                .placeholder {
                    Rectangle()
                        .fill(AppConstants.Colors.placeholderGradient())
                }
                .resizable()
                .blur(radius: 10)
                .overlay(
                    KFImage(URL(string: room.roomCover))
                        .placeholder {
                            Image("placeholder")
                                .resizable()
                                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                .matchedTransitionSource(id: room.roomId, in: namespace)

            // 主播信息
            HStack(spacing: 8) {
                KFImage(URL(string: room.userHeadImg))
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .resizable()
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

                Spacer()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .fill(.clear)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    @ViewBuilder
    private var favoriteContextMenu: some View {
        if isFavorited {
            Button(role: .destructive) {
                Task {
                    await removeFavorite()
                }
            } label: {
                Label("取消收藏", systemImage: "heart.slash.fill")
            }
        } else {
            Button {
                Task {
                    await addFavorite()
                }
            } label: {
                Label("收藏", systemImage: "heart.fill")
            }
        }
    }

    @MainActor
    private func addFavorite() async {
        do {
            try await favoriteModel.addFavorite(room: room)

            // 显示成功提示
            let toast = ToastValue(
                icon: Image(systemName: "heart.fill"),
                message: "收藏成功"
            )
            presentToast(toast)
        } catch {
            // 显示失败提示
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: "收藏失败"
            )
            presentToast(toast)
            print("收藏失败: \(error)")
        }
    }

    @MainActor
    private func removeFavorite() async {
        do {
            try await favoriteModel.removeFavoriteRoom(room: room)

            // 显示成功提示
            let toast = ToastValue(
                icon: Image(systemName: "heart.slash.fill"),
                message: "已取消收藏"
            )
            presentToast(toast)
        } catch {
            // 显示失败提示
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: "取消收藏失败"
            )
            presentToast(toast)
            print("取消收藏失败: \(error)")
        }
    }
}
