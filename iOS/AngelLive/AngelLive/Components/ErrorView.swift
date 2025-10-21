//
//  ErrorView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI

/// 错误提示视图
struct ErrorView: View {
    let title: String
    let message: String
    let details: String?
    let retryAction: () -> Void

    init(
        title: String = "加载失败",
        message: String,
        details: String? = nil,
        retryAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.details = details
        self.retryAction = retryAction
    }

    var body: some View {
        VStack(spacing: 24) {
            // 错误图标
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red.opacity(0.8))

            VStack(spacing: 12) {
                // 错误标题
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppConstants.Colors.primaryText)

                // 错误消息
                Text(message)
                    .font(.body)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppConstants.Spacing.lg)

                // 错误详情（可选）
                if let details = details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppConstants.Spacing.xl)
                        .padding(.top, 4)
                }
            }

            // 重试按钮
            Button(action: retryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text("重试")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(AppConstants.Colors.accent)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppConstants.Colors.primaryBackground)
    }
}

#Preview {
    ErrorView(
        title: "加载失败",
        message: "无法获取直播间列表",
        details: "网络连接超时，请检查网络设置后重试",
        retryAction: {
            print("Retry tapped")
        }
    )
}
