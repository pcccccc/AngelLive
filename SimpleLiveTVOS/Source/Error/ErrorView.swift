//
//  ErrorView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2025/2/6.
//

import SwiftUI

enum AngelLiveErrorPageType: String {
    case collect = "收藏"
    case list = "平台列表"
    case detail = "详情"
}

struct ErrorView: View {
    var body: some View {
        HStack {
            VStack {
                HStack {
                    Text("出错了")
                        .font(.title)
                        .bold()
                    Spacer()
                }
                HStack {
                    Text("错误发生在" + AngelLiveErrorPageType.collect.rawValue + "页面")
                        .font(.title2)
                        .bold()
                    Spacer()
                }
                .padding(.top, 10)
                HStack {
                    Text("错误信息:")
                        .font(.title3)
                        .bold()
                    Spacer()
                }
                .padding(.top, 10)
                HStack {
                    Text("错误信息: 我是一段很长的错误信息我是一段很长的错误信息我是一段很长的错误信息我是一段很长的错误信息我是一段很长的错误信息我是一段很长的错误信息我是一段很长的错误信息")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    
                }
                .padding(.top, 10)
                Spacer()
            }
            .padding(.top, 50)
            VStack {
                
                Image(uiImage: Common.generateQRCode(from: "1111111"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 500, height: 500)
                Text("请扫描二维码获取帮助信息")
                Spacer()
            }
            .padding(.top, 50)
        }
        .safeAreaPadding()
        .background(.thinMaterial)
    }
}

#Preview {
    ErrorView()
}
