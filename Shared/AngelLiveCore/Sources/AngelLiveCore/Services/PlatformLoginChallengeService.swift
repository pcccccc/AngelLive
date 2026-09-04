import Foundation
import Observation

public struct LoginChallengePresentation: Equatable, Sendable {
    public let qrContent: String
    public let qrImageData: Data?
    public let hint: String
    public let expiresAt: Date?
    public let refreshCount: Int

    public init(
        qrContent: String,
        hint: String,
        expiresAt: Date?,
        refreshCount: Int,
        qrImageData: Data? = nil
    ) {
        self.qrContent = qrContent
        self.qrImageData = qrImageData
        self.hint = hint
        self.expiresAt = expiresAt
        self.refreshCount = refreshCount
    }
}

public struct LoginChallengeSuccess: Equatable, Sendable {
    public let userId: String?
    public let userName: String?

    public init(userId: String? = nil, userName: String? = nil) {
        self.userId = userId
        self.userName = userName
    }
}

public enum LoginChallengeBootstrapState: String, Codable, Equatable, Sendable {
    case ok
    case timeout
    case failed
    case skipped
}

/// Non-secret summary passed to `createLoginChallenge` after host-side preparation.
public struct LoginChallengeBootstrapResult: Codable, Equatable, Sendable {
    public let state: LoginChallengeBootstrapState
    public let cookieNames: [String]
    public let navigations: Int?
    public let elapsedMs: Int?

    public init(
        state: LoginChallengeBootstrapState,
        cookieNames: [String] = [],
        navigations: Int? = nil,
        elapsedMs: Int? = nil
    ) {
        self.state = state
        self.cookieNames = Array(Set(cookieNames)).sorted()
        self.navigations = navigations
        self.elapsedMs = elapsedMs
    }

    static var skipped: Self {
        Self(state: .skipped)
    }

    var pluginPayload: [String: Any] {
        var payload: [String: Any] = [
            "state": state.rawValue,
            "cookieNames": cookieNames
        ]
        if let navigations { payload["navigations"] = navigations }
        if let elapsedMs { payload["elapsedMs"] = elapsedMs }
        return payload
    }
}

public enum LoginChallengeVerificationKind: Codable, Equatable, Sendable {
    case smsCode
    case unsupported(String)

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = rawValue.lowercased() == "sms_code" ? .smsCode : .unsupported(rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .smsCode:
            try container.encode("sms_code")
        case .unsupported(let rawValue):
            try container.encode(rawValue)
        }
    }
}

/// Non-secret display metadata for a host-collected login verification step.
public struct LoginChallengeVerificationPresentation: Equatable, Sendable {
    public let kind: LoginChallengeVerificationKind
    public let prompt: String
    public let maskedDestination: String?
    public let codeLength: Int
    public let canResend: Bool
    public let resendAvailableAt: Date?
    public let errorMessage: String?

    public init(
        kind: LoginChallengeVerificationKind,
        prompt: String,
        maskedDestination: String?,
        codeLength: Int,
        canResend: Bool,
        resendAvailableAt: Date?,
        errorMessage: String? = nil
    ) {
        self.kind = kind
        self.prompt = prompt
        self.maskedDestination = maskedDestination
        self.codeLength = codeLength
        self.canResend = canResend
        self.resendAvailableAt = resendAvailableAt
        self.errorMessage = errorMessage
    }

    fileprivate func withError(_ errorMessage: String?) -> Self {
        Self(
            kind: kind,
            prompt: prompt,
            maskedDestination: maskedDestination,
            codeLength: codeLength,
            canResend: canResend,
            resendAvailableAt: resendAvailableAt,
            errorMessage: errorMessage
        )
    }
}

public struct LoginChallengeFailure: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case unsupported
        case timedOut
        case expired
        case invalidResponse
        case validation
        case plugin
    }

    public let kind: Kind
    public let message: String
    public let canRetry: Bool
    public let canFallbackToWebLogin: Bool

    public init(
        kind: Kind,
        message: String,
        canRetry: Bool,
        canFallbackToWebLogin: Bool
    ) {
        self.kind = kind
        self.message = message
        self.canRetry = canRetry
        self.canFallbackToWebLogin = canFallbackToWebLogin
    }
}

/// UI 订阅的单一登录挑战状态，避免多组布尔值形成互相矛盾的组合。
public enum PlatformLoginChallengeState: Equatable, Sendable {
    case idle
    case creating
    case presenting(LoginChallengePresentation)
    case scanned(LoginChallengePresentation)
    case awaitingVerification(LoginChallengeVerificationPresentation)
    case submittingVerification(LoginChallengeVerificationPresentation)
    case requestingVerificationCode(LoginChallengeVerificationPresentation)
    case validating
    case succeeded(LoginChallengeSuccess)
    case failed(LoginChallengeFailure)
}

public struct LoginChallengeCreateResponse: Codable, Equatable, Sendable {
    public let kind: ManifestLoginChallengeKind
    public let challengeId: String
    public let qrContent: String
    public let qrImage: String?
    public let pollIntervalMs: Int?
    public let initialPollDelayMs: Int?
    public let expiresAt: Double?
    public let hint: String?
    public let push: LoginChallengePushPlan?

    public init(
        kind: ManifestLoginChallengeKind,
        challengeId: String,
        qrContent: String,
        pollIntervalMs: Int? = nil,
        initialPollDelayMs: Int? = nil,
        expiresAt: Double? = nil,
        hint: String? = nil,
        qrImage: String? = nil,
        push: LoginChallengePushPlan? = nil
    ) {
        self.kind = kind
        self.challengeId = challengeId
        self.qrContent = qrContent
        self.qrImage = qrImage
        self.pollIntervalMs = pollIntervalMs.map { min(max($0, 1_000), 60_000) }
        self.initialPollDelayMs = initialPollDelayMs.map { min(max($0, 1_000), 60_000) }
        self.expiresAt = expiresAt
        self.hint = hint
        self.push = push
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case challengeId
        case qrContent
        case qrImage
        case pollIntervalMs
        case initialPollDelayMs
        case expiresAt
        case hint
        case push
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(ManifestLoginChallengeKind.self, forKey: .kind),
            challengeId: try container.decode(String.self, forKey: .challengeId),
            qrContent: try container.decode(String.self, forKey: .qrContent),
            pollIntervalMs: try container.decodeIfPresent(Int.self, forKey: .pollIntervalMs),
            initialPollDelayMs: try container.decodeIfPresent(Int.self, forKey: .initialPollDelayMs),
            expiresAt: try container.decodeIfPresent(Double.self, forKey: .expiresAt),
            hint: try container.decodeIfPresent(String.self, forKey: .hint),
            qrImage: try container.decodeIfPresent(String.self, forKey: .qrImage),
            push: try container.decodeIfPresent(LoginChallengePushPlan.self, forKey: .push)
        )
    }
}

