//
//  PluginInstallConsentService.swift
//  AngelLiveMacOS
//
//  macOS 端的插件安装确认实现:基于 SwiftUI alert + CheckedContinuation。
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

    private var presentationHosts: [UUID] = []

    var hasPresentationHost: Bool { !presentationHosts.isEmpty }

    @ObservationIgnored
    private var continuation: CheckedContinuation<Bool, Never>?

    nonisolated init() {}

    func presentationDidAppear(_ id: UUID) {
        presentationHosts.removeAll { $0 == id }
        presentationHosts.append(id)
    }

    func presentationDidDisappear(_ id: UUID) {
        let wasActiveHost = presentationHosts.last == id
        presentationHosts.removeAll { $0 == id }
        if wasActiveHost, isPresenting { resolve(false) }
    }

    func isPresenting(for hostID: UUID) -> Bool {
        isPresenting && presentationHosts.last == hostID
    }

    func requestConsent(reason: PluginInstallConsentReason) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if let existing = continuation {
                existing.resume(returning: false)
            }
            continuation = cont
            pendingReason = reason
            isPresenting = true
        }
    }

    func resolve(_ approved: Bool) {
        isPresenting = false
        let cont = continuation
        continuation = nil
        pendingReason = nil
        cont?.resume(returning: approved)
    }

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
            return "以下 \(plugins.count) 个插件需要您登录对应平台：\n\(bullets)\n\n登录类插件会处理您的账号密码或 Cookie，存在凭证泄露风险。请确认这些插件来自可信来源后再继续。"
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
}
