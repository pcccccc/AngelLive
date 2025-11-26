//
//  ErrorView.swift
//  AngelLiveMacOS
//
//  Created by pangchong on 11/26/25.
//

import SwiftUI

struct ErrorView: View {
    let title: String
    let message: String
    let errorCode: String?
    let detailMessage: String?
    let showDismiss: Bool
    let showRetry: Bool
    let onDismiss: (() -> Void)?
    let onRetry: (() -> Void)?

    init(
        title: String = "加载失败",
        message: String,
        errorCode: String? = nil,
        detailMessage: String? = nil,
        showDismiss: Bool = false,
        showRetry: Bool = true,
        onDismiss: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.errorCode = errorCode
        self.detailMessage = detailMessage
        self.showDismiss = showDismiss
        self.showRetry = showRetry
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 错误图标
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 标题和消息
            VStack(spacing: 8) {
                Text(title)
                    .font(.title.bold())

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let errorCode = errorCode {
                    Text("错误代码: \(errorCode)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
            }

            // 直接显示错误详情（macOS 屏幕大，直接展示）
            if let detailMessage = detailMessage, !detailMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("错误详情")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(detailMessage)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .frame(maxWidth: 600)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }

            // 按钮
            HStack(spacing: 16) {
                if showDismiss, let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Label("返回", systemImage: "arrow.left")
                    }
                    .buttonStyle(.bordered)
                }

                if showRetry, let onRetry = onRetry {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ErrorView(
        title: "加载失败",
        message: "无法获取直播间列表，请检查网络连接",
        detailMessage: "网络请求超时\n==================== 网络请求详情 ====================\nURL: https://api.live.bilibili.com/...\n方法: GET",
        onRetry: {}
    )
    .frame(width: 800, height: 600)
}
