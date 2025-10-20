//
//  SettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct SettingView: View {
    @StateObject private var settingStore = SettingStore()
    @State private var cloudKitReady = false
    @State private var cloudKitStateString = "检查中..."

    var body: some View {
        NavigationStack {
            Form {
                // 账号设置
                Section {
                    NavigationLink {
                        BilibiliLoginViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.link.gradient)
                                .frame(width: 32)

                            Text("哔哩哔哩登录")

                            Spacer()

                            Text(settingStore.bilibiliCookie.isEmpty ? "未登录" : "已登录")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                    }
                } header: {
                    Text("账号")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                        .fill(AppConstants.Colors.materialBackground)
                )

                // 应用设置
                Section {
                    NavigationLink {
                        GeneralSettingViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(Color.gray.gradient)
                                .frame(width: 32)
                            Text("通用设置")
                        }
                    }

                    NavigationLink {
                        DanmuSettingViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.success.gradient)
                                .frame(width: 32)
                            Text("弹幕设置")
                        }
                    }
                } header: {
                    Text("设置")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                        .fill(AppConstants.Colors.materialBackground)
                )

                // 数据管理
                Section {
                    NavigationLink {
                        if cloudKitReady {
                            SyncViewiOS()
                        } else {
                            CloudKitStatusView(stateString: cloudKitStateString)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "icloud.fill")
                                .font(.title3)
                                .foregroundStyle(Color.cyan.gradient)
                                .frame(width: 32)

                            Text("数据同步")

                            Spacer()

                            Text(cloudKitReady ? "iCloud 就绪" : "状态异常")
                                .font(.caption)
                                .foregroundStyle(cloudKitReady ? AppConstants.Colors.success : AppConstants.Colors.error)
                        }
                    }

                    NavigationLink {
                        HistoryListViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "clock.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.warning.gradient)
                                .frame(width: 32)
                            Text("历史记录")
                        }
                    }
                } header: {
                    Text("数据")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                        .fill(AppConstants.Colors.materialBackground)
                )

                // 关于
                Section {
                    NavigationLink {
                        OpenSourceListViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.title3)
                                .foregroundStyle(Color.purple.gradient)
                                .frame(width: 32)
                            Text("开源许可")
                        }
                    }

                    NavigationLink {
                        AboutUSViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.indigo.gradient)
                                .frame(width: 32)
                            Text("关于")
                        }
                    }
                } header: {
                    Text("信息")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                        .fill(AppConstants.Colors.materialBackground)
                )
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await checkCloudKitStatus()
            }
        }
    }

    private func checkCloudKitStatus() async {
        cloudKitStateString = await FavoriteService.getCloudState()
        cloudKitReady = cloudKitStateString == "正常"
    }
}

// MARK: - Placeholder Views
struct BilibiliLoginViewiOS: View {
    var body: some View {
        Text("哔哩哔哩登录")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("哔哩哔哩")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct GeneralSettingViewiOS: View {
    var body: some View {
        Text("通用设置")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("通用")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct DanmuSettingViewiOS: View {
    var body: some View {
        Text("弹幕设置")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("弹幕")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct SyncViewiOS: View {
    var body: some View {
        Text("数据同步")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("同步")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryListViewiOS: View {
    var body: some View {
        Text("历史记录")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct OpenSourceListViewiOS: View {
    var body: some View {
        Text("开源许可")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("许可")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutUSViewiOS: View {
    var body: some View {
        Text("关于我们")
            .font(.title)
            .foregroundStyle(AppConstants.Colors.primaryText)
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct CloudKitStatusView: View {
    let stateString: String

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xl) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 60))
                .foregroundStyle(AppConstants.Colors.warning)

            Text("iCloud 状态异常")
                .font(.title2.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)

            Text(stateString)
                .font(.body)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .navigationTitle("同步")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingView()
}