public enum LoginChallengePushKind: Codable, Equatable, Sendable {
    case websocket
    case unsupported(String)

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = rawValue.lowercased() == "websocket" ? .websocket : .unsupported(rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .websocket:
            try container.encode("websocket")
        case .unsupported(let rawValue):
            try container.encode(rawValue)
        }
    }
}

public enum LoginChallengePushFrameType: String, Codable, Equatable, Sendable {
    case binary
    case text
}

/// Optional v2 extension for a host-managed login push connection.
public struct LoginChallengePushPlan: Codable, Equatable, Sendable {
    public let kind: LoginChallengePushKind
    public let url: String
    public let frameType: LoginChallengePushFrameType
    public let pingIntervalMs: Int?

    public init(
        kind: LoginChallengePushKind,
        url: String,
        frameType: LoginChallengePushFrameType,
        pingIntervalMs: Int? = nil
    ) {
        self.kind = kind
        self.url = url
        self.frameType = frameType
        self.pingIntervalMs = pingIntervalMs.map { min(max($0, 1_000), 60_000) }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case url
        case frameType
        case pingIntervalMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(LoginChallengePushKind.self, forKey: .kind),
            url: try container.decode(String.self, forKey: .url),
            frameType: try container.decode(LoginChallengePushFrameType.self, forKey: .frameType),
            pingIntervalMs: try container.decodeIfPresent(Int.self, forKey: .pingIntervalMs)
        )
    }
}

enum LoginChallengePushEventKind: String, Sendable {
    case message
    case tick
}

struct LoginChallengePushFrame: Codable, Equatable, Sendable {
    let type: LoginChallengePushFrameType
    let text: String?
    let bytesBase64: String?

    init(type: LoginChallengePushFrameType, text: String? = nil, bytesBase64: String? = nil) {
        self.type = type
        self.text = text
        self.bytesBase64 = bytesBase64
    }

    init(text: String) {
        self.init(type: .text, text: text)
    }

    init(binary data: Data) {
        self.init(type: .binary, bytesBase64: data.base64EncodedString())
    }

    var isValid: Bool {
        switch type {
        case .binary:
            return text == nil && bytesBase64.flatMap { Data(base64Encoded: $0) } != nil
        case .text:
            return bytesBase64 == nil && text != nil
        }
    }
}

struct LoginChallengePushEvent: Sendable {
    let kind: LoginChallengePushEventKind
    let frame: LoginChallengePushFrame?
}

struct LoginChallengePushAction: Codable, Equatable, Sendable {
    let pollNow: Bool?
    let send: [LoginChallengePushFrame]?
    let close: Bool?
}

final class LoginChallengePushHandle: Sendable {
    let pollSignals: AsyncStream<Void>
    private let closeAction: @Sendable () async -> Void
    private let cancelAction: @Sendable () -> Void

    init(
        pollSignals: AsyncStream<Void>,
        close: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () -> Void
    ) {
        self.pollSignals = pollSignals
        closeAction = close
        cancelAction = cancel
    }

    func close() async {
        await closeAction()
    }

    func cancel() {
        cancelAction()
    }
}

public enum LoginChallengePollState: String, Codable, Equatable, Sendable {
    case waiting
    case scanned
    case verificationRequired = "verification_required"
    case confirmed
    case expired
    case failed
}

public struct LoginChallengeVerificationDescriptor: Codable, Equatable, Sendable {
    public let kind: LoginChallengeVerificationKind
    public let verificationId: String
    public let prompt: String?
    public let maskedDestination: String?
    public let codeLength: Int?
    public let canResend: Bool?
    public let resendAfterMs: Int?

    public init(
        kind: LoginChallengeVerificationKind,
        verificationId: String,
        prompt: String? = nil,
        maskedDestination: String? = nil,
        codeLength: Int? = nil,
        canResend: Bool? = nil,
        resendAfterMs: Int? = nil
    ) {
        self.kind = kind
        self.verificationId = verificationId
        self.prompt = prompt
        self.maskedDestination = maskedDestination
        self.codeLength = codeLength
        self.canResend = canResend
        self.resendAfterMs = resendAfterMs
    }
}

public struct LoginChallengePollResponse: Codable, Equatable, Sendable {
    public let state: LoginChallengePollState
    public let rawStatus: Int?
    public let message: String?
    /// 兼容早期草案。nil 表示插件遵循“confirmed 即凭据就绪”的最终语义。
    public let credentialReady: Bool?
    public let uid: String?
    public let verification: LoginChallengeVerificationDescriptor?

    public init(
        state: LoginChallengePollState,
        rawStatus: Int? = nil,
        message: String? = nil,
        credentialReady: Bool? = nil,
        uid: String? = nil,
        verification: LoginChallengeVerificationDescriptor? = nil
    ) {
        self.state = state
        self.rawStatus = rawStatus
        self.message = message
        self.credentialReady = credentialReady
        self.uid = uid
        self.verification = verification
    }

    var hasContradictoryCredentialReadiness: Bool {
        guard let credentialReady else { return false }
        return credentialReady != (state == .confirmed)
    }
}

struct LoginChallengeVerificationRequest: Equatable, Sendable {
    let transactionId: String
    let challengeId: String
    let verificationId: String
    let code: String
}

struct LoginChallengeVerificationResendRequest: Equatable, Sendable {
    let transactionId: String
    let challengeId: String
    let verificationId: String
}

public enum LoginChallengeVerificationSubmitState: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
}

public struct LoginChallengeVerificationSubmitResponse: Codable, Equatable, Sendable {
    public let state: LoginChallengeVerificationSubmitState
    public let message: String?
    public let verification: LoginChallengeVerificationDescriptor?

    public init(
        state: LoginChallengeVerificationSubmitState,
        message: String? = nil,
        verification: LoginChallengeVerificationDescriptor? = nil
    ) {
        self.state = state
        self.message = message
        self.verification = verification
    }
}

struct LoginChallengeCreateRequest: Equatable, Sendable {
    let transactionId: String
    let platform: LoginChallengeHostPlatform
    let bootstrap: LoginChallengeBootstrapResult?
}

struct LoginChallengePollRequest: Equatable, Sendable {
    let transactionId: String
    let challengeId: String
}

