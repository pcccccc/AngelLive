//
//  Error+LiveParse.swift
//  AngelLiveCore
//
//  Created by pangchong on 11/26/25.
//

import Foundation
import LiveParse

public extension Error {
    /// 从错误中提取用户友好的错误消息
    var liveParseMessage: String {
        if let liveParseError = self as? LiveParseError {
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
}
