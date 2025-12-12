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
import LiveParse

@Observable
class AppState {
    var selection = 0
    var favoriteViewModel = AppFavoriteModel()
    var danmuSettingsViewModel = DanmuSettingModel()
    var searchViewModel = SearchViewModel()
    var historyViewModel = HistoryModel()
    var playerSettingsViewModel = PlayerSettingModel()
    var generalSettingsViewModel = GeneralSettingModel()

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
