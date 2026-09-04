import Foundation

/// Owns one optional WebSocket for a plugin login challenge. The actor serializes
/// plugin callbacks so message and heartbeat events cannot re-enter one stateful
/// JavaScript runtime concurrently.
actor LoginChallengePushCoordinator {
    typealias EventHandler = @Sendable (LoginChallengePushEvent) async throws -> LoginChallengePushAction

    private enum Limits {
        static let maximumURLBytes = 8_192
        static let maximumFrameBytes = 1_048_576
        static let maximumFramesPerAction = 16
        static let maximumPendingEvents = 64
    }

    private let expectedFrameType: LoginChallengePushFrameType
    private let eventHandler: EventHandler
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private let pollContinuation: AsyncStream<Void>.Continuation
    private let heartbeatInterval: Duration?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var pendingEvents: [LoginChallengePushEvent] = []
    private var isProcessing = false
    private var isClosed = false

    private init(
        request: URLRequest,
        expectedFrameType: LoginChallengePushFrameType,
        pingIntervalMs: Int?,
        pollContinuation: AsyncStream<Void>.Continuation,
        eventHandler: @escaping EventHandler
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        self.expectedFrameType = expectedFrameType
        self.eventHandler = eventHandler
        self.session = session
        socket = session.webSocketTask(with: request)
        self.pollContinuation = pollContinuation
        heartbeatInterval = pingIntervalMs.map { .milliseconds($0) }
    }

    static func open(
        pluginId: String,
        transactionId: String,
        challengeId: String,
        plan: LoginChallengePushPlan,
        eventHandler: @escaping EventHandler
    ) async throws -> LoginChallengePushHandle {
        guard plan.kind == .websocket,
              plan.url.utf8.count <= Limits.maximumURLBytes,
              let url = URL(string: plan.url),
              isAllowedWebSocketURL(url) else {
            throw LiveParsePluginError.invalidReturnValue("Invalid login challenge WebSocket URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpShouldHandleCookies = false
        let cookie = try await LoginTransactionStore.shared.cookieHeader(
            pluginId: pluginId,
            transactionId: transactionId,
            for: url
        )
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (signals, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let coordinator = LoginChallengePushCoordinator(
            request: request,
            expectedFrameType: plan.frameType,
            pingIntervalMs: plan.pingIntervalMs,
            pollContinuation: continuation,
            eventHandler: eventHandler
        )
        await coordinator.start()

        let queryKeys = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .prefix(64)
            .map { String($0.name.prefix(64)) }
            .sorted()
            .joined(separator: ",") ?? ""
        Logger.debug(
            "[LoginChallengePush] open pluginId=\(pluginId) scheme=\(url.scheme ?? "") host=\(url.host ?? "") pathLength=\(url.path.utf8.count) queryKeys=\(queryKeys)",
            category: .plugin
        )

        return LoginChallengePushHandle(
            pollSignals: signals,
            close: { await coordinator.close() },
            cancel: { Task { await coordinator.close() } }
        )
    }

    private func start() {
        guard !isClosed else { return }
        socket.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        if let heartbeatInterval {
            heartbeatTask = Task { [weak self] in
                await self?.heartbeatLoop(interval: heartbeatInterval)
            }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled, !isClosed {
            do {
                let message = try await socket.receive()
                let frame: LoginChallengePushFrame
                switch message {
                case .data(let data):
                    guard data.count <= Limits.maximumFrameBytes else {
                        await finish(waitForProcessing: true)
                        return
                    }
                    frame = LoginChallengePushFrame(binary: data)
                case .string(let text):
                    guard text.utf8.count <= Limits.maximumFrameBytes else {
                        await finish(waitForProcessing: true)
                        return
                    }
                    frame = LoginChallengePushFrame(text: text)
                @unknown default:
                    await finish(waitForProcessing: true)
                    return
                }
                // A platform protocol may mix binary payloads with a text application ping.
                // Deliver the actual frame type instead of dropping the connection.
                _ = expectedFrameType
                await enqueue(.init(kind: .message, frame: frame))
            } catch {
                await finish(waitForProcessing: true)
                return
            }
        }
    }

    private func heartbeatLoop(interval: Duration) async {
        while !Task.isCancelled, !isClosed {
            do {
                try await Task.sleep(for: interval)
                try Task.checkCancellation()
            } catch {
                return
            }
            await enqueue(.init(kind: .tick, frame: nil))
        }
    }

    private func enqueue(_ event: LoginChallengePushEvent) async {
        guard !isClosed else { return }
        guard pendingEvents.count < Limits.maximumPendingEvents else {
            await finish(waitForProcessing: true)
            return
        }
        pendingEvents.append(event)
        guard !isProcessing else { return }
        isProcessing = true
        processingTask = Task { [weak self] in
            await self?.processPendingEvents()
        }
    }

    private func processPendingEvents() async {
        while !isClosed, !pendingEvents.isEmpty {
            let event = pendingEvents.removeFirst()
            do {
                let action = try await eventHandler(event)
                guard !isClosed else { return }
                let frames = Array((action.send ?? []).prefix(Limits.maximumFramesPerAction))
                // FWS uses binary payloads plus a text application ping ("hi").
                guard frames.allSatisfy(\.isValid) else {
                    await finish(waitForProcessing: false)
                    return
                }
                for frame in frames {
                    switch frame.type {
                    case .binary:
                        guard let encoded = frame.bytesBase64,
                              let data = Data(base64Encoded: encoded),
                              data.count <= Limits.maximumFrameBytes else {
                            await finish(waitForProcessing: false)
                            return
                        }
                        try await socket.send(.data(data))
                    case .text:
                        guard let text = frame.text,
                              text.utf8.count <= Limits.maximumFrameBytes else {
                            await finish(waitForProcessing: false)
                            return
                        }
                        try await socket.send(.string(text))
                    }
                }
                if action.pollNow == true {
                    pollContinuation.yield(())
                }
                if action.close == true {
                    await finish(waitForProcessing: false)
                    return
                }
            } catch {
                await finish(waitForProcessing: false)
                return
            }
        }
        isProcessing = false
        processingTask = nil
    }

    func close() async {
        await finish(waitForProcessing: true)
    }

    private func finish(waitForProcessing: Bool) async {
        guard !isClosed else { return }
        isClosed = true
        pendingEvents.removeAll(keepingCapacity: false)
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        let processing = processingTask
        processing?.cancel()
        receiveTask = nil
        heartbeatTask = nil
        processingTask = nil
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        pollContinuation.finish()
        if waitForProcessing {
            await processing?.value
        }
    }

    private static func isAllowedWebSocketURL(_ url: URL) -> Bool {
        guard url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if url.scheme?.lowercased() == "wss" {
            return true
        }
        return url.scheme?.lowercased() == "ws"
            && (host == "localhost" || host == "127.0.0.1" || host == "::1")
    }
}
