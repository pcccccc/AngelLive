//
//  OpenSourceListView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
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
                VStack(spacing: AppConstants.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("加载开源许可...")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = errorMessage {
                VStack(spacing: AppConstants.Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(AppConstants.Colors.warning.gradient)

                    Text("无法加载开源许可")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let list = acknowList {
                AcknowListSwiftUIView(acknowList: list)
            } else {
                VStack(spacing: AppConstants.Spacing.lg) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(AppConstants.Colors.secondaryText.opacity(0.5))

                    Text("暂无开源许可信息")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
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
