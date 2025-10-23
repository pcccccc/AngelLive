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
    @State private var isFavorited = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 直播间标题（置顶，加大加粗）
            Text(viewModel.currentRoom.roomTitle)
                .font(.title2.bold())
                .foregroundStyle(Color(white: 0.95))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 主播信息行
            HStack(spacing: 12) {
                // 主播头像
                KFImage(URL(string: viewModel.currentRoom.userHeadImg))
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    // 主播名称
                    Text(viewModel.currentRoom.userName)
                        .font(.headline)
                        .foregroundStyle(Color(white: 0.9))

                    // 平台信息
                    HStack(spacing: 6) {
                        Image(systemName: "play.tv.fill")
                            .font(.caption2)
                        Text(viewModel.currentRoom.liveType.rawValue)
                            .font(.caption)
                    }
                    .foregroundStyle(Color(white: 0.7))
                }

                Spacer()

                // 收藏按钮
                Button(action: {
                    isFavorited.toggle()
                    // TODO: 实现收藏逻辑
                }) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(isFavorited ? .red : Color(white: 0.7))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.1))
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
