//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI

struct SettingView: View {
    
    let titles = ["哔哩哔哩登录", "弹幕设置", "关于"]
    @State var currentTitle: String?
    @State var isLogin = false
    @State var isPushed = false
    
    var body: some View {
        HStack {
            VStack {
                Spacer()
                Image("icon")
                    .resizable()
                    .frame(width: 500, height: 500)
                Text("Simple Live for tvOS")
                    .font(.headline)
                    .padding(.top, 20)
                Text("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    .font(.subheadline)
                Spacer()
            }
            .frame(maxHeight: .infinity)
            VStack{}
                .frame(width: 50, height: .infinity)
            VStack {
                ForEach(titles, id: \.self) { title in
                    Button(action: {
                        currentTitle = title
                    }, label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title)
                            Spacer()
                            if title == "哔哩哔哩登录" {
                                Text(isLogin ? "未登录" : "已登录")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.gray)
                            }
                        }
                        .frame(width: 500, height: 45)
                        .buttonStyle(.card)
                        .onAppear {
//                            isLogin = BiliBiliCookie.cookie == ""
                        }
                    })
                    .fullScreenCover(item: $currentTitle) { title in
                        if title == "哔哩哔哩登录" {
                            BilibiliLoginView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.background)
                        }else if title == "弹幕设置" {
                            DanmuSettingView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.background)
                        }else {
                            AboutUSView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.background)
                        }
                    }
                }
            }
        }
    }
    

}

#Preview {
    SettingView()
}