struct PlatformLoginChallengeDependencies: Sendable {
    var beginTransaction: @Sendable (_ pluginId: String, _ expectedVersion: String) async throws -> String
    var promoteTransaction: @Sendable (_ pluginId: String, _ transactionId: String) async throws -> String
    var discardTransaction: @Sendable (_ pluginId: String, _ transactionId: String) async throws -> Void
    var supportsBootstrap: Bool
    var bootstrap: @Sendable (_ pluginId: String, _ transactionId: String, _ configuration: ManifestLoginChallengeBootstrap) async throws -> LoginChallengeBootstrapResult
    var create: @Sendable (_ pluginId: String, _ function: String, _ request: LoginChallengeCreateRequest) async throws -> LoginChallengeCreateResponse
    var poll: @Sendable (_ pluginId: String, _ function: String, _ request: LoginChallengePollRequest) async throws -> LoginChallengePollResponse
    var submitVerification: @Sendable (_ pluginId: String, _ function: String, _ request: LoginChallengeVerificationRequest) async throws -> LoginChallengeVerificationSubmitResponse
    var resendVerification: @Sendable (_ pluginId: String, _ function: String, _ request: LoginChallengeVerificationResendRequest) async throws -> LoginChallengeVerificationDescriptor
    var cancel: @Sendable (_ pluginId: String, _ function: String, _ request: LoginChallengePollRequest) async throws -> Void
    var openPush: @Sendable (_ pluginId: String, _ function: String, _ transactionId: String, _ challengeId: String, _ plan: LoginChallengePushPlan) async throws -> LoginChallengePushHandle
    var login: @Sendable (_ pluginId: String, _ transactionId: String, _ cookie: String, _ uid: String?, _ liveType: String, _ validationTimeout: Duration) async -> PlatformSessionValidationResult
    var releaseRuntimeLease: @Sendable (_ pluginId: String, _ transactionId: String) -> Void
    var credentialStatus: @Sendable (_ pluginId: String) async -> CredentialStatus?
    var didLogin: @MainActor @Sendable (_ pluginId: String) async -> Void
    var sleep: @Sendable (_ duration: Duration) async throws -> Void
    var now: @Sendable () -> Date
    var cleanupPluginCallTimeout: Duration
}

extension PlatformLoginChallengeDependencies {
    static var live: Self {
        let runtimeLeases = LoginChallengePluginRuntimeLeaseStore()
        return Self(
            beginTransaction: { pluginId, expectedVersion in
                let lease = try LiveParsePlugins.shared.runtimeLease(pluginId: pluginId)
                guard lease.version == expectedVersion else {
                    throw LiveParsePluginError.pluginNotFound(
                        "插件版本已更新，请重新打开登录页面"
                    )
                }
                let transactionId = try await LoginTransactionStore.shared.begin(pluginId: pluginId)
                runtimeLeases.bind(
                    lease,
                    pluginId: pluginId,
                    transactionId: transactionId
                )
                return transactionId
            },
            promoteTransaction: { pluginId, transactionId in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: transactionId
                )
                return try await LoginTransactionStore.shared.promote(
                    pluginId: pluginId,
                    transactionId: transactionId,
                    preferredDomains: lease.credentialDomains
                )
            },
            discardTransaction: { pluginId, transactionId in
                do {
                    try await LoginTransactionStore.shared.discard(
                        pluginId: pluginId,
                        transactionId: transactionId
                    )
                    runtimeLeases.release(pluginId: pluginId, transactionId: transactionId)
                } catch {
                    runtimeLeases.release(pluginId: pluginId, transactionId: transactionId)
                    throw error
                }
            },
            supportsBootstrap: LoginChallengeWebViewBootstrapRunner.isSupported,
            bootstrap: { pluginId, transactionId, configuration in
                try await LoginChallengeWebViewBootstrapRunner.run(
                    pluginId: pluginId,
                    transactionId: transactionId,
                    configuration: configuration
                )
            },
            create: { pluginId, function, request in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: request.transactionId
                )
                var payload: [String: Any] = [
                    "transactionId": request.transactionId,
                    "platform": request.platform.rawValue
                ]
                if let bootstrap = request.bootstrap {
                    payload["bootstrap"] = bootstrap.pluginPayload
                }
                return try await LiveParsePlugins.shared.callDecodable(
                    using: lease,
                    function: function,
                    payload: payload,
                    sensitive: true,
                    sensitiveConsolePolicy: .loginChallenge(.create)
                )
            },
            poll: { pluginId, function, request in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: request.transactionId
                )
                return try await LiveParsePlugins.shared.callDecodable(
                    using: lease,
                    function: function,
                    payload: [
                        "transactionId": request.transactionId,
                        "challengeId": request.challengeId
                    ],
                    sensitive: true,
                    sensitiveConsolePolicy: .loginChallenge(.poll)
                )
            },
            submitVerification: { pluginId, function, request in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: request.transactionId
                )
                return try await LiveParsePlugins.shared.callDecodable(
                    using: lease,
                    function: function,
                    payload: [
                        "transactionId": request.transactionId,
                        "challengeId": request.challengeId,
                        "verificationId": request.verificationId,
                        "code": request.code
                    ],
                    sensitive: true,
                    sensitiveConsolePolicy: .loginChallenge(.submitVerification)
                )
            },
            resendVerification: { pluginId, function, request in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: request.transactionId
                )
                return try await LiveParsePlugins.shared.callDecodable(
                    using: lease,
                    function: function,
                    payload: [
                        "transactionId": request.transactionId,
                        "challengeId": request.challengeId,
                        "verificationId": request.verificationId
                    ],
                    sensitive: true,
                    sensitiveConsolePolicy: .loginChallenge(.resendVerification)
                )
            },
            cancel: { pluginId, function, request in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: request.transactionId
                )
                let response: LoginChallengeCancelResponse = try await LiveParsePlugins.shared.callDecodable(
                    using: lease,
                    function: function,
                    payload: [
                        "transactionId": request.transactionId,
                        "challengeId": request.challengeId
                    ],
                    sensitive: true,
                    sensitiveConsolePolicy: .loginChallenge(.cancel)
                )
                guard response.ok else {
                    throw LiveParsePluginError.invalidReturnValue(
                        "\(function) returned ok=false"
                    )
                }
            },
            openPush: { pluginId, function, transactionId, challengeId, plan in
                let lease = try runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: transactionId
                )
                return try await LoginChallengePushCoordinator.open(
                    pluginId: pluginId,
                    transactionId: transactionId,
                    challengeId: challengeId,
                    plan: plan
                ) { event in
                    var payload: [String: Any] = [
                        "transactionId": transactionId,
                        "challengeId": challengeId,
                        "event": event.kind.rawValue
                    ]
                    if let frame = event.frame {
                        var encodedFrame: [String: Any] = ["type": frame.type.rawValue]
                        if let text = frame.text { encodedFrame["text"] = text }
                        if let bytesBase64 = frame.bytesBase64 {
                            encodedFrame["bytesBase64"] = bytesBase64
                        }
                        payload["frame"] = encodedFrame
                    }
                    return try await LiveParsePlugins.shared.callDecodable(
                        using: lease,
                        function: function,
                        payload: payload,
                        sensitive: true,
                        sensitiveConsolePolicy: .loginChallenge(.push)
                    )
                }
            },
            login: { pluginId, transactionId, cookie, uid, liveType, validationTimeout in
                guard let lease = try? runtimeLeases.lease(
                    pluginId: pluginId,
                    transactionId: transactionId
                ) else {
                    return .networkError("扫码登录运行时已失效")
                }
                return await PlatformSessionManager.shared.loginWithCookie(
                    pluginId: pluginId,
                    cookie: cookie,
                    uid: uid,
                    liveType: liveType,
                    source: .local,
                    validateBeforeSave: true,
                    preserveExistingSessionOnFailure: true,
                    requireExplicitValid: true,
                    validationTimeout: validationTimeout,
                    runtimeLease: lease
                )
            },
            releaseRuntimeLease: { pluginId, transactionId in
                runtimeLeases.release(pluginId: pluginId, transactionId: transactionId)
            },
            credentialStatus: { pluginId in
                await PlatformSessionManager.shared.fetchCredentialStatus(pluginId: pluginId)
            },
            didLogin: { pluginId in
                let syncService = PlatformCredentialSyncService.shared
                await syncService.refreshLoginStatus(pluginId: pluginId)
                if syncService.iCloudSyncEnabled {
                    _ = await syncService.syncAllToICloud()
                }
            },
            sleep: { duration in
                try await Task.sleep(for: duration)
            },
            now: Date.init,
            cleanupPluginCallTimeout: .seconds(2)
        )
    }
}

