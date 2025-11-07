//
//  WelcomeView.swift
//  AngelLive
//
//  Created by pangchong on 11/7/25.
//

import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        WelcomePageView(
            tint: .blue,
            title: "欢迎使用 SimpleLive"
        ) {
            // App 图标
            Image(systemName: "play.tv.fill")
                .font(.system(size: 50))
                .frame(width: 100, height: 100)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 25)
                )
                .frame(height: 180)
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
                subTitle: "与主播和观众实时互动，感受热烈的直播氛围"
            )
            WelcomeCard(
                symbol: "star.fill",
                title: "便捷收藏",
                subTitle: "轻松收藏喜欢的直播间，随时回看精彩内容"
            )
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.blue)

                Text("我们注重您的观看体验和隐私保护")
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
        .presentationSizing(.page.fitted(horizontal: true, vertical: false))
}
