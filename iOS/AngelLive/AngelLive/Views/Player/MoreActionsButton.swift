//
//  MoreActionsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore

/// 更多功能按钮（投屏、清屏、定时关闭）
struct MoreActionsButton: View {
    @State private var showActionSheet = false

    var onClearChat: () -> Void

    var body: some View {
        Button(action: {
            showActionSheet = true
        }) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .shadow(
                    color: .black.opacity(0.2),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .confirmationDialog("更多功能", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("投屏") {
                // TODO: 实现投屏功能
                handleAirPlay()
            }

            Button("清屏") {
                onClearChat()
            }

            Button("定时关闭") {
                // TODO: 实现定时关闭功能
                handleTimedShutdown()
            }

            Button("取消", role: .cancel) {
                showActionSheet = false
            }
        }
    }

    // MARK: - Action Handlers

    private func handleAirPlay() {
        // TODO: 实现投屏功能
        print("投屏功能待实现")
    }

    private func handleTimedShutdown() {
        // TODO: 实现定时关闭功能
        print("定时关闭功能待实现")
    }
}

#Preview {
    ZStack {
        Color.black
        MoreActionsButton(onClearChat: {
            print("清屏")
        })
    }
}
