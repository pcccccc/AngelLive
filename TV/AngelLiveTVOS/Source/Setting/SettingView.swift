//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI
import AngelLiveCore
import Kingfisher

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct SettingView: View {

    @State var titles = ["账号管理", "插件管理", "通用设置", "弹幕设置", "数据同步", "历史记录", "开源许可", "清除缓存", "关于&问题反馈"]
    @State private var selectedIndex: Int? = nil
    @State private var fullScreenIndex: Int? = nil
    @StateObject var settingStore = SettingStore()
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @Environment(AppState.self) var appViewModel
    @FocusState private var focusedIndex: Int?
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false

    // 需要在右侧半屏显示的页面索引
    private var halfScreenIndices: Set<Int> { [0, 2, 3, 4] } // 账号管理、通用设置、弹幕设置、数据同步

    private var canEnterPluginManagement: Bool {
        appViewModel.pluginAvailability.hasAvailablePlugins ||
        !appViewModel.pluginSourceManager.sourceURLs.isEmpty ||
        !appViewModel.pluginSourceManager.remotePlugins.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧：Logo 区域
                if selectedIndex == nil || (selectedIndex != nil && halfScreenIndices.contains(selectedIndex!)) {
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
                }

                // 右侧：内容区域
                ZStack {
                    // 菜单列表
                    if selectedIndex == nil {
                        menuListView
                            .frame(width: geometry.size.width / 2 - 50)
                            .transition(.opacity)
                    }

                    // 半屏子页面内容（账号管理、通用设置、弹幕设置）
                    if let index = selectedIndex, halfScreenIndices.contains(index) {
                        halfScreenContentView(for: index)
                            .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                .padding(.trailing, 50)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedIndex)
        .fullScreenCover(item: $fullScreenIndex) { index in
            fullScreenContentView(for: index)
        }
        .onChange(of: appViewModel.pluginAvailability.hasAvailablePlugins) { _, hasPlugins in
            guard !hasPlugins else { return }
            if selectedIndex == 0 {
                selectedIndex = nil
            }
            if fullScreenIndex == 1 && !canEnterPluginManagement {
                fullScreenIndex = nil
            }
            // 数据同步现在走半屏(selectedIndex),失去插件后跟着关闭
            if selectedIndex == 4 {
                selectedIndex = nil
            }
        }
        .onChange(of: appViewModel.pluginAvailability.loginRequiredInstalledPluginIds.isEmpty) { _, isEmpty in
            // 已安装插件全部不需要登录时,关闭已打开的账号管理
            if isEmpty, selectedIndex == 0 {
                selectedIndex = nil
            }
        }
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

    // MARK: - 菜单列表
    private var menuListView: some View {
        VStack(spacing: 15) {
            ForEach(titles.indices, id: \.self) { index in
                if shouldShowMenuItem(index) {
                    Button {
                        if index == 7 {
                            showClearCacheConfirm = true
                        } else if halfScreenIndices.contains(index) {
                            selectedIndex = index
                        } else {
                            fullScreenIndex = index
                        }
                    } label: {
                        HStack(spacing: 15) {
                            Text(titles[index])
                                .foregroundColor(.primary)
                            Spacer()
                            menuTrailingStatus(for: index)
                            if index != 7 {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .focused($focusedIndex, equals: index)
                    .disabled(index == 7 && isClearingCache)
                }
            }
        }
    }

    /// 菜单行尾部状态文案。抽成独立 @ViewBuilder,避免 menuListView 整体表达式过大导致编译器 type-check 超时。
    @ViewBuilder
    private func menuTrailingStatus(for index: Int) -> some View {
        if index == 0 {
            Text(syncService.loggedInByPluginId.values.contains(true) ? "已登录" : "未登录")
                .font(.system(size: 30))
                .foregroundStyle(.gray)
        } else if index == 4 {
            // 三端统一文案,见 AppFavoriteModel.syncStatusDisplayText。
            Text(appViewModel.favoriteViewModel.syncStatusDisplayText)
                .font(.system(size: 30))
                .foregroundStyle(.gray)
        } else if index == 7 {
            if isClearingCache {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("清理中...")
                        .font(.system(size: 30))
                        .foregroundStyle(.gray)
                }
            } else {
                Text(cacheSizeText)
                    .font(.system(size: 30))
                    .foregroundStyle(.gray)
            }
        }
    }

    private func shouldShowMenuItem(_ index: Int) -> Bool {
        if appViewModel.pluginAvailability.hasAvailablePlugins {
            // 已安装插件均无登录入口时,隐藏账号管理(0)
            if index == 0 {
                return !appViewModel.pluginAvailability.loginRequiredInstalledPluginIds.isEmpty
            }
            return true
        }
        if index == 1 {
            return canEnterPluginManagement
        }
        // 无本地插件时隐藏：账号管理(0)、数据同步(4)
        return index != 0 && index != 4
    }

    // MARK: - 半屏内容视图（账号管理、通用设置、弹幕设置）
    @ViewBuilder
    private func halfScreenContentView(for index: Int) -> some View {
        switch index {
        case 0: // 账号管理
            AccountManagementView()
                .environmentObject(settingStore)
                .environment(appViewModel)
                .environment(appViewModel.pluginAvailability)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 2: // 通用设置
            GeneralSettingView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 3: // 弹幕设置
            DanmuSettingMainView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 4: // 数据同步
            // 三端对齐:聚合 iCloud 同步 / 局域网同步 / Simple Live 老扫码同步入口。
            SyncManagementView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        default:
            EmptyView()
        }
    }

    // MARK: - 全屏内容视图（插件管理、历史记录、开源许可、关于）
    @ViewBuilder
    private func fullScreenContentView(for index: Int) -> some View {
        switch index {
        case 1: // 插件管理
            TVPluginManagementView(
                pluginSourceManager: appViewModel.pluginSourceManager,
                pluginAvailability: appViewModel.pluginAvailability
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        case 5: // 历史记录
            HistoryListView(appViewModel: appViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        case 6: // 开源许可
            NavigationStack {
                OpenSourceListView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .onExitCommand {
                fullScreenIndex = nil
            }
        case 8: // 关于
            AboutUSView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        default:
            EmptyView()
        }
    }

    // MARK: - 缓存维护
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
            imageCache: Self.kingfisherBridge,
            // tvOS 清理后立即同步到 App Group,让 TopShelf 看到的也是清理后的状态
            extraWork: { PluginAppGroupSync.syncToAppGroup() }
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

#Preview {
    SettingView()
}
