//
//  ChatListView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore

/// 聊天列表视图
struct ChatListView: View {
    @State private var messages: [ChatMessage] = ChatMessage.mockMessages
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
            .onChange(of: messages.count) { oldValue, newValue in
                withAnimation {
                    scrollToBottom()
                }
            }
        }
    }

    private func scrollToBottom() {
        if let lastMessage = messages.last {
            withAnimation {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Public Methods

    func addMessage(_ message: ChatMessage) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            messages.append(message)
        }
    }

    func clearMessages() {
        withAnimation {
            messages.removeAll()
        }
    }
}

#Preview {
    ChatListView()
        .frame(height: 300)
        .background(Color.black.opacity(0.3))
}
