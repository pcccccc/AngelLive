//
//  ShellConfigView.swift
//  AngelLive
//
//  壳 UI - 配置页：统一输入框，自动识别视频链接或订阅地址。
//

import SwiftUI
import AngelLiveCore

struct ShellConfigView: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(PluginSourceManager.self) private var pluginSourceManager

    let onOpenPluginSources: ([String]) -> Void

    @State private var inputURL = ""
    @State private var inputTitle = ""
    @State private var isProcessing = false

    var body: some View {
        List {
            addSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("配置")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - 添加

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubscriptionURL: Bool {
        guard !trimmedURL.isEmpty else { return false }
        if let url = URL(string: trimmedURL) {
            return url.pathExtension.lowercased() == "json"
        }
        return trimmedURL.lowercased().hasSuffix(".json")
    }

    private var addSection: some View {
        Section {
            TextField("标题（可选）", text: $inputTitle)

            TextField("输入地址", text: $inputURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)

            Button {
                handleAdd()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppConstants.Colors.success.gradient)
                    }
                    Text("添加")
                }
            }
            .disabled(trimmedURL.isEmpty || isProcessing)

            if let error = pluginSourceManager.errorMessage {
                PluginSourceErrorCard(title: "插件源异常", message: error)
            }
        } header: {
            Text("添加视频或订阅")
        } footer: {
            Text("输入视频地址添加到收藏，可在收藏页直接播放")
        }
    }

    private func handleAdd() {
        let url = trimmedURL
        let title = inputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldTreatAsSubscription = isSubscriptionURL
        guard !url.isEmpty else { return }

        isProcessing = true
        Task {
            if shouldTreatAsSubscription {
                let addedURLs = await pluginSourceManager.addSourceFromInput(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    isProcessing = false
                    onOpenPluginSources(addedURLs)
                    return
                }
            } else {
                let addedURLs = await pluginSourceManager.addSourceWithKeyResolution(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    isProcessing = false
                    onOpenPluginSources(addedURLs)
                    return
                } else if pluginSourceManager.errorMessage == nil {
                    await bookmarkService.add(title: title.isEmpty ? url : title, url: url)
                    inputURL = ""
                    inputTitle = ""
                }
            }
            isProcessing = false
        }
    }

}
