//
//  SettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore

struct SettingView: View {
    @StateObject private var settingStore = SettingStore()
    @State private var cloudKitReady = false
    @State private var cloudKitStateString = "检查中..."

    var body: some View {
        NavigationStack {
            List {
                // 账号设置
                Section {
                    NavigationLink {
                        BilibiliWebLoginView()
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
                                .foregroundStyle(settingStore.bilibiliCookie.isEmpty ? AppConstants.Colors.secondaryText : AppConstants.Colors.success)
                        }
                    }
                } header: {
                    Text("账号")
                }

                // 应用设置
                Section {
                    NavigationLink {
                        GeneralSettingView()
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
                        DanmuSettingView()
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

                // 数据管理
                Section {
                    NavigationLink {
                        if cloudKitReady {
                            SyncView()
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
                        HistoryListView()
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

                // tvOS 同步
                Section {
                    NavigationLink {
                        TVOSSyncView()
                    } label: {
                        HStack {
                            Image(systemName: "appletv.fill")
                                .font(.title3)
                                .foregroundStyle(Color.purple.gradient)
                                .frame(width: 32)

                            Text("同步到 tvOS")

                            Spacer()

                            Text("Bilibili Cookie")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                    }
                } header: {
                    Text("tvOS")
                } footer: {
                    Text("将 Bilibili Cookie 同步到 Apple TV，支持局域网自动发现或扫描二维码。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                // 关于
                Section {
                    NavigationLink {
                        OpenSourceListView()
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
                        AboutUSView()
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
            }
            .listStyle(.insetGrouped)
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

// MARK: - CloudKit Status View

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
