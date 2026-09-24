//
//  MacAboutView.swift
//  AngelLiveMacOS
//

import Foundation
import SwiftUI

struct MacAboutView: View {
    private static let telegramURL = URL(string: "https://t.me/angelliveapp")!
    private static let communityURL = URL(string: "https://t.me/me888888888888/")!
    private static let githubURL = URL(string: "https://github.com/pcccccc/AngelLive")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image("about-collaboration")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 20))
                    .accessibilityHidden(true)

                Text("AngelLive x 小声逼逼")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("版本 \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("交流与反馈")
                    .font(.headline)

                HStack(alignment: .top, spacing: 16) {
                    MacAboutQRCodeCard(
                        imageName: "qrcode-telegram",
                        title: "Telegram",
                        linkTitle: "加入群组",
                        destination: Self.telegramURL
                    )

                    MacAboutQRCodeCard(
                        imageName: "qrcode-community",
                        title: "小声逼逼",
                        linkTitle: "访问小声逼逼",
                        destination: Self.communityURL
                    )
                }
            }

            Link(destination: Self.githubURL) {
                Label("GitHub 项目与反馈", systemImage: "arrow.up.right")
                    .font(.subheadline)
                    .frame(minHeight: 24)
            }

            Text("本软件完全免费，仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关！")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 2) {
                Text("© \(currentYear) AngelLive")
                Text("Made with LaoPC by the community")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct MacAboutQRCodeCard: View {
    let imageName: String
    let title: LocalizedStringKey
    let linkTitle: LocalizedStringKey
    let destination: URL

    var body: some View {
        VStack(spacing: 6) {
            Image(imageName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 140, height: 140)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 8))

            Text(title)
                .font(.subheadline.weight(.semibold))

            Link(destination: destination) {
                Label(linkTitle, systemImage: "arrow.up.right")
                    .font(.caption)
                    .frame(minHeight: 24)
            }
        }
        .frame(width: 160)
    }
}
