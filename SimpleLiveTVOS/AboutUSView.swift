//
//  AboutUSView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/27.
//

import SwiftUI

struct AboutUSView: View {
    var body: some View {
        VStack {
            HStack(spacing: 15) {
                Text("Simple Live")
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

#Preview {
    AboutUSView()
}
