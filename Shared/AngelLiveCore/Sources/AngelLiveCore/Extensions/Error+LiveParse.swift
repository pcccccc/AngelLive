//
//  Error+LiveParse.swift
//  AngelLiveCore
//
//  Created by pangchong on 11/26/25.
//

import Foundation
import LiveParse

public extension Error {
    /// 从错误中提取用户友好的错误消息（带详细位置信息）
    var liveParseMessage: String {
        if let liveParseError = self as? LiveParseError {
            let detail = liveParseError.detail

            // 提取详情的第一行作为更详细的错误消息
            // 例如：从 "返回结果为空 [Bilibili.getRoomList]" 提取出来
            if let firstLine = detail.components(separatedBy: "\n").first, !firstLine.isEmpty {
                return firstLine
            }

            // 如果没有详细信息，返回标题
            return liveParseError.title
        }
        return localizedDescription
    }

    /// 从错误中提取详细的错误信息（包含网络请求/响应详情）
    var liveParseDetail: String? {
        if let liveParseError = self as? LiveParseError {
            let detail = liveParseError.detail
            return detail.isEmpty ? nil : detail
        }
        return nil
    }

    /// 从错误中提取 CURL 命令（用于调试和复现网络请求）
    var liveParseCurl: String? {
        if let liveParseError = self as? LiveParseError {
            return liveParseError.curl
        }
        return nil
    }

    /// 检查是否是 Bilibili -352 风控错误（需要登录）
    var isBilibiliAuthRequired: Bool {
        if let liveParseError = self as? LiveParseError {
            let detail = liveParseError.detail
            // 检查是否包含 "错误代码: -352" 或 "错误代码: 352"
            return detail.contains("错误代码: -352") || detail.contains("错误代码: 352")
        }
        return false
    }
}
