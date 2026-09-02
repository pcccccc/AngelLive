import Foundation

/// 收藏直播状态请求的总预算与唯一兼容重试规则。
///
/// `totalBudget` 覆盖首次请求、短退避和可选的第二次请求；它不是单次尝试的超时。
public struct FavoriteRefreshRequestPolicy: Sendable, Equatable {
    public var foregroundBudget: Duration
    public var totalBudget: Duration
    public var notFoundRetryDelay: Duration
    public var maximumConcurrentRequests: Int
    public var maximumConcurrentRequestsPerPlugin: Int

    public init(
        foregroundBudget: Duration = .seconds(4),
        totalBudget: Duration = .seconds(20),
        notFoundRetryDelay: Duration = .milliseconds(400),
        maximumConcurrentRequests: Int = 8,
        maximumConcurrentRequestsPerPlugin: Int = 3
    ) {
        self.foregroundBudget = foregroundBudget
        self.totalBudget = totalBudget
        self.notFoundRetryDelay = notFoundRetryDelay
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.maximumConcurrentRequestsPerPlugin = max(1, maximumConcurrentRequestsPerPlugin)
    }

    public static let `default` = FavoriteRefreshRequestPolicy()
}

/// Phase 0 的可注入房间状态边界。生产实现调用插件，测试实现不需要真实网络或 JS runtime。
public protocol FavoriteLiveInfoFetching: Sendable {
    func fetchLatestLiveInfo(for liveModel: LiveModel) async throws -> LiveModel
}

/// Phase 0 的可测试路径快照边界。Phase 1 只建立契约，路径门禁由后续刷新会话接入。
public enum FavoriteNetworkPathStatus: Sendable, Equatable {
    case satisfied
    case unsatisfied
    case requiresConnection
    case unknown
}

public protocol FavoriteNetworkPathObserving: Sendable {
    func currentStatus() async -> FavoriteNetworkPathStatus
    func currentRevision() async -> UInt64
}

public extension FavoriteNetworkPathObserving {
    func currentRevision() async -> UInt64 { 0 }
}

/// 单调时间、退避和超时均可注入，避免策略单测依赖墙钟或真实 sleep。
public protocol FavoriteRefreshTiming: Sendable {
    func now() async -> Duration
    func sleep(for duration: Duration) async throws
    func withTimeout<Value: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value
}

public enum FavoriteRefreshFastUnreachableReason: Sendable, Equatable {
    case noRoute
    case dns
    case connectionRefused
    case connectionLost
    case otherConnectionFailure
}

public enum FavoriteRefreshFailureKind: Sendable, Equatable {
    case deviceOffline
    case fastUnreachable(FavoriteRefreshFastUnreachableReason)
    case timeout
    case authenticationRequired
    case notFound
    case rateLimited
    case blocked
    case upstream
    case invalidResponse
    case cancelled
    case unknown
}

public struct FavoriteRefreshUnderlyingError: Sendable, Equatable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

/// 可跨 actor 传递的失败快照，不携带 Cookie、Token 或完整请求 URL。
public struct FavoriteRefreshFailure: Error, LocalizedError, Sendable, Equatable {
    public let kind: FavoriteRefreshFailureKind
    public let underlyingError: FavoriteRefreshUnderlyingError?
    public let standardCode: LiveParsePluginStandardErrorCode?
    public let receivedHTTPResponse: Bool
    public let attempts: Int
    public let elapsed: Duration
    public let pluginId: String

    public var errorDescription: String? {
        "收藏状态刷新失败：\(kindDescription)，尝试 \(attempts) 次"
    }

    init(
        kind: FavoriteRefreshFailureKind,
        underlyingError: FavoriteRefreshUnderlyingError?,
        standardCode: LiveParsePluginStandardErrorCode?,
        receivedHTTPResponse: Bool,
        attempts: Int,
        elapsed: Duration,
        pluginId: String
    ) {
        self.kind = kind
        self.underlyingError = underlyingError
        self.standardCode = standardCode
        self.receivedHTTPResponse = receivedHTTPResponse
        self.attempts = attempts
        self.elapsed = elapsed
        self.pluginId = pluginId
    }

