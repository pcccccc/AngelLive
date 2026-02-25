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
        Task {
            await syncCookie(session)
        }
    }

    public static func clearForPlatform(_ platformId: PlatformSessionID) {
        Task {
            await clearCookie(platformId: platformId)
        }
    }

    public static func syncFromPersistedSessionsOnLaunch() async {
        for platformId in PlatformSessionID.allCases {
            if let session = await PlatformSessionManager.shared.getSession(platformId: platformId) {
                await syncCookie(session)
            } else {
                await clearCookie(platformId: platformId)
            }
        }
    }

    // MARK: - Internal

    private static func syncCookie(_ session: PlatformSession) async {
        let normalized = session.cookie?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard session.state == .authenticated, !normalized.isEmpty else {
            await clearCookie(platformId: session.platformId)
            return
        }

        var payload: [String: Any] = ["cookie": normalized]
        if let uid = session.uid, !uid.isEmpty {
            payload["uid"] = uid
        }

        _ = try? await LiveParsePlugins.shared.call(
            pluginId: session.platformId.rawValue,
            function: "setCookie",
            payload: payload
        )
    }

    private static func clearCookie(platformId: PlatformSessionID) async {
        _ = try? await LiveParsePlugins.shared.call(
            pluginId: platformId.rawValue,
            function: "clearCookie",
            payload: [:]
        )
    }
}
