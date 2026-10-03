//
//  PluginInstallConsentService.swift
//  AngelLive
//
//  iOS 端的插件安装确认实现:基于 SwiftUI alert + CheckedContinuation。
//  请求方调用 requestConsent(reason:) 挂起,UI 层根据 isPresenting / pendingReason 渲染 alert,
//  用户点继续/取消时调用 resolve(_:) 恢复挂起。
//

import Foundation
import Observation
import AngelLiveCore

@MainActor
@Observable
final class PluginInstallConsentService: PluginInstallConsentRequesting {

    var isPresenting: Bool = false
    var pendingReason: PluginInstallConsentReason?

    @ObservationIgnored
    private var continuation: CheckedContinuation<Bool, Never>?

    private var presentationHosts: [UUID] = []

    nonisolated init() {}

    func requestConsent(reason: PluginInstallConsentReason) async -> Bool {
        guard !presentationHosts.isEmpty else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // 同时只允许一个待确认请求,如果有遗留就先按取消处理
            if let existing = continuation {
                existing.resume(returning: false)
            }
            continuation = cont
            pendingReason = reason
            isPresenting = true
        }
    }

    func presentationDidAppear(_ id: UUID) {
        presentationHosts.removeAll { $0 == id }
        presentationHosts.append(id)
    }

    func presentationDidDisappear(_ id: UUID) {
        let wasActiveHost = presentationHosts.last == id
        presentationHosts.removeAll { $0 == id }
        if wasActiveHost, isPresenting {
            resolve(false)
        }
    }

    func isPresenting(for hostID: UUID) -> Bool {
        isPresenting && presentationHosts.last == hostID
    }

    func resolve(_ approved: Bool) {
        isPresenting = false
        let cont = continuation
        continuation = nil
        pendingReason = nil
        cont?.resume(returning: approved)
    }

    // MARK: - 文案
    var alertTitle: String {
        switch pendingReason {
        case .addingSubscriptionSource:
            return "订阅源安装确认"
        case .installingLoginPlugin, .installingLoginPluginsBatch:
            return "插件登录权限确认"
        case .cloudKitAutoInstall:
            return "iCloud 同步插件确认"
        case .none:
            return ""
        }
    }

    var alertMessage: String {
        switch pendingReason {
        case .addingSubscriptionSource(let url):
            return "订阅源「\(url)」可能包含需要登录的插件。登录类插件会处理您的账号密码或 Cookie，存在凭证泄露风险。请确认该订阅源来自可信来源后再继续。"
        case .installingLoginPlugin(_, let displayName):
            return "插件「\(displayName)」需要您登录对应平台。该过程由插件代码处理您的凭证，存在信息泄露风险。请确认插件来自可信来源后再安装。"
        case .installingLoginPluginsBatch(let plugins):
            let bullets = plugins.map { "• \($0.displayName)" }.joined(separator: "\n")
            return "以下 \(plugins.count) 个插件需要您登录对应平台：\n\(bullets)\n\n登录类插件会处理您的账号密码或 Cookie，存在凭证泄露风险。请确认这些插件来自可信来源后再继续。取消安装将取消本次所有待安装项目。"
        case .cloudKitAutoInstall(let urls):
            return "iCloud 检测到您在其他设备保存的 \(urls.count) 个订阅源，其中可能包含需要登录的插件。请确认这些订阅来自可信来源后再继续自动安装。"
        case .none:
            return ""
        }
    }

    var continueButtonTitle: String {
        switch pendingReason {
        case .addingSubscriptionSource:
            return "继续添加"
        case .installingLoginPlugin, .installingLoginPluginsBatch, .cloudKitAutoInstall:
            return "继续安装"
        case .none:
            return "继续"
        }
    }

    var cancelButtonTitle: String {
        switch pendingReason {
        case .installingLoginPlugin, .installingLoginPluginsBatch:
            return "取消安装"
        default:
            return "取消"
        }
    }
}