    private var kindDescription: String {
        switch kind {
        case .deviceOffline: "设备无网络"
        case .fastUnreachable: "连接不可达"
        case .timeout: "请求超时"
        case .authenticationRequired: "需要登录"
        case .notFound: "未找到房间"
        case .rateLimited: "请求受限"
        case .blocked: "请求被阻止"
        case .upstream: "上游服务失败"
        case .invalidResponse: "响应无效"
        case .cancelled: "请求已取消"
        case .unknown: "未知错误"
        }
    }
}

struct PluginFavoriteLiveInfoFetcher: FavoriteLiveInfoFetching {
    func fetchLatestLiveInfo(for liveModel: LiveModel) async throws -> LiveModel {
        guard let platform = SandboxPluginCatalog.platform(for: liveModel.liveType) else {
            throw LiveParseError.liveParseError("不支持的平台", "\(liveModel.liveType)")
        }
        return try await LiveParseJSPlatformManager.getLiveLastestInfo(
            platform: platform,
            roomId: liveModel.roomId,
            userId: liveModel.userId
        )
    }
}

struct ContinuousFavoriteRefreshTiming: FavoriteRefreshTiming {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func now() async -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }

    func withTimeout<Value: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard duration > .zero else { throw FavoriteRefreshBudgetExceeded() }

        let (stream, continuation) = AsyncStream.makeStream(
            of: FavoriteRefreshTimeoutOutcome<Value>.self,
            // 竞速只接受第一个结果；后到的网络完成或计时器不得覆盖赢家。
            bufferingPolicy: .bufferingOldest(1)
        )
        let operationTask = Task {
            do {
                continuation.yield(.success(try await operation()))
            } catch is CancellationError {
                continuation.yield(.cancelled)
            } catch {
                continuation.yield(.failure(error))
            }
        }
        let timeoutTask = Task {
            do {
                try await clock.sleep(for: duration)
                continuation.yield(.timedOut)
            } catch {
                // 被赢家取消，不再产生第二个结果。
            }
        }

        defer {
            operationTask.cancel()
            timeoutTask.cancel()
            continuation.finish()
        }

        var iterator = stream.makeAsyncIterator()
        guard let outcome = await iterator.next() else { throw CancellationError() }
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .timedOut:
            throw FavoriteRefreshBudgetExceeded()
        case .cancelled:
            throw CancellationError()
        }
    }
}

private struct FavoriteRefreshBudgetExceeded: Error, Sendable {}

private enum FavoriteRefreshTimeoutOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(any Error & Sendable)
    case timedOut
    case cancelled
}

struct FavoriteLiveInfoRequestExecutor<Fetcher: FavoriteLiveInfoFetching, Timing: FavoriteRefreshTiming>: Sendable {
    let fetcher: Fetcher
    let timing: Timing
    let policy: FavoriteRefreshRequestPolicy

