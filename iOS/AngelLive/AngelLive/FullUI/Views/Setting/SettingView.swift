//
//  SettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import Kingfisher

struct SettingView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var generalSetting = GeneralSettingModel()
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false
    @State private var supportDiagnosticsService = SupportDiagnosticsService.shared
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.supportDiagnosticsEnabled) private var supportDiagnosticsEnabled

    var body: some View {
        @Bindable var setting = generalSetting
        NavigationStack {
            List {
                // 账号设置
                if pluginAvailability.hasAvailablePlugins,
                   !pluginAvailability.loginRequiredInstalledPluginIds.isEmpty {
                    Section {
                        NavigationLink {
                            PlatformAccountLoginView()
                                .fullUITabBarHidden()
                                .onAppear {
                                    guard supportDiagnosticsEnabled else { return }
                                    supportDiagnosticsService.recordAction(.openedAccountManagement)
                                }
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.title3)
                                    .foregroundStyle(AppConstants.Colors.link.gradient)
                                .frame(width: 24, height: 24)
                                .frame(width: 32)

                                Text("平台账号登录")

                                Spacer()

                                Text("多平台")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        }
                    } header: {
                        Text("账号")
                    }
                }

                // 插件管理
                if pluginAvailability.hasAvailablePlugins {
                    Section {
                        NavigationLink {
                            PluginManagementView()
                                .fullUITabBarHidden()
                                .onAppear {
                                    guard supportDiagnosticsEnabled else { return }
                                    supportDiagnosticsService.recordAction(.openedPluginManagement)
                                }
                        } label: {
                            HStack {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.orange.gradient)
                                    .frame(width: 32)

                                Text("插件管理")

                                Spacer()

                                Text("\(pluginAvailability.installedPluginIds.count) 个已安装")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        }
                    } header: {
                        Text("插件")
                    }
                }

                // 应用设置
                Section {
                    NavigationLink {
                        GeneralSettingView()
                            .fullUITabBarHidden()
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
                            .fullUITabBarHidden()
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

                // 数据同步（有插件时可用）
                if pluginAvailability.hasAvailablePlugins {
                    Section {
                        NavigationLink {
                            SyncView()
                                .fullUITabBarHidden()
                        } label: {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.cyan.gradient)
                                    .frame(width: 32)

                                Text("数据同步")
                            }
                        }
                    } header: {
                        Text("同步")
                    } footer: {
                        Text("使用 iCloud 同步收藏和平台账号，也可将已登录的平台账号同步到 Apple TV。")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }

                // 历史记录（始终可用）
                Section {
                    NavigationLink {
                        HistoryListView()
                            .fullUITabBarHidden()
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
                    Text("记录")
                }

                // 开发者
                Section {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .font(.title3)
                            .foregroundStyle(Color.red.gradient)
                            .frame(width: 32)

                        Toggle("开发者模式", isOn: $setting.developerModeEnabled)
                    }
                } header: {
                    Text("开发者")
                } footer: {
                    Text("开启后显示浮动调试按钮，可查看插件运行日志。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                // 存储
                Section {
                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .font(.title3)
                                .foregroundStyle(Color.red.gradient)
                                .frame(width: 32)

                            Text("清除缓存")
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Spacer()

                            if isClearingCache {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("清理中...")
                                        .font(.subheadline)
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }
                            } else {
                                Text(cacheSizeText)
                                    .font(.subheadline)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        }
                    }
                    .disabled(isClearingCache)
                } header: {
                    Text("存储")
                } footer: {
                    Text("清理图片缓存、插件旧版本及网络临时文件。保留收藏、登录与已激活的插件版本。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                // 帮助（仅 FullUI 根入口显式启用）
                if supportDiagnosticsEnabled {
                    Section {
                        NavigationLink {
                            SupportDiagnosticsView()
                                .fullUITabBarHidden()
                        } label: {
                            HStack {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.title3)
                                    .foregroundStyle(Color.orange.gradient)
                                    .frame(width: 32)

                                Text("问题诊断与反馈")

                                Spacer()

                                if supportDiagnosticsService.isRecording {
                                    Label("录制中", systemImage: "record.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                    } header: {
                        Text("帮助")
                    }
                }

                // 关于
                Section {
                    NavigationLink {
                        OpenSourceListView()
                            .fullUITabBarHidden()
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
                            .fullUITabBarHidden()
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
                await refreshCacheSize()
            }
            .alert(
                "确认清除所有缓存?",
                isPresented: $showClearCacheConfirm
            ) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    Task { await clearAllCaches() }
                }
            } message: {
                Text("将清理图片缓存、插件旧版本及网络临时文件,不影响收藏与登录状态。")
            }
        }
    }

    private func refreshCacheSize() async {
        let total = await CacheMaintenanceService.currentTotalSize(imageCache: Self.kingfisherBridge)
        await MainActor.run {
            guard !isClearingCache else { return }
            cacheSizeText = CacheMaintenanceService.formatBytes(total)
        }
    }

    private func clearAllCaches() async {
        await MainActor.run { isClearingCache = true }
        let total = await CacheMaintenanceService.purgeAllAndAwaitSettled(
            imageCache: Self.kingfisherBridge
        )
        await MainActor.run {
            cacheSizeText = CacheMaintenanceService.formatBytes(total)
            isClearingCache = false
        }
    }

    private static let kingfisherBridge = CacheMaintenanceService.ImageCacheBridge(
        measureBytes: {
            await withCheckedContinuation { (cont: CheckedContinuation<Int64, Never>) in
                ImageCache.default.calculateDiskStorageSize { result in
                    cont.resume(returning: (try? result.get()).map(Int64.init) ?? 0)
                }
            }
        },
        clearDisk: {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ImageCache.default.clearDiskCache { cont.resume() }
            }
        },
        clearMemory: {
            ImageCache.default.clearMemoryCache()
        }
    )
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
