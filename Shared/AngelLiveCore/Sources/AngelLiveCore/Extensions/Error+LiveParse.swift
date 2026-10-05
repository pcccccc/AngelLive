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
        if let standardError = standardizedPluginError {
            switch standardError.code {
            case .authRequired:
                // 含非 ASCII 字符视为插件写给用户的文案（协议 v1）；纯英文多为旧插件的技术文案，走通用登录提示。
                if standardError.message.unicodeScalars.contains(where: { !$0.isASCII }) {
                    return standardError.message
                }
            case .notLive:
                let message = standardError.message.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? "主播当前未开播" : message
            default:
                break
            }
        }

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
            #"AUTH_REQUIRED"#
        ]

        return authRequiredPatterns.contains { pattern in
            searchableText.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    /// 插件按错误协议抛出的标准错误；非标准错误返回 nil。
    var standardizedPluginError: LiveParsePluginStandardError? {
        guard let pluginError = self as? LiveParsePluginError,
              case .standardized(let error) = pluginError else { return nil }
        return error
    }

    /// 插件明确声明主播未开播 / 已下播（NOT_LIVE）。
    var isNotLive: Bool {
        standardizedPluginError?.code == .notLive
    }

    /// 风控类错误（BLOCKED）且插件标记登录后可能缓解（`loginMayHelp: "true"`）。
    var isLoginSuggested: Bool {
        guard let error = standardizedPluginError, error.code == .blocked else { return false }
        return error.context["loginMayHelp"]?.lowercased() == "true"
    }

    /// 错误页是否展示「去登录」入口：硬性需要登录，或登录可能缓解风控。
    var showsLoginAction: Bool {
        isAuthRequired || isLoginSuggested
    }

    /// Only host-created recovery errors carry a trusted plugin identity.
    var authRequiredPluginIDs: [String] {
        (self as? PluginAuthenticationRequiredError)?.pluginIDs ?? []
    }
}
