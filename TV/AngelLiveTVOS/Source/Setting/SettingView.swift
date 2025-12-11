//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI
import AngelLiveCore

struct SettingView: View {

    @State var titles = ["账号管理", "通用设置", "弹幕设置", "数据同步", "历史记录", "开源许可", "关于"]
    @State var currentTitle: String?
    @State var isLogin = false
    @State var isPushed = false
    @StateObject var settingStore = SettingStore()
    @Environment(AppState.self) var appViewModel
    
    
    var body: some View {
        GeometryReader { geometry in
            HStack {
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 500, height: 500)
                        .cornerRadius(50)
                    Text("Angel Live")
                        .font(.headline)
                        .padding(.top, 20)
                    Text("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                        .font(.subheadline)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)
                VStack(spacing: 15) {
                    Spacer()
                    ForEach(titles, id: \.self) { title in
                        NavigationLink {
                            if title == "账号管理" {
                                AccountManagementView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .environmentObject(settingStore)
                                    .environment(appViewModel)
                            } else if title == "弹幕设置" {
                                DanmuSettingView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.thinMaterial)
                                    .environment(appViewModel)
                            }else if title == "通用设置" {
                                GeneralSettingView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.thinMaterial)
                                    .environment(appViewModel)
                            }else if title == "历史记录" {
                                HistoryListView(appViewModel: appViewModel)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.thinMaterial)
                            }else if title == "开源许可" {
                                OpenSourceListView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.thinMaterial)
                            }else if title == "数据同步" {
                                if appViewModel.favoriteViewModel.cloudKitReady == true {
                                    SyncView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.thinMaterial)
                                        .environment(appViewModel)
                                }else {
                                    Text("请通过收藏页面检查iCloud状态是否正常")
                                }
                            }else {
                                AboutUSView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.thinMaterial)
                            }
                        } label: {
                            Text(title)
                            Spacer()
                            if title == "账号管理" {
                                Text(BilibiliCookieSyncService.shared.loginStatusDescription)
                                    .font(.system(size: 30))
                                    .foregroundStyle(.gray)
                            } else if title == "数据同步" {
                                Text(appViewModel.favoriteViewModel.cloudKitReady == true ? "iCloud就绪" : "iCloud状态异常")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.gray)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 200)
                }
                .frame(width: geometry.size.width / 2 - 50)
                .padding(.trailing, 50)
            }
        }
    }
    
    
}

#Preview {
    SettingView()
}
