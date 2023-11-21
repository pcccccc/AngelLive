//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI

struct SettingView: View {
    
    @State var isLogin = false
    
    var body: some View {
        ScrollView(.vertical) {
            VStack {
                items
            }.padding()
        }
        .frame(width: 650)
    }
    
    var items: some View {
        ForEach(["哔哩哔哩登录","关于"], id: \.self) { title in
            NavigationLink(destination: {
                if title == "哔哩哔哩登录" {
                    BilibiliLoginView()
                }else {
                    AboutUSView()
                }
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
                .frame(width: 900, height: 80)
                .buttonStyle(.card)
                .onAppear {
                    isLogin = BiliBiliCookie.cookie == ""
                }
            })
        }
    }
}

#Preview {
    SettingView()
}
