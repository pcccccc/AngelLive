//
//  ChatBubbleView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore

/// 聊天气泡视图（自适应形状，短消息用胶囊，长消息用圆角矩形）
struct ChatBubbleView: View {
    let message: ChatMessage

    // 判断是否使用胶囊形状（短消息）
    private var shouldUseCapsule: Bool {
        let combinedLength = message.userName.count + message.message.count
        return combinedLength < 30 // 总长度小于30使用胶囊形状
    }

    var body: some View {
        if message.isSystemMessage {
            // 系统消息样式
            systemMessageView
        } else {
            // 普通用户消息样式
            userMessageView
        }
    }

    // 系统消息视图
    private var systemMessageView: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow.opacity(0.8))

            Text(message.message)
                .font(.caption2)
                .foregroundStyle(.yellow.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Group {
                if message.message.count < 20 {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(.yellow.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.3), lineWidth: 0.5))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12).fill(.yellow.opacity(0.15)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.yellow.opacity(0.3), lineWidth: 0.5))
                }
            }
        )
        .shadow(
            color: .black.opacity(0.1),
            radius: 2,
            x: 0,
            y: 1
        )
    }

    // 用户消息视图
    private var userMessageView: some View {
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
            Group {
                if shouldUseCapsule {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(.black.opacity(0.3)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                }
            }
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