private struct LoginChallengeCancelResponse: Codable, Sendable {
    let ok: Bool
}

/// Pins one effective plugin runtime for the complete create → poll → optional
/// verification → cancel / validate lifecycle. Plugin reloads and pin changes may replace the manager's
/// cache, but they cannot splice a newer implementation into an active challenge.
private final class LoginChallengePluginRuntimeLeaseStore: @unchecked Sendable {
    private struct Entry {
        let pluginId: String
        let lease: LiveParsePluginRuntimeLease
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func bind(
        _ lease: LiveParsePluginRuntimeLease,
        pluginId: String,
        transactionId: String
    ) {
        lock.withLock {
            entries[transactionId] = Entry(pluginId: pluginId, lease: lease)
        }
    }

    func lease(
        pluginId: String,
        transactionId: String
    ) throws -> LiveParsePluginRuntimeLease {
        try lock.withLock {
            guard let entry = entries[transactionId], entry.pluginId == pluginId else {
                throw LiveParsePluginError.pluginNotFound(
                    "Login challenge runtime lease is no longer active"
                )
            }
            return entry.lease
        }
    }

    func release(pluginId: String, transactionId: String) {
        lock.withLock {
            guard entries[transactionId]?.pluginId == pluginId else { return }
            entries.removeValue(forKey: transactionId)
        }
    }
}

@MainActor
@Observable
public final class PlatformLoginChallengeService {
    public private(set) var state: PlatformLoginChallengeState = .idle

    @ObservationIgnored private let dependencies: PlatformLoginChallengeDependencies
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var lastRequest: StartRequest?
    @ObservationIgnored private var activeContext: OperationContext?
    @ObservationIgnored private var cleanupTasks: [String: CleanupRecord] = [:]
    @ObservationIgnored private var finalizedTransactionIds: Set<String> = []
    @ObservationIgnored private var cancelledChallengeKeys: Set<ChallengeCancellationKey> = []
    @ObservationIgnored private var verificationActionContinuation: AsyncStream<VerificationAction>.Continuation?

    public convenience init() {
        self.init(dependencies: .live)
    }

    init(dependencies: PlatformLoginChallengeDependencies) {
        self.dependencies = dependencies
    }

    public func start(entry: LoginPlatformEntry, platform: LoginChallengeHostPlatform) {
        guard let challenge = entry.loginChallenge else {
            transitionToUnsupported(message: "该插件未声明扫码登录能力")
            return
        }
        guard challenge.isSupportedByCurrentHost else {
            transitionToUnsupported(message: "该插件的扫码登录协议暂不受当前宿主支持")
            return
        }

        let request = StartRequest(entry: entry, challenge: challenge, platform: platform)
        lastRequest = request
        launch(request)
    }

    public func retry() {
        guard let lastRequest else { return }
        launch(lastRequest)
    }

    /// Sends a transient user-entered code to the active plugin challenge. The
    /// value is never stored in observable state or a platform session.
    public func submitVerificationCode(_ value: String) {
        guard case .awaitingVerification(let presentation) = state else { return }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.count <= Limits.verificationCodeCharacters else {
            state = .awaitingVerification(presentation.withError("请输入有效的短信验证码"))
            return
        }
        state = .submittingVerification(presentation.withError(nil))
        sendVerificationAction(.submit(code))
    }

    public func resendVerificationCode() {
        guard case .awaitingVerification(let presentation) = state,
              presentation.canResend,
              presentation.resendAvailableAt.map({ $0 <= dependencies.now() }) ?? true else {
            return
        }
        state = .requestingVerificationCode(presentation.withError(nil))
        sendVerificationAction(.resend)
    }

    public func cancel() {
        generation &+= 1
        finishVerificationActions()
        runningTask?.cancel()
        runningTask = nil
        let context = activeContext
        activeContext = nil
        // A succeeded state represents a durable host commit. Closing the UI
        // may stop nickname enrichment, but cannot roll the model back to idle.
        if case .succeeded = state {
            return
        }
        state = .idle
        guard let context else { return }
        scheduleCleanup(context)
    }

    func waitForCurrentOperation() async {
        let operation = runningTask
        await operation?.value
        // run 的 defer 可能在 operation 完成时才登记 cleanup，因此完成主任务后
        // 再取快照；按 transaction 建账，不能只等待最后一次 cleanup。
        let cleanups = cleanupTasks.values.map(\.task)
        for cleanup in cleanups {
            await cleanup.value
        }
    }

    private func transitionToUnsupported(message: String) {
        generation &+= 1
        lastRequest = nil
        runningTask?.cancel()
        runningTask = nil
        let context = activeContext
        activeContext = nil
        if let context {
            scheduleCleanup(context)
        }
        state = .failed(LoginChallengeFailure(
            kind: .unsupported,
            message: message,
            canRetry: false,
            canFallbackToWebLogin: true
        ))
    }

