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
    let width: CGFloat?
    @State private var isPressed = false

    init(room: LiveModel, width: CGFloat? = nil) {
        self.room = room
        self.width = width
    }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = width ?? geometry.size.width

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
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(width: cardWidth)
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
                .frame(width: cardWidth)
            }
            .frame(width: cardWidth)
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
        .aspectRatio(280/240, contentMode: .fit)
    }
}
