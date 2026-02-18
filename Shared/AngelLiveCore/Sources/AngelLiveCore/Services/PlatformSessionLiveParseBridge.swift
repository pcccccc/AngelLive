//
//  PlatformSessionLiveParseBridge.swift
//  AngelLiveCore
//
//  Created by Codex on 2026/2/18.
//

import Foundation
import LiveParse

public enum PlatformSessionLiveParseBridge {
    public static func syncSessionToLiveParse(_ session: PlatformSession) {
        guard session.platformId == .douyin else { return }
        Task {
            await syncDouyinCookie(session)
        }
    }

    public static func clearForPlatform(_ platformId: PlatformSessionID) {
        guard platformId == .douyin else { return }
        Task {
            await clearDouyinCookie()
        }
    }

    public static func syncFromPersistedSessionsOnLaunch() async {
        if let session = await PlatformSessionManager.shared.getSession(platformId: .douyin) {
            await syncDouyinCookie(session)
        } else {
            await clearDouyinCookie()
        }
    }

    private static func syncDouyinCookie(_ session: PlatformSession) async {
        let normalized = session.cookie?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if session.state == .authenticated, !normalized.isEmpty {
            _ = try? await LiveParsePlugins.shared.call(
                pluginId: "douyin",
                function: "setCookie",
                payload: ["cookie": normalized]
            )
        } else {
            await clearDouyinCookie()
        }
    }

    private static func clearDouyinCookie() async {
        _ = try? await LiveParsePlugins.shared.call(
            pluginId: "douyin",
            function: "clearCookie",
            payload: [:]
        )
    }
}
