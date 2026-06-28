// TVAddPluginSourceView.swift
// AngelLiveTVOS
//
// 在插件管理页里追加订阅源:沿用 TVShellConfigView 的"输入框 + 远程输入 QR"布局,
// 但裁掉视频书签兜底与 showPluginManagement 跳转,只处理订阅源,成功后自动 dismiss。

import SwiftUI
import AngelLiveCore

struct TVAddPluginSourceView: View {
    @Environment(AppState.self) private var appViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputURL = ""
    @State private var isProcessing = false
    @State private var localErrorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field { case url, add }

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.thinMaterial)
                .ignoresSafeArea()

            HStack(alignment: .center, spacing: 120) {
                VStack(alignment: .leading, spacing: 28) {
                    Text("添加订阅源")
                        .font(.system(size: 48, weight: .heavy))

                    Text("输入插件订阅地址(.json) 或兑换码,添加后会刷新插件目录。")
                        .font(.system(size: 24, weight: .medium))
                        .lineSpacing(6)
                        .foregroundStyle(.secondary)

                    TextField("输入订阅地址或兑换码", text: $inputURL)
                        .focused($focusedField, equals: .url)
                        .frame(maxWidth: 600, alignment: .leading)

                    if let error = localErrorMessage ?? appViewModel.pluginSourceManager.errorMessage {
                        PluginSourceErrorCard(title: "插件源异常", message: error)
                            .frame(maxWidth: 600, alignment: .leading)
                    }

                    Spacer()

                    HStack(spacing: 20) {
                        Button(action: handleAdd) {
                            Label("添加", systemImage: "plus.circle.fill")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        .disabled(trimmedURL.isEmpty || isProcessing)
                        .focused($focusedField, equals: .add)

                        Button("取消") {
                            dismiss()
                        }

                        if isProcessing {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)

                remoteInputQRPanel
            }
            .padding(80)
            .safeAreaPadding()
        }
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard let event = appViewModel.remoteInputService.lastEvent else { return }
            switch event.field {
            case .url:
                inputURL = event.value
            case .config:
                if let url = event.url { inputURL = url }
            case .title, .search, .cookie:
                break
            }
        }
        .onExitCommand {
            dismiss()
        }
    }

    private var remoteInputQRPanel: some View {
        let service = appViewModel.remoteInputService
        let url = "http://\(service.localIPAddress):\(service.port)/config"
        return VStack(spacing: 16) {
            Spacer()
            if service.isRunning && !service.localIPAddress.isEmpty {
                Image(uiImage: Common.generateQRCode(from: url))
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

                Text("扫码用手机输入")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(url)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                Text("正在启动远程输入...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func handleAdd() {
        let url = trimmedURL
        guard !url.isEmpty else { return }

        localErrorMessage = nil
        isProcessing = true
        Task {
            // 乐观添加:即使源当前拉取失败也会把它存下来并返回(标记为异常),所以这里拿到非空就算添加成功。
            let addedURLs = await appViewModel.pluginSourceManager.addSourceFromInput(url)
            isProcessing = false
            if !addedURLs.isEmpty {
                inputURL = ""
                // 不在这里阻塞式重新拉全量目录(失效源会让 dismiss 等满超时);
                // 上层管理页在 cover 关闭后会自行 reloadPluginCatalog,失败源的行会显示"检查中→异常"。
                dismiss()
            } else if appViewModel.pluginSourceManager.errorMessage == nil {
                // 返回空且没写 errorMessage:输入既不是 key,也不是合法 URL。
                localErrorMessage = "无法解析为订阅源,请确认地址是 .json 订阅或有效兑换码。"
            }
        }
    }
}
