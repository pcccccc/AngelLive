//
//  ErrorView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2025/11/20.
//

import SwiftUI

struct ErrorView: View {
    let title: String
    let message: String
    let errorCode: String?
    let detailMessage: String?
    let qrCodeURL: String
    let showDismiss: Bool
    let showRetry: Bool
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    init(
        title: String = "播放遇到问题",
        message: String,
        errorCode: String? = nil,
        detailMessage: String? = nil,
        qrCodeURL: String = "https://github.com/pcccccc/SimpleLiveTVOS",
        showDismiss: Bool = true,
        showRetry: Bool = false,
        onDismiss: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.errorCode = errorCode
        self.detailMessage = detailMessage
        self.qrCodeURL = qrCodeURL
        self.showDismiss = showDismiss
        self.showRetry = showRetry
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.thinMaterial)
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 120) {
                VStack(alignment: .leading, spacing: 28) {
                    Text(title)
                        .font(.system(size: 48, weight: .heavy))

                    VStack(alignment: .leading, spacing: 14) {
                        Text(message)
                            .font(.system(size: 24, weight: .medium))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)

                        if let errorCode = errorCode {
                            Text("错误代码：\(errorCode)")
                                .font(.system(size: 20, weight: .semibold))
                                .padding(.top, 4)
                        }

                        if let detailMessage = detailMessage {
                            Text(detailMessage)
                                .font(.system(size: 20))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 20)

                    HStack(spacing: 18) {
                        if showDismiss {
                            Button(action: onDismiss) {
                                Label("返回", systemImage: "arrow.left")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                            .clipShape(.capsule)
                        }

                        if showRetry, let onRetry = onRetry {
                            Button(action: onRetry) {
                                Label("重试", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                            .clipShape(.capsule)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    // 直接显示错误详情（tvOS 屏幕大，直接展示）
                    if let detailMessage = detailMessage, !detailMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("错误详情")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))

                            ScrollView {
                                Text(detailMessage)
                                    .font(.system(size: 18, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 300)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .padding(.top, 20)
                    }
                }
                .frame(maxWidth: 950, alignment: .leading)

                VStack(spacing: 16) {
                    Spacer()
                    Image(uiImage: Common.generateQRCode(from: qrCodeURL))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 330, height: 330)
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
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
        }
    }
}