    private func launch(_ request: StartRequest) {
        generation &+= 1
        finishVerificationActions()
        let operationGeneration = generation
        let previousOperation = runningTask
        previousOperation?.cancel()
        let eagerCleanup: Task<Void, Never>?
        if let context = activeContext {
            eagerCleanup = scheduleCleanup(context)
        } else {
            eagerCleanup = nil
        }
        activeContext = nil
        state = .creating
        runningTask = Task { [weak self] in
            // 同一 stateful plugin runtime 的旧 create/poll 必须先退出，且它的
            // cancel/discard 要在新 begin 前完成，防止旧事务迟到后挤掉新事务。
            await previousOperation?.value
            await eagerCleanup?.value
            guard let self else { return }
            await self.waitForCleanup(pluginId: request.entry.pluginId)
            guard self.generation == operationGeneration, !Task.isCancelled else { return }
            await self.run(request, generation: operationGeneration)
        }
    }

    private func run(_ request: StartRequest, generation operationGeneration: UInt) async {
        var cleanupContext: OperationContext?
        var operationTransactionId: String?
        var activePush: LoginChallengePushHandle?
        defer {
            activePush?.cancel()
            finishVerificationActions()
            if let cleanupContext {
                scheduleCleanup(cleanupContext)
            }
            if let operationTransactionId {
                // A pending cleanup still needs the leased runtime to invoke
                // the matching version's cancel function. Promoted/finalized
                // paths have no cleanup, so release their lease directly.
                if cleanupContext == nil {
                    dependencies.releaseRuntimeLease(
                        request.entry.pluginId,
                        operationTransactionId
                    )
                }
                pruneTerminalBookkeeping(transactionId: operationTransactionId)
            }
            if generation == operationGeneration {
                activeContext = nil
                runningTask = nil
            }
        }

        do {
            try ensureCurrent(operationGeneration)
            let transactionId = try await dependencies.beginTransaction(
                request.entry.pluginId,
                request.entry.version
            )
            operationTransactionId = transactionId
            var context = OperationContext(
                pluginId: request.entry.pluginId,
                transactionId: transactionId,
                cancelFunction: request.challenge.functions.cancel,
                challengeId: nil
            )
            cleanupContext = context
            try ensureCurrent(operationGeneration)
            activeContext = context

            let deadline = dependencies.now().addingTimeInterval(TimeInterval(request.challenge.timeoutSeconds))
            var refreshCount = 0
            var bootstrapResult: LoginChallengeBootstrapResult?
            if let configuration = request.challenge.bootstrap,
               configuration.runnableURL != nil,
               dependencies.supportsBootstrap {
                do {
                    bootstrapResult = try await dependencies.bootstrap(
                        request.entry.pluginId,
                        transactionId,
                        configuration
                    )
                    try ensureCurrent(operationGeneration)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try ensureCurrent(operationGeneration)
                    bootstrapResult = LoginChallengeBootstrapResult(state: .failed)
                }
            }

            challengeLoop: while true {
                try ensureWithinDeadline(deadline, generation: operationGeneration)
                state = .creating

                let pluginId = request.entry.pluginId
                let createFunction = request.challenge.functions.create
                let createRequest = LoginChallengeCreateRequest(
                    transactionId: transactionId,
                    platform: request.platform,
                    bootstrap: bootstrapResult
                )
                let created = try await withPluginDeadline(deadline) {
                    try await self.dependencies.create(pluginId, createFunction, createRequest)
                }
                if bootstrapResult != nil {
                    bootstrapResult = .skipped
                }
                try ensureCurrent(operationGeneration)
                guard created.kind == .qrcode else {
                    throw ServiceError.invalidResponse("插件返回了不受支持的登录挑战类型")
                }

                let challengeId = created.challengeId
                let qrContent = created.qrContent
                let qrImageData = Self.pngData(from: created.qrImage)
                guard !challengeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !qrContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ServiceError.invalidResponse("插件返回的二维码挑战缺少必要字段")
                }
                if let rawImage = created.qrImage?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !rawImage.isEmpty,
                   qrImageData == nil {
                    throw ServiceError.invalidResponse("插件返回的二维码图片无效")
                }
                guard challengeId.utf8.count <= Limits.challengeIdBytes else {
                    throw ServiceError.invalidResponse("插件返回的登录挑战标识过长")
                }
                guard qrContent.utf8.count <= Limits.qrContentBytes else {
                    throw ServiceError.invalidResponse("插件返回的二维码内容过长")
                }
                if let qrImageData, qrImageData.count > Limits.qrImageBytes {
                    throw ServiceError.invalidResponse("插件返回的二维码图片过大")
                }

                context.challengeId = challengeId
                cleanupContext = context
                activeContext = context

                let expiresAt = Self.expirationDate(fromUnixMilliseconds: created.expiresAt)
                let presentation = LoginChallengePresentation(
                    qrContent: qrContent,
                    hint: Self.normalizedHint(created.hint)
                        ?? request.challenge.hint
                        ?? "请使用对应平台 App 扫描二维码并确认登录",
                    expiresAt: expiresAt,
                    refreshCount: refreshCount,
                    qrImageData: qrImageData
                )
                state = .presenting(presentation)

                let pollIntervalMs = created.pollIntervalMs ?? request.challenge.pollIntervalMs
                let initialPollDelayMs = created.initialPollDelayMs ?? pollIntervalMs
                if let pushPlan = created.push, pushPlan.kind == .websocket {
                    activePush = try? await dependencies.openPush(
                        pluginId,
                        request.challenge.functions.push,
                        transactionId,
                        challengeId,
                        pushPlan
                    )
                }
                var pollImmediately = false
                var isFirstPoll = true
                while true {
                    try ensureWithinDeadline(deadline, generation: operationGeneration)
                    if let expiresAt, expiresAt <= dependencies.now() {
                        await activePush?.close()
                        activePush = nil
                        if try await refreshIfAllowed(
                            request: request,
                            context: &context,
                            refreshCount: &refreshCount,
                            generation: operationGeneration
                        ) {
                            cleanupContext = context
                            activeContext = context
                            continue challengeLoop
                        }
                        throw ServiceError.expired
                    }

                    if pollImmediately {
                        pollImmediately = false
                    } else {
                        let delayMs = isFirstPoll ? initialPollDelayMs : pollIntervalMs
                        try await waitForPollingTurn(
                            delay: .milliseconds(delayMs),
                            push: activePush
                        )
                    }
                    isFirstPoll = false
                    try ensureWithinDeadline(deadline, generation: operationGeneration)

                    let pollFunction = request.challenge.functions.poll
                    let pollRequest = LoginChallengePollRequest(
                        transactionId: transactionId,
                        challengeId: challengeId
                    )
                    let polled = try await withPluginDeadline(deadline) {
                        try await self.dependencies.poll(pluginId, pollFunction, pollRequest)
                    }
                    try ensureCurrent(operationGeneration)

                    guard !polled.hasContradictoryCredentialReadiness else {
                        throw ServiceError.invalidResponse("插件返回了互相矛盾的凭据就绪状态")
                    }

                    switch polled.state {
                    case .waiting:
                        state = .presenting(presentation)
                    case .scanned:
                        state = .scanned(presentation)
                    case .verificationRequired:
                        guard request.challenge.minLoginChallengeProtocol >= 2 else {
                            throw ServiceError.invalidResponse(
                                "插件返回了协议 v2 二次验证状态，但 manifest 未声明 v2"
                            )
                        }
                        guard let verification = polled.verification else {
                            throw ServiceError.invalidResponse("插件请求短信验证但未提供验证信息")
                        }
                        try await handleVerification(
                            verification,
                            request: request,
                            transactionId: transactionId,
                            challengeId: challengeId,
                            deadline: deadline,
                            generation: operationGeneration
                        )
                        state = .scanned(presentation)
                        pollImmediately = true
                    case .expired:
                        await activePush?.close()
                        activePush = nil
                        if try await refreshIfAllowed(
                            request: request,
                            context: &context,
                            refreshCount: &refreshCount,
                            generation: operationGeneration
                        ) {
                            cleanupContext = context
                            activeContext = context
                            continue challengeLoop
                        }
                        throw ServiceError.expired
                    case .failed:
                        throw ServiceError.plugin(Self.normalizedMessage(polled.message) ?? "扫码登录失败")
                    case .confirmed:
                        await activePush?.close()
                        activePush = nil
                        state = .validating
                        try ensureWithinDeadline(deadline, generation: operationGeneration)
                        let cookie = try await dependencies.promoteTransaction(
                            request.entry.pluginId,
                            transactionId
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                        // promote 已销毁事务，confirmed challenge 也已终结；成功或
                        // 后续校验失败都不能再从 defer 重复 cancel/discard。
                        markTransactionFinalized(transactionId)
                        cleanupContext = nil
                        activeContext = nil
                        try ensureCurrent(operationGeneration)
                        guard !cookie.isEmpty else {
                            throw ServiceError.invalidResponse("登录事务未生成有效凭据")
                        }

                        let uid = polled.uid
                        let liveType = request.entry.liveType
                        let remainingValidationSeconds = min(
                            30,
                            deadline.timeIntervalSince(dependencies.now())
                        )
                        guard remainingValidationSeconds > 0 else {
                            throw ServiceError.timedOut
                        }
                        // The session manager owns the validation-only timeout
                        // and returns only after the durable commit decision.
                        // Do not race that commit with this presentation timer.
                        let validation = await dependencies.login(
                            pluginId,
                            transactionId,
                            cookie,
                            uid,
                            liveType,
                            .seconds(remainingValidationSeconds)
                        )
                        switch validation {
                        case .valid:
                            // Refresh host-visible login state immediately in a
                            // task independent of this sheet's lifecycle. It
                            // updates local state before any optional iCloud I/O.
                            let didLogin = dependencies.didLogin
                            Task { await didLogin(pluginId) }

                            guard generation == operationGeneration else { return }
                            state = .succeeded(LoginChallengeSuccess(userId: polled.uid))
                            // `.valid` is the irreversible host commit receipt.
                            // Nickname enrichment and sync are best-effort and
                            // must never turn a stored login into failed/idle.
                            let status: CredentialStatus?
                            do {
                                status = try await withOperationTimeout(
                                    .seconds(5),
                                    timeoutError: ServiceError.timedOut
                                ) {
                                    await self.dependencies.credentialStatus(pluginId)
                                }
                            } catch {
                                status = nil
                            }
                            if generation == operationGeneration, !Task.isCancelled,
                               let status {
                                state = .succeeded(LoginChallengeSuccess(
                                    userId: status.userId ?? polled.uid,
                                    userName: status.userName
                                ))
                            }
                            return
                        case .expired:
                            try ensureCurrent(operationGeneration)
                            throw ServiceError.validation("扫码凭据已过期")
                        case .invalid(let reason):
                            try ensureCurrent(operationGeneration)
                            throw ServiceError.validation(reason)
                        case .networkError(let reason):
                            try ensureCurrent(operationGeneration)
                            throw ServiceError.network(reason)
                        }
                    }
                }
            }
        } catch is CancellationError {
            await activePush?.close()
            activePush = nil
            return
        } catch {
            await activePush?.close()
            activePush = nil
            guard generation == operationGeneration else { return }
            state = .failed(Self.failure(from: error))
        }
    }