    func fetch(
        liveModel: LiveModel,
        pluginId: String,
        allowNotFoundRetry: Bool = true
    ) async throws -> LiveModel {
        let startedAt = await timing.now()
        var attempts = 0

        while true {
            try Task.checkCancellation()
            let elapsedBeforeAttempt = await elapsed(since: startedAt)
            let remainingBudget = policy.totalBudget - elapsedBeforeAttempt
            guard remainingBudget > .zero else {
                throw makeFailure(
                    from: FavoriteRefreshBudgetExceeded(),
                    attempts: attempts,
                    elapsed: elapsedBeforeAttempt,
                    pluginId: pluginId
                )
            }

            attempts += 1
            do {
                return try await timing.withTimeout(remainingBudget) {
                    try await fetcher.fetchLatestLiveInfo(for: liveModel)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let currentElapsed = await elapsed(since: startedAt)
                let failure = makeFailure(
                    from: error,
                    attempts: attempts,
                    elapsed: currentElapsed,
                    pluginId: pluginId
                )

                guard allowNotFoundRetry, failure.kind == .notFound, attempts == 1 else {
                    throw failure
                }

                let remainingAfterFailure = policy.totalBudget - currentElapsed
                guard remainingAfterFailure > policy.notFoundRetryDelay else {
                    throw failure
                }

                try await timing.sleep(for: policy.notFoundRetryDelay)
            }
        }
    }

    private func elapsed(since start: Duration) async -> Duration {
        max(await timing.now() - start, .zero)
    }

    fileprivate func makeFailure(
        from error: any Error,
        attempts: Int,
        elapsed: Duration,
        pluginId: String
    ) -> FavoriteRefreshFailure {
        if error is FavoriteRefreshBudgetExceeded {
            return FavoriteRefreshFailure(
                kind: .timeout,
                underlyingError: nil,
                standardCode: .timeout,
                receivedHTTPResponse: false,
                attempts: attempts,
                elapsed: elapsed,
                pluginId: pluginId
            )
        }

        if let failure = error as? FavoriteRefreshFailure {
            return FavoriteRefreshFailure(
                kind: failure.kind,
                underlyingError: failure.underlyingError,
                standardCode: failure.standardCode,
                receivedHTTPResponse: failure.receivedHTTPResponse,
                attempts: attempts,
                elapsed: elapsed,
                pluginId: pluginId
            )
        }

        if let pluginError = error as? LiveParsePluginError,
           case .standardized(let standardError) = pluginError {
            return makeStandardFailure(
                standardError,
                attempts: attempts,
                elapsed: elapsed,
                pluginId: pluginId
            )
        }

        let nsError = error as NSError
        return FavoriteRefreshFailure(
            kind: Self.kind(forDomain: nsError.domain, code: nsError.code),
            underlyingError: FavoriteRefreshUnderlyingError(domain: nsError.domain, code: nsError.code),
            standardCode: nil,
            receivedHTTPResponse: false,
            attempts: attempts,
            elapsed: elapsed,
            pluginId: pluginId
        )
    }

    private func makeStandardFailure(
        _ error: LiveParsePluginStandardError,
        attempts: Int,
        elapsed: Duration,
        pluginId: String
    ) -> FavoriteRefreshFailure {
        let underlying: FavoriteRefreshUnderlyingError? = {
            guard let domain = error.context["underlyingDomain"],
                  let codeText = error.context["underlyingCode"],
                  let code = Int(codeText) else { return nil }
            return FavoriteRefreshUnderlyingError(domain: domain, code: code)
        }()
        let receivedHTTPResponse = error.context["receivedHTTPResponse"] == "true"

        let kind: FavoriteRefreshFailureKind
        switch error.code {
        case .authRequired: kind = .authenticationRequired
        case .notFound: kind = .notFound
        case .blocked: kind = .blocked
        case .rateLimited: kind = .rateLimited
        case .timeout: kind = .timeout
        case .parse, .invalidArgs, .invalidResponse, .unsupported: kind = .invalidResponse
        case .upstream: kind = .upstream
        case .network:
            if let underlying {
                kind = Self.kind(forDomain: underlying.domain, code: underlying.code)
            } else {
                // NETWORK 本身不等于快速不可达；没有底层 code 时禁止用文案猜测。
                kind = .unknown
            }
        case .unknown: kind = .unknown
        }

        return FavoriteRefreshFailure(
            kind: kind,
            underlyingError: underlying,
            standardCode: error.code,
            receivedHTTPResponse: receivedHTTPResponse,
            attempts: attempts,
            elapsed: elapsed,
            pluginId: pluginId
        )
    }

    private static func kind(forDomain domain: String, code: Int) -> FavoriteRefreshFailureKind {
        guard domain == NSURLErrorDomain else { return .unknown }
        let urlCode = URLError.Code(rawValue: code)

        switch urlCode {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .deviceOffline
        case .cannotFindHost, .dnsLookupFailed:
            return .fastUnreachable(.dns)
        case .cannotConnectToHost:
            return .fastUnreachable(.connectionRefused)
        case .networkConnectionLost:
            return .fastUnreachable(.connectionLost)
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .unknown
        }
    }
}

func favoriteRefreshFailure(
    from error: any Error,
    attempts: Int = 1,
    elapsed: Duration = .zero,
    pluginId: String
) -> FavoriteRefreshFailure {
    FavoriteLiveInfoRequestExecutor(
        fetcher: PluginFavoriteLiveInfoFetcher(),
        timing: ContinuousFavoriteRefreshTiming(),
        policy: .default
    ).makeFailure(
        from: error,
        attempts: attempts,
        elapsed: elapsed,
        pluginId: pluginId
    )
}
