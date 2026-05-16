import Foundation
import Testing
@testable import AngelLiveCore

// MARK: - semverCompare Tests

@Suite("semverCompare")
struct SemverCompareTests {

    @Test("equal versions return 0")
    func equal() {
        #expect(semverCompare("1.0.0", "1.0.0") == 0)
        #expect(semverCompare("0.0.0", "0.0.0") == 0)
        #expect(semverCompare("12.34.56", "12.34.56") == 0)
    }

    @Test("major version difference")
    func majorDiff() {
        #expect(semverCompare("2.0.0", "1.0.0") > 0)
        #expect(semverCompare("1.0.0", "2.0.0") < 0)
    }

    @Test("minor version difference")
    func minorDiff() {
        #expect(semverCompare("1.2.0", "1.1.0") > 0)
        #expect(semverCompare("1.1.0", "1.2.0") < 0)
    }

    @Test("patch version difference")
    func patchDiff() {
        #expect(semverCompare("1.0.2", "1.0.1") > 0)
        #expect(semverCompare("1.0.1", "1.0.2") < 0)
    }

    @Test("short version strings are zero-padded")
    func shortVersions() {
        #expect(semverCompare("1", "1.0.0") == 0)
        #expect(semverCompare("1.2", "1.2.0") == 0)
        #expect(semverCompare("2", "1.9.9") > 0)
    }

    @Test("non-numeric parts treated as 0")
    func nonNumeric() {
        // "abc" → Int("abc") ?? 0 → 0, so "1.0.abc" == "1.0.0"
        #expect(semverCompare("1.0.0", "1.0.abc") == 0)
        #expect(semverCompare("abc.0.0", "0.0.0") == 0)
    }

    @Test("empty string treated as 0.0.0")
    func emptyString() {
        #expect(semverCompare("", "") == 0)
        #expect(semverCompare("0.0.1", "") > 0)
    }
}

// MARK: - PlatformCapability Cache Tests

@Suite("PlatformCapability cache")
struct PlatformCapabilityCacheTests {

    @Test("invalidateCache does not crash when cache is empty")
    func invalidateEmpty() {
        PlatformCapability.invalidateCache()
        // 不崩溃即通过
    }

    @Test("invalidateCache can be called multiple times")
    func invalidateMultiple() {
        PlatformCapability.invalidateCache()
        PlatformCapability.invalidateCache()
        PlatformCapability.invalidateCache()
    }
}

// MARK: - Logger Tests

@Suite("Logger")
struct LoggerTests {

    @Test("LogLevel ordering")
    func levelOrdering() {
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.warning)
        #expect(LogLevel.warning < LogLevel.error)
    }

    @Test("plugin category exists")
    func pluginCategory() {
        let category = LogCategory.plugin
        #expect(category.rawValue == "Plugin")
    }
}

// MARK: - Plugin Index Error Tests

@Suite("Plugin index errors")
struct PluginIndexErrorTests {

    @Test("non-JSON responses include response diagnostics")
    func nonJSONResponseDescription() {
        let diagnostics = LiveParsePluginIndexResponseDiagnostics(
            url: URL(string: "https://example.com/plugins.json")!,
            statusCode: 200,
            contentType: "text/html",
            bodyPreview: "<html>blocked</html>"
        )

        let description = PluginSourceManager.detailedErrorDescription(
            LiveParsePluginIndexFetchError.nonJSONResponse(diagnostics)
        )

        #expect(description.contains("返回的不是 JSON"))
        #expect(description.contains("https://example.com/plugins.json"))
        #expect(description.contains("HTTP 200"))
        #expect(description.contains("text/html"))
        #expect(description.contains("<html>blocked</html>"))
    }

