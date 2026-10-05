import Foundation
import Testing
@testable import AngelLiveCore

/// 插件错误 / 登录协议 v1 的宿主侧行为。
@Suite("Plugin error & auth protocol v1")
struct PluginErrorProtocolTests {
    private static func pluginError(_ code: String, message: String = "msg", context: [String: String] = [:]) -> LiveParsePluginError {
        var payload: [String: Any] = ["code": code, "message": message]
        if !context.isEmpty { payload["context"] = context }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return LiveParsePluginError.fromJSException("Error: LP_PLUGIN_ERROR:" + String(decoding: data, as: UTF8.self))
    }

    private static func standardCode(_ error: LiveParsePluginError) -> LiveParsePluginStandardErrorCode? {
        if case .standardized(let value) = error { return value.code }
        return nil
    }

    // MARK: - code 解析

    @Test("legacy codes map onto standard codes", arguments: [
        ("REQUIRES_AUTH", LiveParsePluginStandardErrorCode.authRequired),
        ("AUTH", .authRequired),
        ("AUTH_FAILED", .authRequired),
        ("INVALID_INPUT", .invalidArgs),
        ("INVALID_STATE", .invalidArgs),
        ("DECODE_FAILED", .parse),
        ("OFFLINE", .notLive),
        ("STREAM_UNAVAILABLE", .notLive),
        ("406", .blocked),
        ("UPSTREAM_RESTRICTED", .blocked),
        ("REQUEST_FAILED", .network),
        ("DEPRECATED", .unsupported),
        ("SIGNING_FAILED", .unsupported),
        ("SIGNING_UNAVAILABLE", .unsupported)
    ])
    func legacyAliases(raw: String, expected: LiveParsePluginStandardErrorCode) {
        #expect(Self.standardCode(Self.pluginError(raw)) == expected)
    }

    @Test("standard codes still win and unknown codes fall back to UNKNOWN")
    func standardAndUnknownCodes() {
        #expect(Self.standardCode(Self.pluginError("NOT_LIVE")) == .notLive)
        #expect(Self.standardCode(Self.pluginError("AUTH_REQUIRED")) == .authRequired)
        #expect(Self.standardCode(Self.pluginError("SOMETHING_NEW")) == .unknown)
    }

