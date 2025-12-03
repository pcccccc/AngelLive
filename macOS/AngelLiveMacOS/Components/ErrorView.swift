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
    let curlCommand: String?
    let showDismiss: Bool
    let showRetry: Bool
    let showLoginButton: Bool
    let onDismiss: (() -> Void)?
    let onRetry: (() -> Void)?
    let onLogin: (() -> Void)?

    @State private var showCopiedAlert = false

    init(
        title: String = "加载失败",
        message: String,
        errorCode: String? = nil,
        detailMessage: String? = nil,
        curlCommand: String? = nil,
        showDismiss: Bool = false,
        showRetry: Bool = true,
        showLoginButton: Bool = false,
        onDismiss: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onLogin: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.errorCode = errorCode
        self.detailMessage = detailMessage
        self.curlCommand = curlCommand
        self.showDismiss = showDismiss
        self.showRetry = showRetry
        self.showLoginButton = showLoginButton
        self.onDismiss = onDismiss
        self.onRetry = onRetry
        self.onLogin = onLogin
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

            // CURL 命令（如果有）
            if let curlCommand = curlCommand, !curlCommand.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CURL 调试命令")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(curlCommand, forType: .string)
                            showCopiedAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("复制")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView {
                        Text(curlCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)

                    Text("提示：复制此命令到终端执行可以复现请求")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: 600)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }

            // 直接显示错误详情（macOS 屏幕大，直接展示）
            if let detailMessage = detailMessage, !detailMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("详细信息")
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
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("返回")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.gray.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }

                if showLoginButton, let onLogin = onLogin {
                    Button(action: onLogin) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 13, weight: .semibold))
                            Text("去登录")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.green))
                    }
                    .buttonStyle(.plain)
                }

                if showRetry, let onRetry = onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                            Text("重试")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("CURL 命令已复制到剪贴板")
        }
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
