//
//  AboutUSView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/27.
//

import SwiftUI

struct AboutUSView: View {
    @Environment(AppState.self) private var appViewModel

    private var presentsFullUI: Bool {
        appViewModel.pluginAvailability.hasAvailablePlugins
    }

    var body: some View {
        if presentsFullUI {
            TVFullUIAboutView()
        } else {
            legacyAboutView
        }
    }

    private var legacyAboutView: some View {
        VStack {
            HStack(spacing: 15) {
                Text("Angel Live")
                    .font(.title)
                Text("v: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    .padding(.top, 30)
            }
            Spacer()
            Text("项目地址&问题反馈:")
            HStack {
                VStack {
                    Text("Github:")
                    Image("qrcode-github")
                }
                VStack {
                    Text("Telegram:")
                    Image("qrcode-telegram")
                }
            }
            .padding(.top, 20)
            Spacer()
            Text("本软件完全免费，仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关！")
        }
    }
}

private struct TVFullUIAboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image("about-collaboration")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 20))

                Text("AngelLive x 小声逼逼")
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("v: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    .font(.subheadline)
            }

            Spacer(minLength: 8)

            Text("交流与反馈")
                .font(.headline)

            HStack(alignment: .top, spacing: 40) {
                TVAboutQRCodeCard(imageName: "qrcode-telegram", title: "Telegram")
                TVAboutQRCodeCard(imageName: "qrcode-community", title: "小声逼逼")
            }
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text("GitHub 项目与反馈")
                    .font(.caption)

                Text("github.com/pcccccc/AngelLive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 8)

            Text("本软件完全免费，仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关！")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

private struct TVAboutQRCodeCard: View {
    let imageName: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image(imageName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(12)
                .frame(width: 250, height: 250)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("二维码")

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AboutUSView()
        .environment(AppState())
}
