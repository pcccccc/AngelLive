//
//  Error+LiveParse.swift
//  AngelLiveCore
//
//  Created by pangchong on 11/26/25.
//

import Foundation

public extension Error {
    /// 从错误中提取用户友好的错误消息（带详细位置信息）
    var liveParseMessage: String {
        if isAuthRequired {
            return "当前内容需要登录账号后才能访问，请前往设置页登录后重试。"
        }

        if let liveParseError = self as? LiveParseError {
            let detail = liveParseError.detail

            // 提取详情的第一行作为更详细的错误消息
            if let firstLine = detail.components(separatedBy: "\n").first, !firstLine.isEmpty {
                return firstLine
            }

            // 如果没有详细信息，返回标题
            return liveParseError.title
        }

        if let pluginError = self as? LiveParsePluginError {
            switch pluginError {
            case .standardized(let error):
                return error.message.isEmpty ? pluginError.localizedDescription : error.message
            case .jsException(let message):
                return message
            default:
                return pluginError.localizedDescription
            }
        }

        return localizedDescription
    }

    /// 从错误中提取详细的错误信息（包含网络请求/响应详情）
    var liveParseDetail: String? {
        if let liveParseError = self as? LiveParseError {
            let detail = liveParseError.detail
            return detail.isEmpty ? nil : detail
        }

        if let pluginError = self as? LiveParsePluginError {
            let detail = pluginError.localizedDescription
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

    /// 检查是否是需要登录的错误（通用，适用于所有平台）
    var isAuthRequired: Bool {
        if self is PluginAuthenticationRequiredError {
            return true
        }
        if let pluginError = self as? LiveParsePluginError {
            switch pluginError {
            case .standardized(let error):
                if error.code == .authRequired {
                    return true
                }
            default:
                break
            }
        }

        let searchableText: String
        if let liveParseError = self as? LiveParseError {
            searchableText = [
                liveParseError.title,
                liveParseError.detail,
                localizedDescription
            ]
            .joined(separator: "\n")
        } else {
            searchableText = localizedDescription
        }

        let authRequiredPatterns = [
            #"错误代码:\s*-?352"#,
            #"code\s*=\s*\"?-?352\"?"#,
            #"\"code\"\s*:\s*\"?-?352\"?"#,
            #"AUTH_REQUIRED"#,
            #"错误代码:\s*-?406"#,
            #"code\s*=\s*\"?-?406\"?"#,
            #"\"code\"\s*:\s*\"?-?406\"?"#,
            #"\"httpCode\"\s*:\s*\"?-?406\"?"#
        ]

        return authRequiredPatterns.contains { pattern in
            searchableText.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    /// Only host-created recovery errors carry a trusted plugin identity.
    var authRequiredPluginIDs: [String] {
        (self as? PluginAuthenticationRequiredError)?.pluginIDs ?? []
    }
}
