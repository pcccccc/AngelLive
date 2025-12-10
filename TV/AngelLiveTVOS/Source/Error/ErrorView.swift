//
//  ErrorView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2025/11/20.
//

import SwiftUI
import AngelLiveCore

struct ErrorView: View {
    let title: String
    let message: String
    let errorCode: String?
    let detailMessage: String?
    let curlCommand: String?
    let qrCodeURL: String
    let showDismiss: Bool
    let showRetry: Bool
    let showLoginButton: Bool
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    @State private var showDetailView = false

    // 检查是否已登录B站
    private var isBilibiliLoggedIn: Bool {
        let cookie = UserDefaults.standard.string(forKey: "SimpleLive.Setting.BilibiliCookie") ?? ""
        return !cookie.isEmpty && cookie.contains("SESSDATA")
    }

    // 是否有详情可显示
    private var hasDetail: Bool {
        (detailMessage != nil && !detailMessage!.isEmpty) || (curlCommand != nil && !curlCommand!.isEmpty)
    }

    init(
        title: String = "播放遇到问题",
        message: String,
        errorCode: String? = nil,
        detailMessage: String? = nil,
        curlCommand: String? = nil,
        qrCodeURL: String = "https://github.com/pcccccc/SimpleLiveTVOS",
        showDismiss: Bool = true,
        showRetry: Bool = false,
        showLoginButton: Bool = false,
        onDismiss: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.errorCode = errorCode
        self.detailMessage = detailMessage
        self.curlCommand = curlCommand
        self.qrCodeURL = qrCodeURL
        self.showDismiss = showDismiss
        self.showRetry = showRetry
        self.showLoginButton = showLoginButton
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.thinMaterial)
                .ignoresSafeArea()

            HStack(alignment: .center, spacing: 120) {
                VStack(alignment: .leading, spacing: 28) {
                    Text(title)
                        .font(.system(size: 48, weight: .heavy))

                    Text(message)
                        .font(.system(size: 24, weight: .medium))
                        .lineSpacing(6)

                    // -352 错误且已登录时显示额外提示
                    if showLoginButton && isBilibiliLoggedIn {
                        Text("tvOS 用户如已经登录依旧报错，请等待几分钟后重试")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.yellow)
                            .lineSpacing(4)
                    }

                    if let errorCode = errorCode {
                        Text("错误代码：\(errorCode)")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    HStack(spacing: 20) {
                        if showDismiss {
                            Button(action: onDismiss) {
                                Label("返回", systemImage: "arrow.left")
                                    .font(.caption)
                            }
                        }

                        // -352 错误时，只有未登录才显示登录按钮
                        if showLoginButton && !isBilibiliLoggedIn {
                            Button(action: {
                                onDismiss()
                                NotificationCenter.default.post(name: SimpleLiveNotificationNames.navigateToSettings, object: nil)
                            }) {
                                Label("去登录", systemImage: "person.crop.circle.badge.checkmark")
                                    .font(.caption)
                            }
                        }

                        if showRetry, let onRetry = onRetry {
                            Button(action: onRetry) {
                                Label("重试", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }

                        if hasDetail {
                            Button(action: { showDetailView = true }) {
                                Label("查看详情", systemImage: "doc.text.magnifyingglass")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)

                VStack(spacing: 16) {
                    Spacer()
                    Image(uiImage: Common.generateQRCode(from: qrCodeURL))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 280)
                        .padding(28)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 18)

                    Text("扫码查看帮助文档")
                        .font(.caption)
                    Spacer()
                }
            }
            .padding(80)
            .safeAreaPadding()

            // 错误详情 Overlay
            if showDetailView {
                ErrorDetailOverlay(
                    detailMessage: detailMessage,
                    curlCommand: curlCommand,
                    onClose: { showDetailView = false }
                )
            }
        }
    }
}

// MARK: - 错误详情 Overlay
struct ErrorDetailOverlay: View {
    let detailMessage: String?
    let curlCommand: String?
    let onClose: () -> Void

    @FocusState private var isCloseButtonFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 30) {
                // 标题栏
                HStack {
                    Text("错误详情")
                        .font(.system(size: 48, weight: .heavy))

                    Spacer()

                    Button(action: onClose) {
                        Label("关闭", systemImage: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .focused($isCloseButtonFocused)
                }

                HStack(alignment: .top, spacing: 50) {
                    // 左侧：错误信息
                    if let detailMessage = detailMessage, !detailMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("错误信息")
                                .font(.system(size: 24, weight: .semibold))

                            ScrollView {
                                Text(detailMessage)
                                    .font(.system(size: 20, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.4))
                        )
                        .frame(maxWidth: .infinity)
                    }

                    // 右侧：二维码
                    if let curlCommand = curlCommand, !curlCommand.isEmpty {
                        VStack(spacing: 16) {
                            Image(uiImage: Common.generateQRCode(from: curlCommand))
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 240, height: 240)
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )

                            Text("扫码获取 CURL 命令")
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(50)
            .frame(maxWidth: 1200, maxHeight: 600)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .transition(.opacity)
        .onExitCommand {
            onClose()
        }
        .onAppear {
            isCloseButtonFocused = true
        }
    }
}