    private func refreshIfAllowed(
        request: StartRequest,
        context: inout OperationContext,
        refreshCount: inout Int,
        generation operationGeneration: UInt
    ) async throws -> Bool {
        guard refreshCount < request.challenge.maxRefreshes else { return false }
        if let challengeId = context.challengeId {
            let cancellationContext = context
            if markChallengeCancellation(cancellationContext, challengeId: challengeId) {
                let dependencies = dependencies
                let cancelRequest = LoginChallengePollRequest(
                        transactionId: context.transactionId,
                        challengeId: challengeId
                    )
                let pluginId = context.pluginId
                let cancelFunction = context.cancelFunction
                try await withOperationTimeout(
                    dependencies.cleanupPluginCallTimeout,
                    timeoutError: ServiceError.timedOut
                ) {
                    try await dependencies.cancel(
                        pluginId,
                        cancelFunction,
                        cancelRequest
                    )
                }
            }
            try ensureCurrent(operationGeneration)
        }
        context.challengeId = nil
        refreshCount += 1
        return true
    }

    private func handleVerification(
        _ initialDescriptor: LoginChallengeVerificationDescriptor,
        request: StartRequest,
        transactionId: String,
        challengeId: String,
        deadline: Date,
        generation operationGeneration: UInt
    ) async throws {
        var descriptor = initialDescriptor
        var presentation = try verificationPresentation(from: descriptor, errorMessage: nil)

        while true {
            try ensureWithinDeadline(deadline, generation: operationGeneration)
            let action = try await awaitVerificationAction(
                presentation: presentation,
                deadline: deadline
            )
            try ensureCurrent(operationGeneration)

            switch action {
            case .submit(let code):
                state = .submittingVerification(presentation.withError(nil))
                let verificationRequest = LoginChallengeVerificationRequest(
                    transactionId: transactionId,
                    challengeId: challengeId,
                    verificationId: descriptor.verificationId,
                    code: code
                )
                let response = try await withPluginDeadline(deadline) {
                    try await self.dependencies.submitVerification(
                        request.entry.pluginId,
                        request.challenge.functions.submitVerification,
                        verificationRequest
                    )
                }
                try ensureCurrent(operationGeneration)
                switch response.state {
                case .accepted:
                    return
                case .rejected:
                    if let updated = response.verification {
                        descriptor = updated
                    }
                    presentation = try verificationPresentation(
                        from: descriptor,
                        errorMessage: Self.normalizedMessage(response.message) ?? "验证码不正确，请重新输入"
                    )
                }

            case .resend:
                state = .requestingVerificationCode(presentation.withError(nil))
                let resendRequest = LoginChallengeVerificationResendRequest(
                    transactionId: transactionId,
                    challengeId: challengeId,
                    verificationId: descriptor.verificationId
                )
                descriptor = try await withPluginDeadline(deadline) {
                    try await self.dependencies.resendVerification(
                        request.entry.pluginId,
                        request.challenge.functions.resendVerification,
                        resendRequest
                    )
                }
                try ensureCurrent(operationGeneration)
                presentation = try verificationPresentation(
                    from: descriptor,
                    errorMessage: "验证码已重新发送"
                )
            }
        }
    }

