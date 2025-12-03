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
    @State private var acknowList: AcknowList? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("加载开源许可...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

                    Text("无法加载开源许可")
                        .font(.headline)

                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let list = acknowList {
                AcknowListSwiftUIView(acknowList: list)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text("暂无开源许可信息")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("开源许可")
        .task {
            loadAcknowledgements()
        }
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

#Preview {
    OpenSourceListView()
}
