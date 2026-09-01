//
//  AppState.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation
import AngelLiveCore
import AngelLiveDependencies

/// 打开 TVPluginManagementView cover 时希望视图自动跑的安装动作。
enum PluginManagementAutoAction: Sendable {
    /// 走 PluginSourceSyncService.performOneClickInstall(从 CloudKit 已检测的源批量安装)。
    case oneClickInstall
    /// 走 deep link 安装(addSourceFromInput + 拉取索引 + installAll)。
    case deepLinkInstall(input: String)
}

@Observable
class AppState {
    /// 首页在能力确认前也保持有效 selection；若没有 homeFeed，ContentView 会有序回退到收藏。
    var selection = 4
    var favoriteViewModel = AppFavoriteModel()
    var pluginAvailability = PluginAvailabilityService()
    var pluginSourceManager = PluginSourceManager()
    var pluginSourceSyncService = PluginSourceSyncService()
    var consentService = PluginInstallConsentService()
    var bookmarkService = StreamBookmarkService()
    var shellHistoryService = ShellHistoryService()
    var remoteInputService: RemoteInputService
    var danmuSettingsViewModel = DanmuSettingModel()
    var searchViewModel = SearchViewModel()
    var historyViewModel = HistoryModel()
    var playerSettingsViewModel = PlayerSettingModel()
    var generalSettingsViewModel = GeneralSettingModel()

    /// 控制 TVPluginManagementView 是否以 fullScreenCover 形式呈现。
    /// 所有触发 consent 的路径(用户添加源、一键安装、deep link)在调 installAll 前都先把它置 true,
    /// 让 cover 内的 alert 绑定生效,避免双重 alert 冲突
    /// ("Attempt to present alert on view controller which is already presenting")。
    var showPluginManagement: Bool = false

    /// cover mount 后需要 TVPluginManagementView 自动执行的动作。
    /// nil 表示用户手动打开的 cover,不做自动动作。
    var pendingPluginManagementAction: PluginManagementAutoAction?

    init() {
        let service = RemoteInputService()
        service.start()
        self.remoteInputService = service

        // 注入插件安装确认请求器
        pluginSourceManager.consentRequester = consentService
    }

    // MARK: - Deep Link
    var pendingDeepLinkRoom: LiveModel?
    var showDeepLinkPlayer = false

    /// 解析 Deep Link URL
    /// URL 格式: simplelive://room/{platform}/{roomId}?userId={userId}
    func handleDeepLink(url: URL) {
        guard url.scheme == "simplelive",
              url.host == "room" else {
            return
        }

        // 解析路径: /{platform}/{roomId}
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else {
            return
        }

        let platformString = pathComponents[0]
        let roomId = pathComponents[1]

        // 解析 userId (可选)
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let userId = urlComponents?.queryItems?.first(where: { $0.name == "userId" })?.value ?? ""

        // 转换平台类型
        guard let liveType = LiveType(rawValue: platformString) else {
            return
        }

        // 创建 LiveModel
        let liveModel = LiveModel(
            userName: "",
            roomTitle: "",
            roomCover: "",
            userHeadImg: "",
            liveType: liveType,
            liveState: "1",  // 从 Top Shelf 来的都是正在直播
            userId: userId,
            roomId: roomId,
            liveWatchedCount: nil
        )

        pendingDeepLinkRoom = liveModel
        showDeepLinkPlayer = true
    }
}
