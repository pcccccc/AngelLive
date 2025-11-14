//
//  FavoriteView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import LiveParse

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var favoriteModel

    var body: some View {
        Group {
            if favoriteModel.roomList.isEmpty {
                ContentUnavailableView(
                    "暂无收藏",
                    systemImage: "heart.slash",
                    description: Text("浏览直播间并添加收藏")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                        ForEach(favoriteModel.roomList) { room in
                            NavigationLink(value: room) {
                                RoomCardView(room: room)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("收藏")
    }
}

// 占位符卡片视图
struct RoomCardView: View {
    let room: LiveModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图
            AsyncImage(url: URL(string: room.roomCover)) { image in
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 房间信息
            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(room.userName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(AppConstants.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