    @Test("wrapped decoding errors keep coding path and response diagnostics")
    func wrappedDecodingErrorDescription() {
        let diagnostics = LiveParsePluginIndexResponseDiagnostics(
            url: URL(string: "https://example.com/plugins.json")!,
            statusCode: 200,
            contentType: "application/json",
            bodyPreview: "{\"apiVersion\":\"1\"}"
        )
        let context = DecodingError.Context(
            codingPath: [AnyCodingKey(stringValue: "apiVersion")!],
            debugDescription: "Expected to decode Int but found a string instead."
        )

        let description = PluginSourceManager.detailedErrorDescription(
            LiveParsePluginIndexFetchError.decodingFailed(
                diagnostics,
                .typeMismatch(Int.self, context)
            )
        )

        #expect(description.contains("类型不匹配"))
        #expect(description.contains("apiVersion"))
        #expect(description.contains("application/json"))
        #expect(description.contains("{\"apiVersion\":\"1\"}"))
    }
}

@Suite("Plugin error card parsing")
struct PluginErrorCardParsingTests {

    @Test("structured plugin error message exposes summary and diagnostics")
    func structuredMessageParsing() {
        let message = "拉取插件索引失败: 返回的不是 JSON。URL https://example.com/plugins.json, HTTP 200, Content-Type text/html, 响应片段 <html>blocked</html>"
        let parsed = ParsedPluginSourceErrorMessage(message: message)

        #expect(parsed.summary == "拉取插件索引失败: 返回的不是 JSON")
        #expect(parsed.details.map(\.label) == ["URL", "HTTP", "Content-Type", "响应片段"])
        #expect(parsed.details[0].value == "https://example.com/plugins.json")
        #expect(parsed.details[1].value == "200")
        #expect(parsed.details[2].value == "text/html")
        #expect(parsed.details[3].value == "<html>blocked</html>")
        #expect(parsed.details[0].isURL)
        #expect(parsed.details[3].isResponsePreview)
    }

    @Test("plain plugin error message remains a single summary")
    func plainMessageParsing() {
        let message = "拉取插件索引失败: 请求超时"
        let parsed = ParsedPluginSourceErrorMessage(message: message)

        #expect(parsed.summary == message)
        #expect(parsed.details.isEmpty)
    }
}

@Suite("Plugin source keys")
struct PluginSourceKeyTests {

    @Test("Official short key resolves without remote key index")
    func officialShortKeyFallback() async {
        let urls = await PluginSourceKeyService.shared.resolveKey("444222000")

        #expect(urls?.count == 2)
        #expect(urls?.first?.contains("PluginRelease/plugins.json") == true)
        #expect(urls?.first?.contains("ghfast.top") == true)
    }
}

@Suite("Platform login compatibility")
struct PlatformLoginCompatibilityTests {

    @Test("Twitch and Kick older manifests get host login fallback")
    func fallbackLoginFlows() {
        let twitch = manifest(pluginId: "twitch", liveType: "9")
        let kick = manifest(pluginId: "kick", liveType: "10")
        let soop = manifest(pluginId: "soop", liveType: "8")

        #expect(PlatformLoginCompatibility.loginFlow(for: twitch)?.authSignalCookies == ["auth-token"])
        #expect(PlatformLoginCompatibility.loginFlow(for: kick)?.authSignalCookies.contains("kick_session") == true)
        #expect(PlatformLoginCompatibility.loginFlow(for: soop)?.loginURL == "https://login.sooplive.com/afreeca/login.php")
        #expect(PlatformLoginCompatibility.loginFlow(for: soop)?.cookieDomains.contains("sooplive.co.kr") == true)
        #expect(PlatformLoginCompatibility.loginFlow(for: twitch)?.userAgent == nil)
        #expect(PlatformLoginCompatibility.requiresLogin(twitch))
        #expect(PlatformLoginCompatibility.requiresLogin(kick))
        #expect(PlatformLoginCompatibility.requiresLogin(soop))
    }

    @Test("Manifest loginFlow wins over fallback")
    func manifestLoginFlowWins() {
        let declared = ManifestLoginFlow(
            loginURL: "https://example.com/login",
            cookieDomains: ["example.com"],
            authSignalCookies: ["sid"]
        )
        let twitch = manifest(pluginId: "twitch", liveType: "9", loginFlow: declared)

        #expect(PlatformLoginCompatibility.loginFlow(for: twitch)?.loginURL == "https://example.com/login")
        #expect(PlatformLoginCompatibility.loginFlow(for: twitch)?.authSignalCookies == ["sid"])
    }

