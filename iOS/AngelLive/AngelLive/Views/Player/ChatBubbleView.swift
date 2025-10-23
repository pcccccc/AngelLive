//
//  ChatBubbleView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore

/// 聊天气泡视图（胶囊形状，自适应大小）
struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 用户名
            Text(message.userName)
                .font(.caption.bold())
                .foregroundStyle(randomUserColor(for: message.userName))
                .lineLimit(1)

            // 消息内容
            Text(message.message)
                .font(.caption)
                .foregroundStyle(Color(white: 0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(.black.opacity(0.3))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .shadow(
            color: .black.opacity(0.1),
            radius: 2,
            x: 0,
            y: 1
        )
    }

    // 根据用户名生成随机颜色（同一用户名颜色固定）
    private func randomUserColor(for userName: String) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo
        ]
        let hash = userName.hashValue
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ChatMessage.mockMessages) { message in
            ChatBubbleView(message: message)
        }
    }
    .padding()
    .background(Color.black)
}
