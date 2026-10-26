//
//  OpenSourceListView.swift
//  AngelLiveMacOS
//
//  Created by Claude on 12/3/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct OpenSourceListView: View {
    var usesSettingsLayout = false
    @State private var acknowList: AcknowList? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                if usesSettingsLayout {
                    ProgressView("正在加载开源许可…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    loadingStateView
                }
            } else if let errorMsg = errorMessage {
                ErrorView(
                    title: "无法加载开源许可",
                    message: errorMsg,
                    showRetry: true,
                    onRetry: {
                        loadAcknowledgements()
                    }
                )
            } else if let list = acknowList {
                if usesSettingsLayout {
                    MacSettingsAcknowledgementList(list: list)
                } else {
                    AcknowListSwiftUIView(acknowList: list)
                }
            } else {
                ErrorView.empty(
                    title: "暂无开源许可信息",
                    message: "当前没有可展示的依赖许可内容。",
                    symbolName: "doc.text",
                    tint: .secondary
                )
            }
        }
        .navigationTitle("开源许可")
        .macSettingsPage("开源许可")
        .task {
            loadAcknowledgements()
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: 16) {
            PanelHintCard(
                title: "正在整理开源许可",
                message: "稍后会列出当前构建包含的第三方依赖与授权信息，方便你快速核对来源。",
                systemImage: "doc.text.magnifyingglass",
                tint: .blue
            )

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在解析 Package.resolved")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadAcknowledgements() {
        isLoading = true
        errorMessage = nil

        // 尝试从 Bundle 中加载 Package.resolved 文件
        guard let url = Bundle.main.url(forResource: "Package", withExtension: "resolved") else {
            errorMessage = "找不到 Package.resolved 文件"
            isLoading = false
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = AcknowPackageDecoder()
            let list = try decoder.decode(from: data)
            acknowList = list
            isLoading = false
        } catch {
            errorMessage = "解析失败: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

private struct MacSettingsAcknowledgementList: View {
    let list: AcknowList

    var body: some View {
        Form {
            Section {
                ForEach(list.acknowledgements) { acknowledgement in
                    NavigationLink {
                        MacSettingsLicenseDetail(acknowledgement: acknowledgement)
                    } label: {
                        PanelNavigationRow(
                            title: acknowledgement.title,
                            subtitle: acknowledgement.license,
                            showsChevron: false
                        ) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(list.headerText ?? "第三方组件")
            } footer: {
                if let footer = list.footerText {
                    Text(footer)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MacSettingsLicenseDetail: View {
    let acknowledgement: Acknow

    private enum Phase {
        case loading
        case loaded(String)
        case unavailable
        case failed(String)
    }

    @State private var phase = Phase.loading
    @State private var request: URLSessionDataTask?
    @State private var requestGeneration = UUID()

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("正在加载许可正文…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let text):
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 20)
                }
            case .unavailable:
                ContentUnavailableView {
                    Label("暂无许可正文", systemImage: "doc.text")
                } description: {
                    Text(acknowledgement.repository == nil
                         ? "此组件没有提供许可正文或项目地址。"
                         : "可在项目仓库中查看此组件的许可信息。")
                } actions: {
                    if let repository = acknowledgement.repository {
                        Link("打开项目仓库", destination: repository)
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("无法加载许可", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试", action: loadLicense)
                    if let repository = acknowledgement.repository {
                        Link("打开项目仓库", destination: repository)
                    }
                }
            }
        }
        .navigationTitle(acknowledgement.title)
        .macSettingsPage(acknowledgement.title, showsBackButton: true)
        .onAppear {
            if case .loaded = phase { return }
            loadLicense()
        }
        .onDisappear(perform: cancelRequest)
    }

    private func loadLicense() {
        cancelRequest()
        if let text = acknowledgement.text {
            phase = .loaded(text)
            return
        }
        guard let repository = acknowledgement.repository,
              GitHubAPI.isGitHubRepository(repository) else {
            phase = .unavailable
            return
        }

        phase = .loading
        let generation = requestGeneration
        request = GitHubAPI.getLicense(for: repository) { result in
            // AcknowList documents and implements delivery on the main queue.
            MainActor.assumeIsolated {
                guard requestGeneration == generation else { return }
                request = nil
                switch result {
                case .success(let text):
                    phase = .loaded(text)
                case .failure(let error):
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func cancelRequest() {
        requestGeneration = UUID()
        request?.cancel()
        request = nil
    }
}

#Preview {
    OpenSourceListView()
}
