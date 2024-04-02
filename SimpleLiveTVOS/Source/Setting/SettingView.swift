//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI


struct SettingView: View {
    
    let titles = ["哔哩哔哩登录", "弹幕设置", "数据同步", "历史记录", "开源许可", "关于"]
    @State var currentTitle: String?
    @State var isLogin = false
    @State var isPushed = false
    @StateObject var danmuSettingModel = DanmuSettingStore()
    @StateObject var settingStore = SettingStore()
    @EnvironmentObject var favoriteStore: FavoriteStore
    
    var body: some View {
        GeometryReader { geometry in
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
                .frame(width: geometry.size.width / 2)
                VStack(spacing: 45) {
                    ForEach(titles, id: \.self) { title in
                        Button(action: {
                            currentTitle = title
                        }, label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(title)
                                Spacer()
                                if title == "哔哩哔哩登录" {
                                    Text(settingStore.bilibiliCookie.count == 0 ? "未登录" : "已登录")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.gray)
                                }
                            }
                            .onAppear {
                            }
                        })
                        .frame(height: 40)
                        .fullScreenCover(item: $currentTitle) { title in
                            if title == "哔哩哔哩登录" {
                                BilibiliLoginView()
                                    .background(.ultraThickMaterial)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .environmentObject(settingStore)
                            }else if title == "弹幕设置" {
                                DanmuSettingView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThickMaterial)
                                    .environmentObject(danmuSettingModel)
                            }else if title == "历史记录" {
                                HistoryListView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThickMaterial)
                            }else if title == "开源许可" {
                                OpenSourceListView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThickMaterial)
                            }else if title == "数据同步" {
                                SyncView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThickMaterial)
                                    .environmentObject(favoriteStore)
                            }else {
                                AboutUSView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThickMaterial)
                            }
                        }
                        
                    }
                    Spacer()
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
                .padding(.top, 50)
            }
        }
    }
    

}

#Preview {
    SettingView()
}
