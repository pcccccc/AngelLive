//
//  ErrorView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI

/// 全局错误提示视图
struct ErrorView: View {
    let title: String
    let message: String
    let errorCode: String?
    let detailMessage: String?
    let curlCommand: String?
    let qrCodeURL: String?
    let showDismiss: Bool
    let showRetry: Bool
    let showLoginButton: Bool
    let showDetailButton: Bool
    let onDismiss: (() -> Void)?
    let onRetry: (() -> Void)?
    let onLogin: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDetailSheet = false
    @State private var showingCookieDebugView = false

    // 检查是否已登录B站
    private var isBilibiliLoggedIn: Bool {
        let cookie = UserDefaults.standard.string(forKey: "SimpleLive.Setting.BilibiliCookie") ?? ""
        return !cookie.isEmpty && cookie.contains("SESSDATA")
    }

    private var bilibiliCookie: String {
        UserDefaults.standard.string(forKey: "SimpleLive.Setting.BilibiliCookie") ?? ""
    }

    init(
        title: String = "加载失败",
        message: String,
        errorCode: String? = nil,
        detailMessage: String? = nil,
        curlCommand: String? = nil,
        qrCodeURL: String? = nil,
        showDismiss: Bool = false,
        showRetry: Bool = true,
        showLoginButton: Bool = false,
        showDetailButton: Bool = false,
        onDismiss: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onLogin: (() -> Void)? = nil
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
        self.showDetailButton = showDetailButton
        self.onDismiss = onDismiss
        self.onRetry = onRetry
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { geometry in
            let isPadLandscape = UIDevice.current.userInterfaceIdiom == .pad && geometry.size.width > geometry.size.height

            ZStack {
                // 使用系统背景色，确保与应用主题一致
                Color(UIColor.systemBackground).ignoresSafeArea()

                if isPadLandscape {
                    padLandscapeLayout
                        .padding(40)
                } else {
                    portraitLayout
                }
            }
        }
        .sheet(isPresented: $showingDetailSheet) {
            ErrorDetailSheet(
                title: title,
                message: message,
                detailMessage: detailMessage ?? "",
                curlCommand: curlCommand
            )
        }
        .sheet(isPresented: $showingCookieDebugView) {
            BilibiliCookieDebugView(cookie: bilibiliCookie)
        }
    }
}

// MARK: - 错误详情弹窗

struct ErrorDetailSheet: View {
    let title: String
    let message: String
    let detailMessage: String
    let curlCommand: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 错误标题
                    VStack(alignment: .leading, spacing: 8) {
                        Text("错误信息")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(title)
                            .font(.title3.bold())
                        Text(message)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // CURL 命令（如果有）
                    if let curlCommand = curlCommand, !curlCommand.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("CURL 调试命令")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button(action: {
                                    UIPasteboard.general.string = curlCommand
                                    showCopiedAlert = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 13))
                                        Text("复制")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }

                            Text(curlCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(8)

                            Text("提示：复制此命令到终端执行可以复现请求")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // 详细信息
                    VStack(alignment: .leading, spacing: 8) {
                        Text("详细信息")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(detailMessage)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("错误详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("已复制", isPresented: $showCopiedAlert) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("CURL 命令已复制到剪贴板")
            }
        }
    }
}

// MARK: - iOS 适配布局

