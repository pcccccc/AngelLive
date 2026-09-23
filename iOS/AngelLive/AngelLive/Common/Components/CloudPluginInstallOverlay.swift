//
//  CloudPluginInstallOverlay.swift
//  AngelLive
//
//  The one-click cloud plugin installation progress card.
//

import SwiftUI

struct CloudPluginInstallResult: Equatable {
    let installedCount: Int
    let failedCount: Int
    let skippedCount: Int
    let sourceFailureCount: Int
    let firstError: String?

    var canRetry: Bool {
        failedCount > 0
            || sourceFailureCount > 0
            || installedCount == 0
            || skippedCount > 0
    }
}

struct CloudPluginInstallOverlay: View {
    let statusMessage: String
    let completedCount: Int
    let totalCount: Int
    let result: CloudPluginInstallResult?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                CloudPluginInstallCard(
                    statusMessage: statusMessage,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    result: result,
                    onRetry: onRetry,
                    onDismiss: onDismiss
                )
                .frame(maxWidth: 340)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.black.opacity(0.32).ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}

private struct CloudPluginInstallCard: View {
    let statusMessage: String
    let completedCount: Int
    let totalCount: Int
    let result: CloudPluginInstallResult?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let result {
                CloudPluginInstallResultContent(
                    result: result,
                    onRetry: onRetry,
                    onDismiss: onDismiss
                )
            } else {
                CloudPluginInstallProgressContent(
                    statusMessage: statusMessage,
                    completedCount: completedCount,
                    totalCount: totalCount
                )
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct CloudPluginInstallProgressContent: View {
    let statusMessage: String
    let completedCount: Int
    let totalCount: Int

    private var processedCount: Int {
        guard totalCount > 0 else { return max(completedCount, 0) }
        return min(max(completedCount, 0), totalCount)
    }

    var body: some View {
        VStack(spacing: 16) {
            CloudPluginInstallArc()

            Text("正在安装插件")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if totalCount > 0 {
                VStack(spacing: 8) {
                    ProgressView(
                        value: Double(processedCount),
                        total: Double(totalCount)
                    )
                    .tint(.accentColor)

                    Text("已处理 \(processedCount) / \(totalCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text("首次安装可能需要一点时间")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct CloudPluginInstallArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .frame(width: 42, height: 42)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
            .onAppear {
                startAnimationIfNeeded()
            }
            .onChange(of: reduceMotion) { _, value in
                if value {
                    rotation = 0
                } else {
                    startAnimationIfNeeded()
                }
            }
    }

    private func startAnimationIfNeeded() {
        guard !reduceMotion else {
            rotation = 0
            return
        }

        rotation = 0
        withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct CloudPluginInstallResultContent: View {
    let result: CloudPluginInstallResult
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var isFullyInstalled: Bool {
        result.installedCount > 0
            && result.failedCount == 0
            && result.skippedCount == 0
            && result.sourceFailureCount == 0
    }

    private var title: LocalizedStringKey {
        if isFullyInstalled {
            return "插件已就绪"
        }
        if result.installedCount > 0 {
            return "部分插件未安装"
        }
        return "暂未安装插件"
    }

    private var symbolName: String {
        if isFullyInstalled { return "checkmark.circle" }
        if result.installedCount > 0 { return "exclamationmark.circle" }
        if result.failedCount > 0 || result.sourceFailureCount > 0 {
            return "xmark.circle"
        }
        return "minus.circle"
    }

    private var symbolColor: Color {
        if isFullyInstalled { return .green }
        if result.installedCount > 0 { return .orange }
        if result.failedCount > 0 || result.sourceFailureCount > 0 {
            return .red
        }
        return .secondary
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbolName)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            CloudPluginInstallResultSummary(result: result)

            CloudPluginInstallResultActions(
                result: result,
                onRetry: onRetry,
                onDismiss: onDismiss
            )
        }
    }
}

private struct CloudPluginInstallResultSummary: View {
    let result: CloudPluginInstallResult

    private var hasAnyResult: Bool {
        result.installedCount > 0
            || result.failedCount > 0
            || result.skippedCount > 0
            || result.sourceFailureCount > 0
    }

    private var hasFirstError: Bool {
        guard let firstError = result.firstError else { return false }
        return !firstError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.installedCount > 0 {
                Text("已安装 \(result.installedCount) 个插件")
            }

            if result.failedCount > 0 {
                Text("\(result.failedCount) 个插件安装失败")
            }

            if result.skippedCount > 0 {
                Text("\(result.skippedCount) 个插件已跳过")
            }

            if result.sourceFailureCount > 0 {
                Text("\(result.sourceFailureCount) 个插件源获取失败")
            }

            if !hasAnyResult && !hasFirstError {
                Text("插件源中暂无可安装的插件")
            } else if result.installedCount == 0,
                      result.skippedCount > 0,
                      result.failedCount == 0,
                      result.sourceFailureCount == 0 {
                Text("你已跳过需要确认的插件，可重新安装后继续确认")
            }

            if let firstError = result.firstError, hasFirstError {
                Text(firstError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CloudPluginInstallResultActions: View {
    let result: CloudPluginInstallResult
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var hasInstalledPlugins: Bool {
        result.installedCount > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            if hasInstalledPlugins {
                Button(action: onDismiss) {
                    Text(result.canRetry ? "继续使用" : "开始使用")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                if result.canRetry {
                    Button(action: onRetry) {
                        Text("重试未完成项")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Button(action: onRetry) {
                    Text("重试")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDismiss) {
                    Text("稍后再说")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

#Preview("Installing") {
    CloudPluginInstallOverlay(
        statusMessage: "正在同步可用插件",
        completedCount: 3,
        totalCount: 8,
        result: nil,
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Success") {
    CloudPluginInstallOverlay(
        statusMessage: "",
        completedCount: 4,
        totalCount: 4,
        result: CloudPluginInstallResult(
            installedCount: 4,
            failedCount: 0,
            skippedCount: 0,
            sourceFailureCount: 0,
            firstError: nil
        ),
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Partial failure") {
    CloudPluginInstallOverlay(
        statusMessage: "",
        completedCount: 0,
        totalCount: 0,
        result: CloudPluginInstallResult(
            installedCount: 2,
            failedCount: 1,
            skippedCount: 1,
            sourceFailureCount: 1,
            firstError: "示例插件：安装失败，请稍后重试"
        ),
        onRetry: {},
        onDismiss: {}
    )
}
