#if DEBUG
import AngelLiveCore
import AngelLiveDependencies
import Combine
import SwiftUI

@MainActor @Observable
final class TVUIAuditSettings {
    var showDanmu = true
    var showColorDanmu = true
    var isDanmakuTranslationEnabled = false
    var danmuFontSize = 50
    var danmuAlpha = 0.8
    var danmuAlphaString = "0.8"
    var danmuSpeed = 0.7
    var danmuSpeedIndex = 1
    var danmuAreaIndex = 2
    var defaultPlaybackQuality: DefaultPlaybackQuality = .highest
    var blockedKeywords = ["重复消息", "剧透"]
}

struct TVUIAuditDemoApp: App {
    static let isEnabled: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--tv-ui-audit-demo") &&
            !arguments.contains { $0.hasPrefix("--ui-test") }
    }()

    var body: some Scene {
        WindowGroup {
            TVUIAuditMenu(fixtures: .current)
                .environment(\.usesFullUI, true)
                .environment(\.tvFullUIBackNavigation, true)
                .environment(\.tvUIAuditSubtitleLanguages, TVUIAuditFixtures.subtitleLanguages)
                .supportDiagnosticsEnabled(false)
        }
    }
}

private enum TVUIAuditDestination: String, CaseIterable, Identifiable {
    case player, capability, error, account, subtitles

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .player: "播放器"
        case .capability: "插件能力与版本"
        case .error: "长文本错误"
        case .account: "多平台登录恢复"
        case .subtitles: "翻译与字幕"
        }
    }

    static var initial: Self? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--tv-ui-audit-page"),
              arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

private struct TVUIAuditMenu: View {
    let fixtures: TVUIAuditFixtures
    @State private var destination = TVUIAuditDestination.initial
    @State private var lastDestination = TVUIAuditDestination.initial ?? .player
    @State private var translation = TVUIAuditTranslationFixture()
    @FocusState private var focusedDestination: TVUIAuditDestination?

    var body: some View {
        NavigationStack {
            List(TVUIAuditDestination.allCases) { item in
                Button(item.title) {
                    lastDestination = item
                    destination = item
                }
                .focused($focusedDestination, equals: item)
                .accessibilityIdentifier("tv.audit.open.\(item.rawValue)")
            }
            .navigationTitle("tvOS 界面审查")
            .defaultFocus($focusedDestination, lastDestination)
        }
        .fullScreenCover(item: $destination, onDismiss: {
            focusedDestination = lastDestination
        }) { item in
            switch item {
            case .player:
                TVUIAuditPlayer(
                    room: RoomInfoViewModel(tvUIAuditRoom: fixtures.room,
                                            appViewModel: fixtures.app, playArgs: fixtures.playArgs)
                )
            case .capability:
                TVPlatformCapabilityContent(snapshot: TVUIAuditFixtures.capability)
                    .accessibilityIdentifier("tv.audit.capability")
            case .error:
                TVUIAuditError { destination = nil }
            case .account:
                TVUIAuditAccountRecovery(platforms: TVUIAuditFixtures.loginPlatforms)
            case .subtitles:
                GeometryReader { geometry in
                    TranslationSettingView(auditFixture: translation)
                        .environment(\.tvUIAuditSpeechSettings, fixtures.speechSettings)
                        .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tv.audit.subtitles")
                }
                .background(Color.black.ignoresSafeArea())
                .interactiveDismissDisabled()
                .tvFullUIBackCommand { destination = nil }
            }
        }
    }
}

