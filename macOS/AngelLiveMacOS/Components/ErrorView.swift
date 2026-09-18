//
//  ErrorView.swift
//  AngelLiveMacOS
//
//  Created by pangchong on 11/26/25.
//

import SwiftUI
import AngelLiveCore
import AppKit

enum ErrorViewPresentationStyle {
    case error
    case empty(symbolName: String, tint: Color)

    var symbolName: String {
        switch self {
        case .error:
            return "exclamationmark.triangle.fill"
        case .empty(let symbolName, _):
            return symbolName
        }
    }

    var tint: Color {
        switch self {
        case .error:
            return .orange
        case .empty(_, let tint):
            return tint
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .error:
            return 36
        case .empty:
            return 32
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .error:
            return 0.16
        case .empty:
            return 0.08
        }
    }
}

enum ErrorViewLayout {
    case fill
    case compact(minHeight: CGFloat)
}

struct ErrorView: View {
    let style: ErrorViewPresentationStyle
    let layout: ErrorViewLayout
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
    @State private var showingSupportDiagnostics = false
    @Environment(\.supportDiagnosticsEnabled) private var supportDiagnosticsEnabled

    init(
        style: ErrorViewPresentationStyle = .error,
        layout: ErrorViewLayout = .fill,
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
        self.style = style
        self.layout = layout
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

    private var hasVisibleActions: Bool {
        (showDismiss && onDismiss != nil)
            || (showRetry && onRetry != nil)
            || (showLoginButton && onLogin != nil)
            || (supportDiagnosticsEnabled && isErrorStyle)
    }

    private var isErrorStyle: Bool {
        if case .error = style {
            return true
        }
        return false
    }

    var body: some View {
        Group {
            switch layout {
            case .fill:
                fillLayout
            case .compact(let minHeight):
                compactLayout(minHeight: minHeight)
            }
        }
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("CURL 命令已复制到剪贴板")
        }
        .sheet(isPresented: $showingSupportDiagnostics) {
            NavigationStack {
                SupportDiagnosticsView()
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("关闭", systemImage: "xmark") {
                                showingSupportDiagnostics = false
                            }
                            .labelStyle(.iconOnly)
                            .help("关闭问题诊断")
                            .keyboardShortcut(.cancelAction)
                        }
                    }
            }
            .frame(minWidth: 600, idealWidth: 640, minHeight: 520, idealHeight: 560)
        }
    }

    private var fillLayout: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 28)
            contentStack
            Spacer(minLength: 28)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppConstants.Colors.primaryBackground)
    }

    private func compactLayout(minHeight: CGFloat) -> some View {
        contentStack
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private var contentStack: some View {
        VStack(spacing: 16) {
            heroCard

            if let curlCommand, !curlCommand.isEmpty {
                curlBlock(curlCommand)
            }

            if let detailMessage, !detailMessage.isEmpty {
                detailBlock(detailMessage)
            }
        }
        .frame(maxWidth: 720)
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                iconView

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 470)
                }

                if let errorCode, !errorCode.isEmpty {
                    Text("错误代码  \(errorCode)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.quaternary.opacity(0.9))
                        )
                }
            }

            if hasVisibleActions {
                HStack(spacing: 10) {
                    actionButtons
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
    }

    private var iconView: some View {
        Image(systemName: style.symbolName)
            .font(.system(size: style.symbolSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(style.tint)
            .shadow(color: style.tint.opacity(style.shadowOpacity), radius: 10, x: 0, y: 4)
            .frame(minWidth: style.symbolSize + 4, minHeight: style.symbolSize + 4)
    }

    private var blockBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppConstants.Colors.secondaryBackground)
    }

    private func curlBlock(_ curlCommand: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("CURL 调试命令", systemImage: "terminal")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: copyCurlCommand) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(curlCommand)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(blockBackground)

            Text("提示：复制此命令到终端执行，可以快速复现当前请求。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    private func detailBlock(_ detailMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("详细信息", systemImage: "text.alignleft")
                .font(.headline)
                .foregroundStyle(.primary)

            ScrollView {
                Text(detailMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(blockBackground)
            }
            .frame(maxHeight: 220)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if showDismiss, let onDismiss {
            Button(action: onDismiss) {
                Label("返回", systemImage: "arrow.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }

        if showLoginButton, let onLogin {
            Button(action: onLogin) {
                Label(
                    supportDiagnosticsEnabled ? "管理账号" : "去登录",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }

        if supportDiagnosticsEnabled, isErrorStyle {
            Button(action: openSupportDiagnostics) {
                Label("诊断与反馈", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("诊断与反馈")
            .accessibilityHint("记录并预览当前错误信息")
        }

        if showRetry, let onRetry {
            Button(action: onRetry) {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func copyCurlCommand() {
        guard let curlCommand, !curlCommand.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curlCommand, forType: .string)
        showCopiedAlert = true
    }

    private func openSupportDiagnostics() {
        SupportDiagnosticsService.shared.makeReportForError(
            title: title,
            message: message,
            detail: detailMessage
        )
        showingSupportDiagnostics = true
    }
}

extension ErrorView {
    static func empty(
        title: String,
        message: String,
        symbolName: String,
        tint: Color = .accentColor,
        layout: ErrorViewLayout = .fill
    ) -> ErrorView {
        ErrorView(
            style: .empty(symbolName: symbolName, tint: tint),
            layout: layout,
            title: title,
            message: message,
            showDismiss: false,
            showRetry: false,
            showLoginButton: false
        )
    }
}

#Preview {
    ErrorView(
        title: "加载失败",
        message: "无法获取直播间列表，请检查网络连接后稍后再试。",
        detailMessage: """
网络请求超时
==================== 网络请求详情 ====================
URL: https://api.example.com/...
方法: GET
""",
        onRetry: {}
    )
    .frame(width: 820, height: 620)
}