    private func awaitVerificationAction(
        presentation: LoginChallengeVerificationPresentation,
        deadline: Date
    ) async throws -> VerificationAction {
        let pair = AsyncStream.makeStream(
            of: VerificationAction.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        verificationActionContinuation = pair.continuation
        state = .awaitingVerification(presentation)
        defer {
            pair.continuation.finish()
            verificationActionContinuation = nil
        }
        return try await withPluginDeadline(deadline) {
            for await action in pair.stream {
                return action
            }
            throw CancellationError()
        }
    }

    private func sendVerificationAction(_ action: VerificationAction) {
        verificationActionContinuation?.yield(action)
        verificationActionContinuation?.finish()
        verificationActionContinuation = nil
    }

    private func finishVerificationActions() {
        verificationActionContinuation?.finish()
        verificationActionContinuation = nil
    }

    private func verificationPresentation(
        from descriptor: LoginChallengeVerificationDescriptor,
        errorMessage: String?
    ) throws -> LoginChallengeVerificationPresentation {
        guard descriptor.kind == .smsCode else {
            throw ServiceError.invalidResponse("插件请求了宿主不支持的二次验证方式")
        }
        let verificationId = descriptor.verificationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !verificationId.isEmpty, verificationId.utf8.count <= Limits.verificationIdBytes else {
            throw ServiceError.invalidResponse("插件返回的二次验证标识无效")
        }
        let prompt = Self.normalizedHint(descriptor.prompt) ?? "请输入短信验证码"
        let maskedDestination = Self.normalizedMaskedDestination(descriptor.maskedDestination)
        let codeLength = min(max(descriptor.codeLength ?? 6, 1), Limits.verificationCodeCharacters)
        let canResend = descriptor.canResend ?? (descriptor.resendAfterMs != nil)
        let resendAfterMs = min(max(descriptor.resendAfterMs ?? 0, 0), Limits.maxResendAfterMs)
        let resendAvailableAt = canResend
            ? dependencies.now().addingTimeInterval(Double(resendAfterMs) / 1_000)
            : nil
        return LoginChallengeVerificationPresentation(
            kind: descriptor.kind,
            prompt: prompt,
            maskedDestination: maskedDestination,
            codeLength: codeLength,
            canResend: canResend,
            resendAvailableAt: resendAvailableAt,
            errorMessage: Self.normalizedMessage(errorMessage)
        )
    }

    private func ensureCurrent(_ operationGeneration: UInt) throws {
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
    }

    private func ensureWithinDeadline(_ deadline: Date, generation operationGeneration: UInt) throws {
        try ensureCurrent(operationGeneration)
        guard dependencies.now() < deadline else { throw ServiceError.timedOut }
    }

    @discardableResult
    private func scheduleCleanup(_ context: OperationContext) -> Task<Void, Never>? {
        if finalizedTransactionIds.contains(context.transactionId) {
            return cleanupTasks[context.transactionId]?.task
        }
        finalizedTransactionIds.insert(context.transactionId)
        let dependencies = dependencies
        let shouldCancel: Bool
        if let challengeId = context.challengeId {
            shouldCancel = markChallengeCancellation(context, challengeId: challengeId)
        } else {
            shouldCancel = false
        }
        let task = Task { [self] in
            if shouldCancel, let challengeId = context.challengeId {
                let request = LoginChallengePollRequest(
                    transactionId: context.transactionId,
                    challengeId: challengeId
                )
                try? await withOperationTimeout(
                    dependencies.cleanupPluginCallTimeout,
                    timeoutError: ServiceError.timedOut
                ) {
                    try await dependencies.cancel(context.pluginId, context.cancelFunction, request)
                }
            }
            try? await dependencies.discardTransaction(context.pluginId, context.transactionId)
            dependencies.releaseRuntimeLease(context.pluginId, context.transactionId)
            cleanupTasks.removeValue(forKey: context.transactionId)
        }
        cleanupTasks[context.transactionId] = CleanupRecord(pluginId: context.pluginId, task: task)
        return task
    }

    private func waitForCleanup(pluginId: String) async {
        let tasks = cleanupTasks.values
            .filter { $0.pluginId == pluginId }
            .map(\.task)
        for task in tasks {
            await task.value
        }
    }

    private func markChallengeCancellation(
        _ context: OperationContext,
        challengeId: String
    ) -> Bool {
        cancelledChallengeKeys.insert(ChallengeCancellationKey(
            transactionId: context.transactionId,
            challengeId: challengeId
        )).inserted
    }

    private func markTransactionFinalized(_ transactionId: String) {
        finalizedTransactionIds.insert(transactionId)
        cancelledChallengeKeys = cancelledChallengeKeys.filter { $0.transactionId != transactionId }
    }

    private func pruneTerminalBookkeeping(transactionId: String) {
        finalizedTransactionIds.remove(transactionId)
        cancelledChallengeKeys = cancelledChallengeKeys.filter { $0.transactionId != transactionId }
    }

    private func withPluginDeadline<Value: Sendable>(
        _ deadline: Date,
        operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let remaining = deadline.timeIntervalSince(dependencies.now())
        guard remaining > 0 else { throw ServiceError.timedOut }
        return try await withOperationTimeout(
            .seconds(remaining),
            timeoutError: ServiceError.timedOut,
            operation: operation
        )
    }

    /// Waits for the regular polling deadline or one coalesced push signal.
    /// Push is advisory: a closed stream simply leaves the HTTP timer in charge.
    private func waitForPollingTurn(
        delay: Duration,
        push: LoginChallengePushHandle?
    ) async throws {
        guard let push else {
            try await dependencies.sleep(delay)
            return
        }

        let first = LoginChallengeFirstResult<Void>()
        let sleep = dependencies.sleep
        let timerTask = Task {
            do {
                try await sleep(delay)
                await first.resolve(.success(()))
            } catch {
                await first.resolve(.failure(error))
            }
        }
        let signalTask = Task {
            for await _ in push.pollSignals {
                await first.resolve(.success(()))
                return
            }
        }

        try await withTaskCancellationHandler {
            defer {
                timerTask.cancel()
                signalTask.cancel()
            }
            try await first.value()
        } onCancel: {
            timerTask.cancel()
            signalTask.cancel()
            Task { await first.resolve(.failure(CancellationError())) }
        }
    }

    /// 插件 Promise 可能永不 settle；不能让它使 manifest deadline、取消和
    /// retry 永久失效。这里让状态机只等待第一个结果，迟到插件任务不会再
    /// 获得提交事务的机会，最终由 transaction ownership/expiry 丢弃结果。
    private func withOperationTimeout<Value: Sendable>(
        _ timeout: Duration,
        timeoutError: any Error,
        operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let first = LoginChallengeFirstResult<Value>()
        let operationTask = Task {
            do {
                await first.resolve(.success(try await operation()))
            } catch {
                await first.resolve(.failure(error))
            }
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
                await first.resolve(.failure(timeoutError))
            } catch {
                // Winning operation/caller cancellation stops this watchdog.
            }
        }

        return try await withTaskCancellationHandler {
            defer {
                operationTask.cancel()
                timeoutTask.cancel()
            }
            return try await first.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task {
                await first.resolve(.failure(CancellationError()))
            }
        }
    }

