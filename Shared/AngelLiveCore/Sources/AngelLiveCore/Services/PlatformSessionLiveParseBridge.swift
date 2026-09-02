//
//  PlatformSessionLiveParseBridge.swift
//  AngelLiveCore
//
//  Created by Codex on 2026/2/18.
//

import Foundation

/// Keeps plugin runtimes coherent with the host-owned credential vault.
/// Credential values never cross the Swift/JavaScriptCore boundary.
public enum PlatformSessionLiveParseBridge {
    public static func syncSessionToLiveParse(
        _ session: PlatformSession,
        expectedVaultRevision: String
    ) {
        invalidateRuntime(
            pluginId: session.pluginId,
            expectedVaultRevision: expectedVaultRevision
        )
    }

    public static func clearForPlatform(
        pluginId: String,
        expectedVaultRevision: String
    ) {
        invalidateRuntime(
            pluginId: pluginId,
            expectedVaultRevision: expectedVaultRevision
        )
    }

    public static func syncFromPersistedSessionsOnLaunch() async {
        // 基于已安装插件集合驱动：宿主端不再维护平台 enum。
        let pluginIds = SandboxPluginCatalog.installedPluginIds()
        for pluginId in pluginIds {
            await PlatformSessionManager.shared.hydratePersistedSessionToRuntime(pluginId: pluginId)
        }
    }

    private static func invalidateRuntime(
        pluginId: String,
        expectedVaultRevision: String
    ) {
        guard LiveParsePlatformSessionVault.revision(for: pluginId) == expectedVaultRevision else {
            return
        }
        // A replacement runtime reads no credential value. Native Host.http
        // consults the vault only when a protected auth mode is requested.
        LiveParsePlugins.shared.evict(pluginId: pluginId)
    }
}
