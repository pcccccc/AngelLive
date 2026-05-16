import Foundation

/// Compatibility login declarations for older plugin manifests.
///
/// Twitch and Kick plugins already know how to consume host-managed cookies, but
/// several released manifests do not declare `loginFlow`. Keep these fallbacks
/// small and data-only so plugin authors can later move the same fields into
/// manifest.json without changing app code.
public enum PlatformLoginCompatibility {
    public static func loginFlow(for manifest: LiveParsePluginManifest) -> ManifestLoginFlow? {
        if let loginFlow = manifest.loginFlow {
            return loginFlow
        }

        switch normalizedPluginId(manifest.pluginId) {
        case "twitch":
            return twitchLoginFlow()
        case "kick":
            return kickLoginFlow()
        case "soop":
            return soopLoginFlow()
        default:
            return nil
        }
    }

    public static func auth(for manifest: LiveParsePluginManifest) -> ManifestAuth? {
        if let auth = manifest.auth {
            return auth
        }
        guard loginFlow(for: manifest) != nil else { return nil }
        return ManifestAuth(
            required: true,
            credentialKinds: ["cookie"],
            supportsStatusCheck: false,
            supportsValidation: false
        )
    }

    public static func requiresLogin(_ manifest: LiveParsePluginManifest) -> Bool {
        if let required = manifest.auth?.required {
            return required
        }
        return loginFlow(for: manifest) != nil
    }

    private static func twitchLoginFlow() -> ManifestLoginFlow {
        ManifestLoginFlow(
            kind: "webview",
            loginURL: "https://www.twitch.tv/login",
            cookieDomains: ["twitch.tv", "www.twitch.tv"],
            authSignalCookies: ["auth-token"],
            uidCookieNames: ["login", "name", "unique_id"],
            successURLKeyword: "twitch.tv",
            requiredCookieHint: "需要包含 auth-token，建议同时包含 login 或 unique_id。",
            websiteHost: "www.twitch.tv"
        )
    }

    private static func kickLoginFlow() -> ManifestLoginFlow {
        ManifestLoginFlow(
            kind: "webview",
            loginURL: "https://kick.com/login",
            cookieDomains: ["kick.com", "www.kick.com"],
            authSignalCookies: ["kick_session", "XSRF-TOKEN"],
            uidCookieNames: ["username", "user_id", "userId"],
            successURLKeyword: "kick.com",
            requiredCookieHint: "需要包含 kick_session，建议同时包含 XSRF-TOKEN。",
            websiteHost: "kick.com"
        )
    }

    private static func soopLoginFlow() -> ManifestLoginFlow {
        ManifestLoginFlow(
            kind: "webview",
            loginURL: "https://login.sooplive.com/afreeca/login.php",
            cookieDomains: [
                "sooplive.co.kr",
                "sooplive.com",
                "afreecatv.com"
            ],
            authSignalCookies: [
                "AuthTicket",
                "PdboxTicket",
                "RDB"
            ],
            uidCookieNames: ["uid", "user_id", "szBjId"],
            successURLKeyword: "sooplive",
            requiredCookieHint: "海外访问通常需要 AbroadChk=OK；19+ 房间还需要账号登录后的 AuthTicket/PdboxTicket 等 Cookie。",
            websiteHost: "www.sooplive.com"
        )
    }

    private static func normalizedPluginId(_ pluginId: String) -> String {
        pluginId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