    private static func expirationDate(fromUnixMilliseconds value: Double?) -> Date? {
        guard let value, value > 0, value.isFinite else { return nil }
        return Date(timeIntervalSince1970: value / 1_000)
    }

    private static func normalizedHint(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(Limits.hintCharacters))
    }

    private static let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private static func pngData(from qrImage: String?) -> Data? {
        var payload = qrImage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !payload.isEmpty else { return nil }
        if let range = payload.range(of: "base64,", options: .caseInsensitive) {
            payload = String(payload[range.upperBound...])
        }
        guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]),
              data.count >= pngMagic.count,
              data.prefix(pngMagic.count) == pngMagic else {
            return nil
        }
        return data
    }

    private static func normalizedMessage(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(Limits.messageCharacters))
    }

    private static func normalizedMaskedDestination(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(Limits.maskedDestinationCharacters))
    }

    private static func failure(from error: Error) -> LoginChallengeFailure {
        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .timedOut:
                return .init(kind: .timedOut, message: "扫码登录超时，请重试", canRetry: true, canFallbackToWebLogin: true)
            case .expired:
                return .init(kind: .expired, message: "二维码已过期，请重试", canRetry: true, canFallbackToWebLogin: true)
            case .invalidResponse(let message):
                return .init(kind: .invalidResponse, message: normalizedMessage(message) ?? "插件返回无效响应", canRetry: true, canFallbackToWebLogin: true)
            case .validation(let message):
                return .init(kind: .validation, message: normalizedMessage(message) ?? "登录凭据校验失败", canRetry: true, canFallbackToWebLogin: true)
            case .network(let message), .plugin(let message):
                return .init(kind: .plugin, message: normalizedMessage(message) ?? "扫码登录失败", canRetry: true, canFallbackToWebLogin: true)
            }
        }

        if let pluginError = error as? LiveParsePluginError,
           case .standardized(let standard) = pluginError {
            switch standard.code {
            case .unsupported:
                return .init(kind: .unsupported, message: normalizedMessage(standard.message) ?? "当前宿主不支持该扫码登录协议", canRetry: false, canFallbackToWebLogin: true)
            case .blocked:
                return .init(kind: .plugin, message: normalizedMessage(standard.message) ?? "扫码登录被平台拦截", canRetry: false, canFallbackToWebLogin: true)
            default:
                return .init(kind: .plugin, message: normalizedMessage(standard.message) ?? "扫码登录失败", canRetry: true, canFallbackToWebLogin: true)
            }
        }

        return .init(
            kind: .plugin,
            message: normalizedMessage(error.localizedDescription) ?? "扫码登录失败",
            canRetry: true,
            canFallbackToWebLogin: true
        )
    }
}

private extension PlatformLoginChallengeService {
    enum Limits {
        static let challengeIdBytes = 4_096
        /// 三端 Core Image 生成器默认使用 M 级纠错；Version 40 字节模式最大 2331 字节。
        static let qrContentBytes = 2_331
        static let qrImageBytes = 32_768
        static let hintCharacters = 500
        static let messageCharacters = 1_000
        static let verificationIdBytes = 4_096
        static let verificationCodeCharacters = 32
        static let maskedDestinationCharacters = 100
        static let maxResendAfterMs = 300_000
    }

    struct StartRequest: Sendable {
        let entry: LoginPlatformEntry
        let challenge: ManifestLoginChallenge
        let platform: LoginChallengeHostPlatform
    }

    struct OperationContext: Sendable {
        let pluginId: String
        let transactionId: String
        let cancelFunction: String
        var challengeId: String?
    }

    struct CleanupRecord {
        let pluginId: String
        let task: Task<Void, Never>
    }

    struct ChallengeCancellationKey: Hashable {
        let transactionId: String
        let challengeId: String
    }

    enum VerificationAction: Sendable {
        case submit(String)
        case resend
    }

    enum ServiceError: Error {
        case timedOut
        case expired
        case invalidResponse(String)
        case validation(String)
        case network(String)
        case plugin(String)
    }
}

/// One-shot result cell used to race an untrusted plugin Promise against a host
/// timeout/cancellation without structurally waiting for a non-cooperative loser.
private actor LoginChallengeFirstResult<Value: Sendable> {
    private var isResolved = false
    private var storedResult: Result<Value, any Error>?
    private var continuation: CheckedContinuation<Value, any Error>?

    func resolve(_ result: Result<Value, any Error>) {
        guard !isResolved else { return }
        isResolved = true
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            storedResult = result
        }
    }

    func value() async throws -> Value {
        if let storedResult {
            self.storedResult = nil
            return try storedResult.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
}
