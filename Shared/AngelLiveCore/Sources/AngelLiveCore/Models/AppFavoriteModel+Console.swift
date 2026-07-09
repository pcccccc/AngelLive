//
//  AppFavoriteModel+Console.swift
//  AngelLiveCore
//
//  收藏操作在开发者控制台(PluginConsoleService)的文案格式化。
//  从 AppFavoriteModel 主文件抽出(纯搬迁);仅供本模块内收藏流程调用。
//

import Foundation

extension AppFavoriteModel {
    /// 构造统一的控制台请求摘要,用于开发者面板查看本次收藏操作针对哪个房间。
    static func consoleRequestBody(for room: LiveModel) -> String {
        let platform = room.liveType.rawValue
        let userId = room.userId.isEmpty ? "-" : room.userId
        let roomId = room.roomId.isEmpty ? "-" : room.roomId
        let userName = room.userName.isEmpty ? "-" : room.userName
        let roomTitle = room.roomTitle.isEmpty ? "-" : room.roomTitle
        return """
        platform: \(platform)
        userId: \(userId)
        roomId: \(roomId)
        userName: \(userName)
        roomTitle: \(roomTitle)
        """
    }

    /// 控制台成功面板:把操作结果(收藏/取消)+ 房间识别信息 + 当前收藏总数都打出来。
    static func consoleSuccessSummary(verb: String, room: LiveModel, totalCount: Int) -> String {
        let platformName = LiveParseTools.getLivePlatformName(room.liveType)
        let userName = room.userName.isEmpty ? "-" : room.userName
        let identity: String
        if !room.userId.isEmpty {
            identity = "userId=\(room.userId)"
        } else if !room.roomId.isEmpty {
            identity = "roomId=\(room.roomId)"
        } else {
            identity = "name=\(userName)"
        }
        return """
        result: \(verb)
        platform: \(platformName)
        target: \(userName) (\(identity))
        currentFavoriteCount: \(totalCount)
        """
    }

    /// 控制台错误面板:既给出格式化的错误码,也保留原始 error 描述,方便排查。
    static func consoleErrorMessage(for error: Error) -> String {
        let formatted = FavoriteService.formatErrorCode(error: error)
        let raw = error.localizedDescription
        if formatted == raw {
            return formatted
        }
        return """
        \(formatted)
        ── raw ──
        \(raw)
        """
    }
}
