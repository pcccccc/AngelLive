//
//  AboutUSView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct AboutUSView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.xl) {
                // 应用图标和名称
                VStack(spacing: AppConstants.Spacing.md) {
                    Image("icon")
                        .resizable()
                        .frame(width: 120, height: 120)
                        .cornerRadius(AppConstants.CornerRadius.xl)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                    Text("AngelLive")
                        .font(.title.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("版本 \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .padding(.top, AppConstants.Spacing.xl)

                // 项目描述
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("关于 AngelLive")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("一个简洁、优雅的多平台直播聚合应用，支持哔哩哔哩、斗鱼、虎牙等多个直播平台。")
                        .font(.body)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 项目地址
                VStack(spacing: AppConstants.Spacing.md) {
                    Text("项目地址 & 问题反馈")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: AppConstants.Spacing.lg) {
                        // GitHub 二维码
                        VStack(spacing: AppConstants.Spacing.sm) {
                            Image("qrcode-github")
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 140, height: 140)
                                .background(Color.white)
                                .cornerRadius(AppConstants.CornerRadius.md)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)

                            Text("GitHub")
                                .font(.caption.bold())
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Button {
                                if let url = URL(string: "https://github.com/pcccccc/AngelLive") {
                                    openURL(url)
                                }
                            } label: {
                                Text("访问项目")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.link)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Telegram 二维码
                        VStack(spacing: AppConstants.Spacing.sm) {
                            Image("qrcode-telegram")
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 140, height: 140)
                                .background(Color.white)
                                .cornerRadius(AppConstants.CornerRadius.md)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)

                            Text("Telegram")
                                .font(.caption.bold())
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Button {
                                if let url = URL(string: "https://t.me/SimpleLiveTV") {
                                    openURL(url)
                                }
                            } label: {
                                Text("加入群组")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.link)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 免责声明
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("免责声明")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("本软件完全免费，仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关！")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 版权信息
                VStack(spacing: AppConstants.Spacing.xs) {
                    Text("© 2024 AngelLive")
                        .font(.caption2)
                        .foregroundStyle(AppConstants.Colors.secondaryText)

                    Text("Made with ♥ by the community")
                        .font(.caption2)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .padding(.vertical, AppConstants.Spacing.lg)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Feature Row Component

private struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: AppConstants.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppConstants.Colors.link.gradient)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
    }
}