private struct TVUIAuditPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var room: RoomInfoViewModel
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var sleepTimer: TVPlaybackSleepTimer?
    @State private var recovery: AuthenticationRecoveryRequest?
    @State private var accountRecoveryIsActive = false

    init(room: RoomInfoViewModel) {
        _room = State(initialValue: room)
    }

    var body: some View {
        PlayerControlView(
            playerCoordinator: coordinator,
            showsRoomBanner: true,
            sleepTimer: sleepTimer,
            accountRecoveryIsActive: accountRecoveryIsActive,
            onSetSleepTimer: setSleepTimer,
            onBottomControlVisibilityChange: { _ in },
            onRouteOnDemandRoom: { _ in }
        )
        .background { Color.black.ignoresSafeArea() }
        .ignoresSafeArea(.container)
        .environment(\.tvUIAuditStatistics, true)
        .environment(room)
        .environment(room.appViewModel)
        .accessibilityIdentifier("tv.audit.player")
        .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.playerEndPlay)) { _ in
            dismiss()
        }
        .onChange(of: room.pendingLoginRequest?.id) {
            guard let request = room.pendingLoginRequest else { return }
            accountRecoveryIsActive = true
            recovery = request
            room.pendingLoginRequest = nil
        }
        .onChange(of: room.subtitlePlayback.activationID, initial: true) {
            let subtitles = room.subtitlePlayback
            guard subtitles.phase == .preparing else { return }
            let language = subtitles.sourceLanguage
            subtitles.apply(.init(phase: language == nil ? .manualSelectionRequired : .transcribing,
                                  sourceLanguage: language),
                            activationID: subtitles.activationID)
        }
        .fullScreenCover(item: $recovery, onDismiss: { accountRecoveryIsActive = false }) { request in
            let platforms = TVUIAuditFixtures.loginPlatforms.filter { request.pluginIDs.contains($0.pluginId) }
            TVUIAuditAccountRecovery(platforms: platforms)
        }
    }

    private func setSleepTimer(_ minutes: Int) {
        sleepTimer = minutes == 0 ? nil : .init(
            minutes: minutes,
            deadline: .now.advanced(by: .seconds(minutes * 60))
        )
    }
}

private struct TVUIAuditError: View {
    let onDismiss: () -> Void
    @State private var showingRecovery = false
    @State private var didRetry = false

    var body: some View {
        ErrorView(
            message: didRetry ? TVUIAuditFixtures.retryMessage : TVUIAuditFixtures.errorMessage,
            errorCode: "FIXTURE-001",
            detailMessage: TVUIAuditFixtures.errorDetail,
            qrCodeURL: "https://help.example.invalid/playback",
            showRetry: true,
            showLoginButton: true,
            onDismiss: onDismiss,
            onRetry: { didRetry = true },
            onLogin: { showingRecovery = true }
        )
        .accessibilityIdentifier("tv.audit.error")
        .fullScreenCover(isPresented: $showingRecovery) {
            TVUIAuditAccountRecovery(platforms: TVUIAuditFixtures.loginPlatforms)
        }
    }
}

private struct TVUIAuditAccountRecovery: View {
    let platforms: [LoginPlatformEntry]

    var body: some View {
        AccountManagementView(auditRecoveryPlatforms: platforms)
            .frame(maxWidth: 1000)
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("tv.audit.account")
    }
}

@MainActor
struct TVUIAuditFixtures {
    let app: AppState
    let room: LiveModel
    let playArgs: [LiveQualityModel]
    let speechSettings: LiveSubtitleSettings

    static let current: Self = {
        do {
            // The existing history harness creates a fresh suite and cache subtree for each UUID.
            let arguments = ["--ui-testing", "--ui-test-run-id", UUID().uuidString, "--ui-test-reset"]
            guard let configuration = try UITestLaunchConfiguration.current(arguments: arguments) else {
                fatalError("Unable to configure the tvOS UI audit sandbox")
            }
            let context = try UITestHistoryContext.prepare(configuration: configuration)
            let args = try JSONDecoder().decode([LiveQualityModel].self, from: Data(playbackJSON.utf8))
            guard let speechDefaults = UserDefaults(suiteName: "dev.angellive.tv-ui-audit-speech.\(configuration.runID.uuidString)") else {
                fatalError("Unable to configure the tvOS UI audit speech settings")
            }
            return Self(
                app: AppState(historyTestContext: context),
                room: LiveModel(
                    userName: "示例主播（审查样本）", roomTitle: "海岸自然观察与潮汐记录",
                    roomCover: "", userHeadImg: "", liveType: "fixture.live", liveState: LiveState.live.rawValue,
                    userId: "fixture-user", roomId: "fixture-room", liveWatchedCount: nil
                ),
                playArgs: args,
                speechSettings: LiveSubtitleSettings(defaults: speechDefaults)
            )
        } catch {
            fatalError("Unable to prepare the tvOS UI audit sandbox")
        }
    }()

