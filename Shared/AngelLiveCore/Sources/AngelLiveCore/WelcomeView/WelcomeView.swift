//
//  WelcomeView.swift
//  AngelLive
//
//  Created by pangchong on 11/7/25.
//

import SwiftUI
#if !os(macOS)
import SharedAssets
#else
import AppKit
#endif

public struct WelcomeView: View {
    public var onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        WelcomePageView(
            tint: .accentColor,
            title: "欢迎使用 AngelLive"
        ) {
            // App 图标
#if os(macOS)
            Image(nsImage: NSImage(named: "logoicon") ?? NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 25))
#else
            Image("AppIcon")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 25))
#endif
           
            
        } cards: {
            WelcomeCard(
                symbol: "rectangle.stack.fill",
                title: "多平台支持",
                subTitle: "支持斗鱼、B站、虎牙等主流直播平台，一个应用畅享所有内容"
            )
            WelcomeCard(
                symbol: "play.circle.fill",
                title: "流畅播放",
                subTitle: "采用先进的播放技术，提供高清流畅的观看体验"
            )
            WelcomeCard(
                symbol: "message.fill",
                title: "实时弹幕",
                subTitle: "支持主流平台弹幕展示，感受热烈的直播氛围"
            )
            WelcomeCard(
                symbol: "star.fill",
                title: "便捷收藏",
                subTitle: "通过iCloud轻松收藏喜欢的直播间，并同步到所有设备"
            )
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("开源、免费、请勿在任何平台购买此APP")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .padding(.vertical, 15)
        } onContinue: {
            onContinue()
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