    @Test("Manifest auth required false wins over fallback loginFlow")
    func manifestAuthRequiredFalseWins() {
        let twitch = manifest(
            pluginId: "twitch",
            liveType: "9",
            auth: ManifestAuth(required: false, credentialKinds: ["cookie"])
        )

        #expect(PlatformLoginCompatibility.loginFlow(for: twitch) != nil)
        #expect(PlatformLoginCompatibility.requiresLogin(twitch) == false)
    }
}

@Suite("Platform cookie collector")
struct PlatformCookieCollectorTests {

    @Test("Domain matching covers sibling login hosts")
    func domainMatching() {
        let loginFlow = ManifestLoginFlow(
            loginURL: "https://www.twitch.tv/login",
            cookieDomains: ["twitch.tv"],
            authSignalCookies: ["auth-token"]
        )
        let cookies = [
            cookie(name: "auth-token", value: "token", domain: ".twitch.tv"),
            cookie(name: "login", value: "streamer", domain: "www.twitch.tv"),
            cookie(name: "sid", value: "other", domain: "example.com")
        ]

        let filtered = PlatformCookieCollector.filteredCookies(from: cookies, loginFlow: loginFlow)
        #expect(filtered.map(\.name).sorted() == ["auth-token", "login"])
        #expect(PlatformCookieCollector.containsAuthenticatedCookie(in: filtered, loginFlow: loginFlow))
        #expect(PlatformCookieCollector.cookieHeader(from: filtered).contains("auth-token=token"))
    }

    @Test("Session cookie wins duplicate header selection")
    func sessionCookieWinsDuplicateHeaderSelection() {
        let cookies = [
            cookie(name: "XSRF-TOKEN", value: "old-persistent", domain: ".kick.com"),
            cookie(name: "XSRF-TOKEN", value: "fresh-session", domain: "kick.com", expires: nil)
        ]

        #expect(PlatformCookieCollector.cookieHeader(from: cookies) == "XSRF-TOKEN=fresh-session")
    }
}

@Suite("Live image URL resolver")
struct LiveImageURLResolverTests {

    @Test("SOOP empty cover falls back to live preview CDN by room id")
    func soopEmptyCoverFallback() {
        let cover = LiveImageURLResolver.roomCoverURLString(
            rawValue: "",
            liveType: LiveType(rawValue: "8")!,
            roomId: "294060425"
        )

        #expect(cover == "https://liveimg.sooplive.com/m/294060425?320")
    }

    @Test("SOOP legacy image domain is canonicalized")
    func soopLegacyDomainCanonicalized() {
        let cover = LiveImageURLResolver.roomCoverURLString(
            rawValue: "http://liveimg.sooplive.co.kr/m/294060425?511",
            liveType: LiveType(rawValue: "8")!,
            roomId: "294060425"
        )

        #expect(cover == "https://liveimg.sooplive.com/m/294060425?511")
    }

    @Test("SOOP live preview URL can carry a refresh token")
    func soopLivePreviewURLIncludesRefreshToken() {
        let cover = LiveImageURLResolver.soopLivePreviewURLString(
            roomId: "294060425",
            refreshToken: "preview-1"
        )

        #expect(cover == "https://liveimg.sooplive.com/m/294060425?320&_al_preview=preview-1")
    }

    @Test("Non-SOOP empty cover stays empty")
    func nonSOOPEmptyCover() {
        let cover = LiveImageURLResolver.roomCoverURLString(
            rawValue: "",
            liveType: LiveType(rawValue: "13")!,
            roomId: "294060425"
        )

        #expect(cover.isEmpty)
    }

    @Test("SOOP model falls back to avatar when broad number is unavailable")
    func soopModelUsesAvatarFallbackWithoutBroadNumber() {
        let room = LiveModel(
            userName: "streamer",
            roomTitle: "19+ room",
            roomCover: "",
            userHeadImg: "https://stimg.sooplive.com/LOGO/ci/cinnamoroll/cinnamoroll.jpg",
            liveType: LiveType(rawValue: "8")!,
            liveState: "1",
            userId: "cinnamoroll",
            roomId: "cinnamoroll",
            liveWatchedCount: "0"
        )

        #expect(room.displayRoomCover == "https://stimg.sooplive.com/LOGO/ci/cinnamoroll/cinnamoroll.jpg")
    }
}