    static let subtitleLanguages = ["en-US", "ja-JP", "ko-KR", "zh-CN"].map { Locale(identifier: $0) }

    static let loginPlatforms: [LoginPlatformEntry] = [
        .init(pluginId: "fixture.login-a", displayName: "示例直播来源 A", liveType: "fixture.live-a",
              loginFlow: .init(loginURL: "https://login.example.invalid/", cookieDomains: [], authSignalCookies: []),
              auth: nil, version: "1.4.0"),
        .init(pluginId: "fixture.login-b", displayName: "示例直播来源 B", liveType: "fixture.live-b",
              auth: .init(credentialKinds: ["token"]), version: "2.1.0")
    ]

    static var loginPluginIDs: [String] { loginPlatforms.map(\.pluginId) }

    static let capability = TVPlatformCapabilityContent.Snapshot(
        name: "示例直播来源 A",
        installedVersion: "1.4.0",
        latestVersion: "1.5.0",
        hasUpdate: true,
        changelog: [
            "改善直播线路的初始选择和切换后的状态展示。",
            "补充登录后可用画质的说明。"
        ],
        features: [
            .init(feature: .categories, status: .available, auth: .none),
            .init(feature: .rooms, status: .available, auth: .none),
            .init(feature: .playback, status: .available,
                  auth: .init(level: .enhances, reason: "登录后可用更多清晰度。")),
            .init(feature: .search, status: .available,
                  auth: .init(level: .required, reason: "登录后可搜索此来源的直播间。")),
            .init(feature: .roomDetail, status: .available, auth: .none),
            .init(feature: .liveState, status: .available, auth: .none),
            .init(feature: .shareResolve, status: .partial("支持直播间链接"), auth: .none),
            .init(feature: .danmaku, status: .partial("部分房间可用"), auth: .none),
            .init(feature: .homeFeed, status: .available, auth: .none),
            .init(feature: .vod, status: .unavailable, auth: .none)
        ]
    )

    static let errorMessage = """
    当前直播间暂时无法加载。可以先切换到其他线路，或在确认账号状态后重新尝试。若问题持续出现，请在下面查看详细说明。

    这个错误示例包含多段文字，用来核对较长的提示在电视上是否可以完整阅读，以及返回、登录、重试和查看详情是否始终可达。
    """

    static let retryMessage = "重试完成。\n\n" + errorMessage

    static let errorDetail = (1...16).map { index in
        "检查项 \(index)　示例线路状态未就绪。请返回播放设置检查其他线路，或完成账号恢复后重试。"
    }.joined(separator: "\n\n")

    private static let playbackJSON = #"""
    [
      {"cdn":"source-a","displayName":"主线路","qualitys":[
        {"roomId":"fixture-room","title":"高清","qn":1080,"url":"https://stream.example.invalid/fixture-live-high-definition-sample-playlist.m3u8","liveCodeType":"m3u8","liveType":"fixture.live"},
        {"roomId":"fixture-room","title":"原画","qn":2160,"url":"","liveCodeType":"m3u8","liveType":"fixture.live",
         "playbackHints":{"authLimit":{"reason":"login_required","message":"登录后可使用原画。"}}},
        {"roomId":"fixture-room","title":"流畅","qn":480,"url":"https://stream.example.invalid/smooth.m3u8","liveCodeType":"m3u8","liveType":"fixture.live"}
      ]},
      {"cdn":"source-b","displayName":"备用线路","qualitys":[
        {"roomId":"fixture-room","title":"高清","qn":1080,"url":"https://stream.example.invalid/backup.m3u8","liveCodeType":"m3u8","liveType":"fixture.live"},
        {"roomId":"fixture-room","title":"超清","qn":1440,"url":"","liveCodeType":"m3u8","liveType":"fixture.live",
         "playbackHints":{"authLimit":{"reason":"membership_required","message":"此清晰度需要会员。"}}}
      ]}
    ]
    """#
}
#endif
