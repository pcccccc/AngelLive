//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import GameController
import Network
import Foundation
import Darwin
import AngelLiveDependencies
import AngelLiveCore

struct ContentView: View {
    
    var appViewModel: AppState
    var searchLiveViewModel: LiveViewModel
    var favoriteLiveViewModel: LiveViewModel

    @State private var showPluginSyncPrompt = false
    @State private var showUpdateToast = false
    @State private var updateToastTitle = ""
    @State private var updateToastSuccess = true
    private let updateToastOptions = SimpleToastOptions(alignment: .topLeading, hideAfter: 2.0)

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        self.searchLiveViewModel = LiveViewModel(roomListType: .search, liveType: .placeholder, appViewModel: appViewModel)
        self.favoriteLiveViewModel = LiveViewModel(roomListType: .favorite, liveType: .placeholder, appViewModel: appViewModel)
    }
    
    var body: some View {

        @Bindable var contentVM = appViewModel

        NavigationView {
            TabView(selection:$contentVM.selection) {
                if appViewModel.pluginAvailability.hasAvailablePlugins {
                    FavoriteMainView()
                        .tabItem {
                            if appViewModel.favoriteViewModel.isLoading == true || appViewModel.favoriteViewModel.cloudReturnError == true {
                                Label(
                                    title: {  },
                                    icon: {
                                        Image(systemName: appViewModel.favoriteViewModel.isLoading == true ? "arrow.triangle.2.circlepath.icloud" : appViewModel.favoriteViewModel.cloudKitReady == true ? "checkmark.icloud" : "exclamationmark.icloud" )
                                    }
                                )
                                .contentTransition(.symbolEffect(.replace))
                            } else {
                                Text("收藏")
                            }
                        }
                        .tag(0)
                        .environment(favoriteLiveViewModel)
                        .environment(appViewModel)
                } else {
                    TVShellFavoriteView()
                        .tabItem {
                            Text("收藏")
                        }
                        .tag(0)
                        .environment(appViewModel)
                }
                
                PlatformView()
                    .tabItem {
                        Text("配置")
                    }
                    .tag(1)
                    .environment(appViewModel)

                
                if appViewModel.pluginAvailability.hasAvailablePlugins {
                    SearchRoomView()
                        .tabItem {
                            Text("搜索")
                        }
                        .tag(2)
                        .environment(searchLiveViewModel)
                        .environment(appViewModel)
                }

                
                SettingView()
                    .tabItem {
                        Text("设置")
                    }
                    .tag(3)
                    .environment(appViewModel)

            }
        }
        .environment(appViewModel.consentService)
        .onAppear {
            Task {
                // 启动时拉取 key 映射（后台静默，不阻塞 UI）
                Task { await PluginSourceKeyService.shared.fetchKeys() }
                await appViewModel.pluginAvailability.checkAvailability()

                // 自动检查插件更新
                if appViewModel.pluginAvailability.hasAvailablePlugins && !appViewModel.pluginSourceManager.sourceURLs.isEmpty {
                    await appViewModel.pluginSourceManager.refreshAvailableUpdates()
                    let updatableIds = appViewModel.pluginAvailability.installedPluginIds.filter {
                        appViewModel.pluginSourceManager.hasUpdate(for: $0)
                    }
                    if !updatableIds.isEmpty {
                        presentUpdateToast(success: true, title: "有 \(updatableIds.count) 个插件需要更新，正在更新...")
                        var successCount = 0
                        for id in updatableIds {
                            if await appViewModel.pluginSourceManager.updatePlugin(pluginId: id) {
                                successCount += 1
                            }
                        }
                        await appViewModel.pluginAvailability.refresh()
                        if successCount > 0 {
                            presentUpdateToast(success: true, title: "\(successCount) 个插件已更新完成")
                        } else {
                            presentUpdateToast(success: false, title: "插件更新失败")
                        }
                    }
                }

                // 无本地插件时，检查 CloudKit 是否有已保存的插件源
                if !appViewModel.pluginAvailability.hasAvailablePlugins {
                    await appViewModel.pluginSourceSyncService.checkCloudForSources()
                    if appViewModel.pluginSourceSyncService.hasSyncedSources {
                        showPluginSyncPrompt = true
                    }
                }
            }
        }
        .alert("检测到云端插件", isPresented: $showPluginSyncPrompt) {
            Button("一键安装") {
                // 先打开 cover,等 TVPluginManagementView mount 后由它的 .task 自动跑 performOneClickInstall。
                // 不在这里直接调,是为了让 consent alert 走 cover 内的绑定,避免双 alert 冲突。
                appViewModel.pendingPluginManagementAction = .oneClickInstall
                appViewModel.showPluginManagement = true
            }
            Button("取消", role: .cancel) {
                appViewModel.pluginSourceSyncService.dismissPrompt()
            }
        } message: {
            Text("检测到您已在其他设备安装过插件，是否一键安装？")
        }
        // consent alert 不在这里挂 —— 改由 TVPluginManagementView 内部统一处理,
        // 所有触发 consent 的路径都通过 showPluginManagement 先把 cover 打开。
        .fullScreenCover(isPresented: $contentVM.showPluginManagement) {
            TVPluginManagementView(
                pluginSourceManager: appViewModel.pluginSourceManager,
                pluginAvailability: appViewModel.pluginAvailability
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .environment(appViewModel)
            .environment(appViewModel.consentService)
            .onExitCommand {
                contentVM.showPluginManagement = false
            }
        }
        .overlay {
            if appViewModel.pluginSourceSyncService.isInstalling {
                cloudInstallProgressOverlay
            }
        }
        .simpleToast(isPresented: $showUpdateToast, options: updateToastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: updateToastSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(updateToastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            if contentVM.selection == 0 {
                NotificationCenter.default.post(name: SimpleLiveNotificationNames.favoriteRefresh, object: nil)
            }
        })
        .onChange(of: appViewModel.pluginAvailability.installedPluginIds) { oldIds, installedIds in
            // 从无插件变为有插件时，主动触发收藏同步
            if oldIds.isEmpty && !installedIds.isEmpty {
                Task {
                    await appViewModel.favoriteViewModel.syncWithActor()
                }
            }
            if installedIds.isEmpty, contentVM.selection == 2 {
                contentVM.selection = 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.navigateToSettings)) { _ in
            contentVM.selection = 3
        }
        
//        .simpleToast(isPresented: $contentVM.showToast, options: appViewModel.toastOptions) {
//            VStack(alignment: .leading) {
//                Label("提示", systemImage: appViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
//                    .font(.headline.bold())
//                Text(appViewModel.toastTitle)
//            }
//            .padding()
//            .background(.black.opacity(0.6))
//            .foregroundColor(Color.white)
//            .cornerRadius(10)
//        }
    }

    @MainActor
    private func presentUpdateToast(success: Bool, title: String) {
        updateToastSuccess = success
        updateToastTitle = title
        showUpdateToast = true
    }

    // MARK: - 云端一键安装进度

    private var cloudInstallProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(2)

                if let message = appViewModel.pluginSourceSyncService.installStatusMessage {
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                if appViewModel.pluginSourceManager.installTotalCount > 0 {
                    Text("\(appViewModel.pluginSourceManager.installCompletedCount)/\(appViewModel.pluginSourceManager.installTotalCount)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: appViewModel.pluginSourceSyncService.isInstalling)
    }
}
