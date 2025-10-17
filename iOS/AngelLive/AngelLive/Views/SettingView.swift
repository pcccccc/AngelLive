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
    @State private var settingStore = SettingStore()
    @State private var cloudKitReady = false
    @State private var cloudKitStateString = "检查中..."

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Form {
                    // 应用信息
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                if let image = UIImage(named: "icon") {
                                    Image(uiImage: image)
                                        .resizable()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .shadow(radius: 10)
                                } else {
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 80))
                                        .foregroundStyle(.blue)
                                }

                                Text("AngelLive")
                                    .font(.title2.bold())

                                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                                    Text("Version \(version) (\(build))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)

                    // 账号设置
                    Section {
                        NavigationLink {
                            BilibiliLoginViewiOS()
                        } label: {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue.gradient)
                                    .frame(width: 32)

                                Text("哔哩哔哩登录")

                                Spacer()

                                Text(settingStore.bilibiliCookie.isEmpty ? "未登录" : "已登录")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("账号")
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )

                    // 应用设置
                    Section {
                        NavigationLink {
                            GeneralSettingViewiOS()
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                    .font(.title3)
                                    .foregroundStyle(.gray.gradient)
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
                                    .foregroundStyle(.green.gradient)
                                    .frame(width: 32)
                                Text("弹幕设置")
                            }
                        }
                    } header: {
                        Text("设置")
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
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
                                    .foregroundStyle(.cyan.gradient)
                                    .frame(width: 32)

                                Text("数据同步")

                                Spacer()

                                Text(cloudKitReady ? "iCloud 就绪" : "状态异常")
                                    .font(.caption)
                                    .foregroundStyle(cloudKitReady ? .green : .red)
                            }
                        }

                        NavigationLink {
                            HistoryListViewiOS()
                        } label: {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .font(.title3)
                                    .foregroundStyle(.orange.gradient)
                                    .frame(width: 32)
                                Text("历史记录")
                            }
                        }
                    } header: {
                        Text("数据")
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )

                    // 关于
                    Section {
                        NavigationLink {
                            OpenSourceListViewiOS()
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.title3)
                                    .foregroundStyle(.purple.gradient)
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
                                    .foregroundStyle(.indigo.gradient)
                                    .frame(width: 32)
                                Text("关于")
                            }
                        }
                    } header: {
                        Text("信息")
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                }
                .scrollContentBackground(.hidden)
            }
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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("哔哩哔哩登录")
                .font(.title)
        }
        .navigationTitle("哔哩哔哩")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GeneralSettingViewiOS: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("通用设置")
                .font(.title)
        }
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DanmuSettingViewiOS: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("弹幕设置")
                .font(.title)
        }
        .navigationTitle("弹幕")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SyncViewiOS: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("数据同步")
                .font(.title)
        }
        .navigationTitle("同步")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryListViewiOS: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("历史记录")
                .font(.title)
        }
        .navigationTitle("历史")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OpenSourceListViewiOS: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("开源许可")
                .font(.title)
        }
        .navigationTitle("许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutUSViewiOS: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("关于我们")
                .font(.title)
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CloudKitStatusView: View {
    let stateString: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text("iCloud 状态异常")
                    .font(.title2.bold())

                Text(stateString)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("同步")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingView()
}
