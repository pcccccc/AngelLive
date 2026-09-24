//
//  AboutUSView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct AboutUSView: View {
    private static let qrGridColumns = [
        GridItem(.adaptive(minimum: 140), spacing: AppConstants.Spacing.lg)
    ]

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
                    Image("about-collaboration")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .cornerRadius(AppConstants.CornerRadius.xl)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                    Text("AngelLive x 小声逼逼")
                        .font(.title.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    Text("版本 \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .padding(.top, AppConstants.Spacing.xl)

                // 交流与反馈
                VStack(spacing: AppConstants.Spacing.md) {
                    Text("交流与反馈")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: Self.qrGridColumns, spacing: AppConstants.Spacing.lg) {
                        AboutQRCodeCard(
                            imageName: "qrcode-telegram",
                            title: "Telegram",
                            buttonTitle: "加入群组",
                            url: URL(string: "https://t.me/angelliveapp")!
                        )

                        AboutQRCodeCard(
                            imageName: "qrcode-community",
                            title: "小声逼逼",
                            buttonTitle: "访问小声逼逼",
                            url: URL(string: "https://t.me/me888888888888/")!
                        )
                    }

                    Link(destination: URL(string: "https://github.com/pcccccc/AngelLive")!) {
                        Label("GitHub 项目与反馈", systemImage: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.link)
                            .frame(maxWidth: .infinity, minHeight: 44)
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
                    Text("© \(Calendar.current.component(.year, from: Date())) AngelLive")
                        .font(.caption2)
                        .foregroundStyle(AppConstants.Colors.secondaryText)

                    Text("Made with LaoPC by the community")
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

private struct AboutQRCodeCard: View {
    @Environment(\.openURL) private var openURL

    let imageName: String
    let title: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let url: URL

    var body: some View {
        VStack(spacing: AppConstants.Spacing.sm) {
            Image(imageName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 140, height: 140)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.md))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                .accessibilityLabel("二维码")

            Text(title)
                .font(.caption.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(url)
            } label: {
                Text(buttonTitle)
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.link)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
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