@Suite("Playback initial selection")
struct PlaybackInitialSelectionTests {

    @Test("Prefers concrete CHZZK-like 1080p over Auto and lower variants")
    func prefersHighestConcreteQuality() {
        let playArgs = [
            LiveQualityModel(cdn: "default", qualitys: [
                quality(title: "Auto", qn: 0, url: "https://example.com/master.m3u8", liveType: "13"),
                quality(title: "720p", qn: 720, url: "https://example.com/720.m3u8", liveType: "13"),
                quality(title: "1080p", qn: 1080, url: "https://example.com/1080.m3u8", liveType: "13")
            ])
        ]

        let selection = RoomPlaybackResolver.preferredInitialSelection(in: playArgs)
        #expect(selection?.qualityIndex == 2)
        #expect(selection?.quality.title == "1080p")
    }

    @Test("Skips empty source placeholder when choosing initial stream")
    func skipsEmptySourcePlaceholder() {
        let playArgs = [
            LiveQualityModel(cdn: "default", qualitys: [
                quality(title: "原画", qn: 10_000, url: "", liveType: "13"),
                quality(title: "1080p", qn: 1080, url: "https://example.com/1080.m3u8", liveType: "13")
            ])
        ]

        let selection = RoomPlaybackResolver.preferredInitialSelection(in: playArgs)
        #expect(selection?.qualityIndex == 1)
        #expect(selection?.quality.title == "1080p")
    }

    @Test("Skips audio-only stream when video stream is available")
    func skipsAudioWhenVideoExists() {
        let playArgs = [
            LiveQualityModel(cdn: "default", qualitys: [
                quality(title: "Audio", qn: 9999, url: "https://example.com/audio.m3u8", liveType: "13"),
                quality(title: "720p", qn: 720, url: "https://example.com/720.m3u8", liveType: "13")
            ])
        ]

        let selection = RoomPlaybackResolver.preferredInitialSelection(in: playArgs)
        #expect(selection?.qualityIndex == 1)
        #expect(selection?.quality.title == "720p")
    }

    @Test("Allows refresh-only quality as initial stream candidate")
    func allowsRefreshOnlyQualityCandidate() {
        let playArgs = [
            LiveQualityModel(cdn: "default", qualitys: [
                quality(title: "720p", qn: 720, url: "https://example.com/720.m3u8", liveType: "13"),
                quality(
                    title: "原画",
                    qn: 10_000,
                    url: "",
                    liveType: "13",
                    playbackHints: LivePlaybackHints(selectionBehavior: .refreshOnSelect)
                )
            ])
        ]

        let selection = RoomPlaybackResolver.preferredInitialSelection(in: playArgs)
        #expect(selection?.qualityIndex == 1)
        #expect(selection?.quality.title == "原画")
    }
}

private func manifest(
    pluginId: String,
    liveType: String,
    loginFlow: ManifestLoginFlow? = nil,
    auth: ManifestAuth? = nil
) -> LiveParsePluginManifest {
    LiveParsePluginManifest(
        pluginId: pluginId,
        version: "1.0.0",
        apiVersion: 1,
        displayName: pluginId,
        liveTypes: [liveType],
        entry: "index.js",
        auth: auth,
        loginFlow: loginFlow
    )
}

private func cookie(
    name: String,
    value: String,
    domain: String,
    expires: Date? = Date(timeIntervalSinceNow: 3600)
) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .domain: domain,
        .path: "/"
    ]
    if let expires {
        properties[.expires] = expires
    }
    return HTTPCookie(properties: properties)!
}

private func quality(
    title: String,
    qn: Int,
    url: String,
    liveType: String,
    playbackHints: LivePlaybackHints? = nil
) -> LiveQualityDetail {
    LiveQualityDetail(
        roomId: "room",
        title: title,
        qn: qn,
        url: url,
        liveCodeType: .hls,
        liveType: LiveType(rawValue: liveType)!,
        userAgent: nil,
        headers: nil,
        requestContext: nil,
        playbackHints: playbackHints
    )
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