    @Test("numeric legacy code is accepted")
    func numericCode() {
        let error = LiveParsePluginError.fromJSException(#"LP_PLUGIN_ERROR:{"code":406,"message":"x"}"#)
        #expect(Self.standardCode(error) == .blocked)
    }

    @Test("NOT_LIVE parses with message and context")
    func notLiveParse() {
        let error = Self.pluginError("NOT_LIVE", message: "主播已下播", context: ["api": "play_info"])
        guard case .standardized(let value) = error else {
            Issue.record("expected standardized error")
            return
        }
        #expect(value.code == .notLive)
        #expect(value.message == "主播已下播")
        #expect(value.context["api"] == "play_info")
        #expect(error.isNotLive)
        #expect(!error.isAuthRequired)
    }

    // MARK: - isAuthRequired / isLoginSuggested

    @Test("406 text is no longer treated as auth required")
    func code406TextIsNotAuth() {
        let jsError = LiveParsePluginError.jsException(#"request failed "code":406"#)
        #expect(!jsError.isAuthRequired)
        let detailError = LiveParseError.liveParseError("请求失败", "错误代码: 406")
        #expect(!detailError.isAuthRequired)
        // -352 风控仍按需要登录处理
        let biliError = LiveParseError.liveParseError("请求失败", "错误代码: -352")
        #expect(biliError.isAuthRequired)
        // 旧 406 code 现在归为 BLOCKED，不再是登录错误
        #expect(!Self.pluginError("406").isAuthRequired)
    }

    @Test("BLOCKED with loginMayHelp suggests login")
    func loginSuggested() {
        let suggested = Self.pluginError("BLOCKED", message: "快手暂时限制访问", context: ["loginMayHelp": "true"])
        #expect(suggested.isLoginSuggested)
        #expect(!suggested.isAuthRequired)
        #expect(suggested.showsLoginAction)

        let plainBlocked = Self.pluginError("BLOCKED")
        #expect(!plainBlocked.isLoginSuggested)
        #expect(!plainBlocked.showsLoginAction)

        let otherCode = Self.pluginError("UPSTREAM", context: ["loginMayHelp": "true"])
        #expect(!otherCode.isLoginSuggested)

        #expect(Self.pluginError("AUTH_REQUIRED").showsLoginAction)
        #expect(PluginAuthenticationRequiredError(pluginIDs: ["a"]).showsLoginAction)
    }

    // MARK: - liveParseMessage

    @Test("AUTH_REQUIRED shows Chinese plugin message, falls back for ASCII text")
    func authMessageBranches() {
        let chinese = Self.pluginError("AUTH_REQUIRED", message: "B站房间列表需要登录后查看")
        #expect(chinese.liveParseMessage == "B站房间列表需要登录后查看")

        let ascii = Self.pluginError("AUTH_REQUIRED", message: "requires cookie")
        #expect(ascii.liveParseMessage == "当前内容需要登录账号后才能访问，请前往设置页登录后重试。")

        let hostError = PluginAuthenticationRequiredError(pluginIDs: ["a"])
        #expect(hostError.liveParseMessage == "当前内容需要登录账号后才能访问，请前往设置页登录后重试。")
    }

    @Test("NOT_LIVE message uses plugin text or a default")
    func notLiveMessage() {
        #expect(Self.pluginError("NOT_LIVE", message: "主播休息中").liveParseMessage == "主播休息中")
        let empty = LiveParsePluginError.standardized(.init(code: .notLive, message: "  "))
        #expect(empty.liveParseMessage == "主播当前未开播")
    }

    // MARK: - capabilities.auth

    @Test("capability auth level and reason are parsed")
    func capabilityAuthParsing() throws {
        let manifest = Data(#"""
        {"apiVersion":1,"capabilities":{
          "rooms":{"status":"available","auth":"required","reason":"房间列表需要登录后查看"},
          "playback":{"status":"available","auth":"ENHANCES","reason":"登录后可看原画"},
          "search":{"status":"available","auth":"none","reason":"x"},
          "danmaku":{"status":"available","auth":"bogus"},
          "categories":"available"
        }}
        """#.utf8)

        let auth = PlatformCapability.parseAuthRequirements(from: manifest)
        #expect(auth[.rooms] == FeatureAuthRequirement(level: .required, reason: "房间列表需要登录后查看"))
        #expect(auth[.playback] == FeatureAuthRequirement(level: .enhances, reason: "登录后可看原画"))
        #expect(auth[.search] == nil)
        #expect(auth[.danmaku] == nil)
        #expect(auth[.categories] == nil)

        // auth 字段不影响原有 status 解析
        let statuses = try #require(PlatformCapability.parseCapabilities(from: manifest))
        #expect(statuses[.rooms]?.isSupported == true)
        #expect(statuses[.categories]?.isSupported == true)

        #expect(FeatureAuthLevel.required.badgeTitle == "需登录")
        #expect(FeatureAuthLevel.enhances.badgeTitle == "登录增强")
        #expect(FeatureAuthLevel.none.badgeTitle == nil)
    }

    @Test("unknown platform reports no auth requirement")
    func unknownPlatformAuth() {
        let result = PlatformCapability.auth(for: .rooms, liveType: LiveType(rawValue: "__no_such_platform__")!)
        #expect(result.level == .none)
        #expect(result.reason == nil)
    }

    // MARK: - playbackHints.authLimit

    @Test("authLimit decodes and survives an encode round trip")
    func authLimitDecode() throws {
        let data = Data(#"{"streamFormat":"flv","authLimit":{"reason":"login_required","message":"登录后可看原画"}}"#.utf8)
        let hints = try JSONDecoder().decode(LivePlaybackHints.self, from: data)
        #expect(hints.streamFormat == .flv)
        #expect(hints.authLimit == LivePlaybackAuthLimit(reason: "login_required", message: "登录后可看原画"))
        #expect(hints.authLimit?.requiresLogin == true)

        let roundTrip = try JSONDecoder().decode(LivePlaybackHints.self, from: JSONEncoder().encode(hints))
        #expect(roundTrip.authLimit == hints.authLimit)
    }

    @Test("wrong-typed authLimit does not break hint decoding")
    func authLimitWrongType() throws {
        let data = Data(#"{"streamFormat":"flv","isLive":true,"authLimit":"login_required"}"#.utf8)
        let hints = try JSONDecoder().decode(LivePlaybackHints.self, from: data)
        #expect(hints.streamFormat == .flv)
        #expect(hints.isLive == true)
        #expect(hints.authLimit == nil)

        let partial = Data(#"{"authLimit":{"message":123}}"#.utf8)
        let partialHints = try JSONDecoder().decode(LivePlaybackHints.self, from: partial)
        #expect(partialHints.authLimit == LivePlaybackAuthLimit(reason: "login_required", message: nil))
    }

    // MARK: - 自动选画质

    private func quality(_ title: String, locked: String? = nil) -> LiveQualityDetail {
        LiveQualityDetail(
            roomId: "room",
            title: title,
            qn: 0,
            url: "https://example.com/\(title).flv",
            liveCodeType: .flv,
            liveType: LiveType(rawValue: "test") ?? .placeholder,
            playbackHints: locked.map { LivePlaybackHints(authLimit: LivePlaybackAuthLimit(reason: $0)) }
        )
    }

    @Test("automatic selection skips locked qualities")
    func automaticSelectionSkipsLocked() {
        let args = [
            LiveQualityModel(cdn: "a", qualitys: [
                quality("原画", locked: "login_required"),
                quality("超清", locked: "membership_required"),
                quality("高清"),
                quality("流畅")
            ])
        ]
        let selection = RoomPlaybackResolver.automaticSelection(in: args, preferredCdnIndex: 0, preferredQualityIndex: 0)
        #expect(selection.cdnIndex == 0)
        #expect(selection.qualityIndex == 2)

        // 当前档未锁定时保持不变
        let keep = RoomPlaybackResolver.automaticSelection(in: args, preferredCdnIndex: 0, preferredQualityIndex: 3)
        #expect(keep.qualityIndex == 3)
    }

    @Test("automatic selection looks lower first, then higher, then other lines")
    func automaticSelectionOrdering() {
        let args = [
            LiveQualityModel(cdn: "a", qualitys: [
                quality("原画"),
                quality("超清", locked: "login_required")
            ]),
            LiveQualityModel(cdn: "b", qualitys: [
                quality("原画", locked: "login_required"),
                quality("高清")
            ])
        ]
        let sameLine = RoomPlaybackResolver.automaticSelection(in: args, preferredCdnIndex: 0, preferredQualityIndex: 1)
        #expect(sameLine.cdnIndex == 0)
        #expect(sameLine.qualityIndex == 0)

        let allLockedLine = [
            LiveQualityModel(cdn: "a", qualitys: [quality("原画", locked: "login_required")]),
            LiveQualityModel(cdn: "b", qualitys: [quality("高清")])
        ]
        let otherLine = RoomPlaybackResolver.automaticSelection(in: allLockedLine, preferredCdnIndex: 0, preferredQualityIndex: 0)
        #expect(otherLine.cdnIndex == 1)
        #expect(otherLine.qualityIndex == 0)

        let pinned = RoomPlaybackResolver.automaticSelection(
            in: allLockedLine,
            preferredCdnIndex: 0,
            preferredQualityIndex: 0,
            allowsOtherCDN: false
        )
        #expect(pinned.cdnIndex == 0)
        #expect(pinned.qualityIndex == 0)
    }

    @Test("all locked keeps the original clamped selection")
    func automaticSelectionAllLocked() {
        let args = [
            LiveQualityModel(cdn: "a", qualitys: [
                quality("原画", locked: "login_required"),
                quality("高清", locked: "login_required")
            ])
        ]
        let selection = RoomPlaybackResolver.automaticSelection(in: args, preferredCdnIndex: 3, preferredQualityIndex: 9)
        #expect(selection.cdnIndex == 0)
        #expect(selection.qualityIndex == 1)
        let empty = RoomPlaybackResolver.automaticSelection(in: [], preferredCdnIndex: 0, preferredQualityIndex: 0)
        #expect(empty.cdnIndex == 0)
        #expect(empty.qualityIndex == 0)
    }

    @Test("lock action follows authLimit reason")
    func lockActions() {
        #expect(RoomPlaybackResolver.lockAction(for: quality("高清")) == nil)
        #expect(RoomPlaybackResolver.lockAction(for: quality("原画", locked: "login_required")) == .requestLogin(message: "登录后可用"))
        #expect(RoomPlaybackResolver.lockAction(for: quality("原画", locked: "membership_required")) == .showMessage("当前账号暂无法观看该画质"))
        #expect(RoomPlaybackResolver.lockBadgeTitle(for: quality("原画", locked: "login_required")) == "登录后可用")
    }
}
