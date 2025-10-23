//
//  ChatMessage.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import Foundation

/// 聊天消息模型
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let userName: String
    let userAvatar: String?
    let message: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        userName: String,
        userAvatar: String? = nil,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userName = userName
        self.userAvatar = userAvatar
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - Mock Data for Preview

extension ChatMessage {
    static let mockMessages: [ChatMessage] = [
        ChatMessage(userName: "用户1", message: "这个主播太棒了！"),
        ChatMessage(userName: "观众A", message: "666"),
        ChatMessage(userName: "粉丝小明", message: "刚来，发生了什么？"),
        ChatMessage(userName: "路人甲", message: "哈哈哈哈哈哈哈"),
        ChatMessage(userName: "观众B", message: "主播唱得真好听"),
        ChatMessage(userName: "用户2", message: "支持支持！"),
        ChatMessage(userName: "粉丝999", message: "这是我见过最有才华的主播了，真的太厉害了！"),
    ]
}
