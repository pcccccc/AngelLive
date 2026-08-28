//
//  PluginAvailabilityService.swift
//  AngelLiveCore
//
//  检测 sandbox 中是否有用户安装的远程 LiveParse JS 插件。
//  只检查 sandbox（用户安装的），不检查 builtIn（bundle 内置的）。
//  根据检测结果决定显示完整 UI 还是壳 UI。
//

import Foundation
import Observation

@Observable
public final class PluginAvailabilityService: @unchecked Sendable {

    /// sandbox 中是否有已安装的插件
    public private(set) var hasAvailablePlugins: Bool = false

    /// 已安装资源扩展的 pluginId 列表
    public private(set) var installedPluginIds: [String] = []

    /// 已安装插件中需要登录平台账号的 pluginId 集合(由 manifest.requiresLogin 决定)。
    public private(set) var loginRequiredInstalledPluginIds: Set<String> = []

    /// 当前正在检测中
    public private(set) var isChecking: Bool = false

    /// 是否至少完成过一次本地插件检测。用于区分“尚未检测”和“确认没有插件”。
    public private(set) var hasCheckedAvailability: Bool = false

    /// 本地插件目录每次重新检测后递增。
    ///
    /// 插件原地升级时 `installedPluginIds` 不会变，视图仍需要重新读取
    /// manifest、平台元数据和首页能力，因此不能只依赖 ID 列表作为失效信号。
    public private(set) var catalogRevision: UInt = 0

    public init() {}

    /// 检测 sandbox 目录下是否有任何已安装的插件
    @MainActor
    public func checkAvailability() async {
        isChecking = true
        defer {
            isChecking = false
            hasCheckedAvailability = true
            catalogRevision &+= 1
        }

        // 仅认定“可被正确解析的沙盒插件 manifest”，不把空目录/损坏目录算作可用插件。
        let pluginMap = SandboxPluginCatalog.installedPluginMap()
        installedPluginIds = pluginMap.keys.sorted()
        loginRequiredInstalledPluginIds = Set(pluginMap.values
            .filter { $0.requiresLogin }
            .map { $0.pluginId })
        hasAvailablePlugins = !installedPluginIds.isEmpty
    }

    /// 检查某个 pluginId 的插件是否已安装
    public func isPluginInstalled(for pluginId: String) -> Bool {
        installedPluginIds.contains(pluginId)
    }

    /// 已安装的插件是否需要登录(仅基于本地 manifest)。
    public func requiresLogin(for pluginId: String) -> Bool {
        loginRequiredInstalledPluginIds.contains(pluginId)
    }

    /// 刷新状态（插件安装成功后调用）
    @MainActor
    public func refresh() async {
        // 重新加载插件管理器
        try? LiveParsePlugins.shared.reload()
        PlatformCapability.invalidateCache()
        await checkAvailability()
        // 插件安装/更新后，立即把持久化会话同步进插件运行时。
        await PlatformSessionLiveParseBridge.syncFromPersistedSessionsOnLaunch()
    }
}
