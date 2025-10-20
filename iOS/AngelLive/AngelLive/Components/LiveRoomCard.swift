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

            VStack {
                // 封面图
                ZStack(alignment: .topTrailing) {

                    KFImage(URL(string: room.roomCover))
                    .placeholder {
                        Rectangle()
                            .fill(AppConstants.Colors.placeholderGradient())
                    }
                    .resizable()
                    .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fill)
                    .blur(radius: 10)
                    .frame(width: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                    
                    KFImage(URL(string: room.roomCover))
                        .placeholder {
                            Image("placeholder")
                                .resizable()
                                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                                .frame(width: cardWidth)
                                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: cardWidth)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                }

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
                .frame(width: cardWidth)
            }
            .frame(width: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                    .fill(.clear)
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
        .aspectRatio(AppConstants.AspectRatio.card, contentMode: .fit)
    }
}