private extension ErrorView {
    var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 60)

                iconView
                    .padding(.bottom, 20)

                infoBlock(alignment: .center)
                    .padding(.horizontal)

                qrBlock
                    .padding(.top, 20)

                Spacer(minLength: 20)

                actionButtons
                    .padding(.top, 30)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical)
        }
    }

    var padLandscapeLayout: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 20) {
                iconView

                infoBlock(alignment: .leading)

                actionButtons
                    .padding(.top, 10)

                if showDetailButton, detailMessage != nil, !(detailMessage ?? "").isEmpty {
                    detailInlineBlock
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: 700, alignment: .leading)

            qrBlock
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    var iconView: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(
                LinearGradient(
                    colors: [.red, .orange],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
    }

    func infoBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)

            Text(message)
                .font(.headline.weight(.regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .leading ? 0 : 16)

            if let errorCode = errorCode, !errorCode.isEmpty {
                Text("错误代码: \(errorCode)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(.quaternary)
                    )
                    .padding(.top, 8)
            }

            if let detailMessage = detailMessage, !detailMessage.isEmpty, !showDetailButton {
                Text(detailMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
                    .padding(.horizontal, alignment == .leading ? 0 : 30)
            }
        }
    }

    var qrBlock: some View {
        Group {
            if let qrCodeURL = qrCodeURL, !qrCodeURL.isEmpty {
                VStack(spacing: 12) {
                    Image(uiImage: QRCodeGenerator.generateQRCode(from: qrCodeURL))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding()
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 15, y: 10)

                    Text("扫码查看帮助文档")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var actionButtons: some View {
        HStack(spacing: 16) {
            if showDismiss, let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                }
                .buttonStyle(.plain)
            }

            if showLoginButton {
                if isBilibiliLoggedIn {
                    // 已登录：显示查看官方页面按钮
                    Button(action: {
                        showingCookieDebugView = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("查看官方页面")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                    }
                    .buttonStyle(.plain)
                } else if let onLogin = onLogin {
                    // 未登录：显示去登录按钮
                    Button(action: onLogin) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 15, weight: .semibold))
                            Text("去登录")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.green)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if showRetry, let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                        Text("重试")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }

            if showDetailButton, detailMessage != nil, !detailMessage!.isEmpty {
                Button(action: {
                    showingDetailSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                        Text("查看详情")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    var detailInlineBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("错误详情")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(detailMessage ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Convenience Initializers & Previews
// (保持不变，以确保功能兼容性)

extension ErrorView {
    /// 简单错误视图 - 只有重试按钮
    static func simple(
        message: String,
        onRetry: @escaping () -> Void
    ) -> ErrorView {
        ErrorView(
            message: message,
            showRetry: true,
            onRetry: onRetry
        )
    }

    /// 播放错误视图 - 带返回和重试按钮
    static func playback(
        message: String,
        errorCode: String? = nil,
        detailMessage: String? = nil,
        curlCommand: String? = nil,
        onDismiss: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) -> ErrorView {
        let hasDetail = detailMessage != nil && !detailMessage!.isEmpty
        return ErrorView(
            title: "播放遇到问题",
            message: message,
            errorCode: errorCode,
            detailMessage: detailMessage,
            curlCommand: curlCommand,
            qrCodeURL: "https://github.com/pcccccc/SimpleLiveTVOS",
            showDismiss: true,
            showRetry: onRetry != nil,
            showDetailButton: hasDetail,
            onDismiss: onDismiss,
            onRetry: onRetry
        )
    }

    /// 网络错误视图
    static func network(
        onRetry: @escaping () -> Void
    ) -> ErrorView {
        ErrorView(
            title: "网络错误",
            message: "无法连接到服务器",
            detailMessage: "请检查网络连接后重试",
            showRetry: true,
            onRetry: onRetry
        )
    }
}


#Preview("新版基础错误") {
    ErrorView(
        title: "加载失败",
        message: "无法获取直播间列表，请检查您的网络连接或稍后再试。",
        errorCode: "NETWORK_TIMEOUT",
        onRetry: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("新版播放错误") {
    ErrorView.playback(
        message: "视频流加载失败，主播可能已下播或更换了直播地址。",
        errorCode: "HLS_ERROR_404",
        detailMessage: "您可以尝试刷新或返回上一页。",
        onDismiss: {},
        onRetry: {}
    )
}

#Preview("新版带二维码") {
    ErrorView(
        title: "播放遇到问题",
        message: "该直播需要登录才能观看。",
        errorCode: "AUTH_REQUIRED",
        qrCodeURL: "https://github.com/pcccccc/SimpleLiveTVOS",
        showDismiss: true,
        showRetry: false,
        onDismiss: {}
    )
}

#Preview("新版网络错误") {
    ErrorView.network {
        print("Retry network")
    }
    .preferredColorScheme(.light)
}
