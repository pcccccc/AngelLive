import Foundation
@preconcurrency import Alamofire

typealias DanmakuHTTPResponse = Result<(Data, HTTPURLResponse?), Error>
typealias DanmakuHTTPRequestExecutor = @MainActor (
    URLRequest,
    @escaping @MainActor (DanmakuHTTPResponse) -> Void
) -> (@MainActor () -> Void)

/// 与 `WebSocketConnection` 同构:轮询 Timer 落在主 runloop,delegate 是 UI 层,
/// 状态(isConnected / isRequestInFlight / pollingTimer 等)本就只在主线程读写。
/// 标注 `@MainActor` 把这份既有约定交给编译器保证。
@MainActor
public final class HTTPPollingDanmakuConnection {
    public var parameters: [String: String]?
    var headers: [String: String]?
    public weak var delegate: WebSocketConnectionDelegate?

    let liveType: LiveType

    private let danmakuPlan: LiveParseDanmakuPlan?
    private let pluginId: String?
    private var pluginDriver: (any DanmakuRuntimeDriving)?
    var makeDriver: DanmakuDriverFactory = { PluginJSDanmakuDriver(pluginId: $0, roomId: $1, userId: $2, plan: $3) }
    var schedule: DanmakuSchedule = scheduleDanmakuWork
    var executeRequest: DanmakuHTTPRequestExecutor = { request, completion in
        let dataRequest = AF.request(request).responseData { response in
            MainActor.assumeIsolated {
                switch response.result {
                case .success(let data): completion(.success((data, response.response)))
                case .failure(let error): completion(.failure(error))
                }
            }
        }
        return { dataRequest.cancel() }
    }
    private var roomId: String?
    private var userId: String?
    private let pollingTimer = DanmakuConnectionTimer()
    let workQueue = DanmakuConnectionWorkQueue()
    private lazy var driverRetirement = DanmakuDriverRetirement(schedule: schedule)
    private var cancelReconnect: (@MainActor () -> Void)?
    private var reconnectPolicy = DanmakuReconnectPolicy()
    private var shouldReconnect = false
    private var hasNotifiedDisconnect = false
    private var cancelRequest: (@MainActor () -> Void)?
    private var pollingInterval: TimeInterval = 3.0
    private var pollingURL: String = ""
    private var pollingMethod: String = "POST"
    private var isConnected = false
    private var hasReceivedResponse = false
    private var isRequestInFlight = false
    private var driverTimerReason: PluginJSDanmakuDriver.TickReason = .polling

    public init(parameters: [String: String]?, headers: [String: String]?, liveType: LiveType) {
        self.parameters = parameters
        self.headers = headers
        self.liveType = liveType
        self.danmakuPlan = nil
        self.pluginId = nil
        parseConfig()
    }

    public init(
        parameters: [String: String]?,
        headers: [String: String]?,
        liveType: LiveType,
        pluginId: String,
        roomId: String,
        userId: String?,
        danmakuPlan: LiveParseDanmakuPlan
    ) {
        self.parameters = parameters
        self.headers = headers
        self.liveType = liveType
        self.danmakuPlan = danmakuPlan
        self.pluginId = pluginId
        self.roomId = roomId
        self.userId = userId


        parseConfig()
    }

    /// `isolated deinit`:在主 actor 上执行析构,理由同 `WebSocketConnection`——
    /// nonisolated deinit 无法访问非 Sendable 的 `pollingTimer`,也就复用不了 `disconnect()`。
    isolated deinit {
        disconnect()
    }

    public func connect() {
        guard !shouldReconnect else { return }
        shouldReconnect = true
        reconnectPolicy.connected()
        hasNotifiedDisconnect = false
        hasReceivedResponse = false
        startSession()
    }

    public func disconnect() {
        shouldReconnect = false
        cancelReconnect?()
        cancelReconnect = nil
        tearDownAttempt(reason: .disconnect)
    }

    private func tearDownAttempt(reason: PluginJSDanmakuDriver.DestroyReason) {
        workQueue.invalidate()
        pollingTimer.stop()
        isConnected = false
        isRequestInFlight = false
        cancelRequest?()
        cancelRequest = nil
        let oldDriver = pluginDriver
        pluginDriver = nil
        if let oldDriver {
            driverRetirement.retire(oldDriver, reason: reason)
        }
    }

    private func startSession() {
        guard shouldReconnect else { return }
        tearDownAttempt(reason: .reconnect)
        guard let pluginId, let roomId, let danmakuPlan, danmakuPlan.usesPluginRuntimeDriver,
              !pollingURL.isEmpty else {
            disconnect()
            delegate?.webSocketDidDisconnect(
                error: LiveParseError.danmuArgsParseError("弹幕轮询配置无效", "缺少驱动或连接地址")
            )
            return
        }
        let driver = makeDriver(pluginId, roomId, userId, danmakuPlan)
        pluginDriver = driver
        workQueue.enqueue(operation: { try await driver.createSession() }) { [weak self] outcome in
            guard let self, self.shouldReconnect else { return }
            switch outcome {
            case .success(let result):
                self.isConnected = true
                self.applyDriverResult(result)
                // Session creation is not proof that polling has recovered.
                if danmakuPlan.transport?.polling?.sendOnConnect ?? true {
                    if let poll = result.poll { self.executePoll(poll) }
                    else { self.runDriverTick() }
                }
            case .failure(let error):
                self.handleDriverFailure(error)
            }
        }
    }
}

private extension HTTPPollingDanmakuConnection {
    func parseConfig() {
        if let url = danmakuPlan?.transport?.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            pollingURL = url
        } else if let url = parameters?["_polling_url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            pollingURL = url
        }

        if let method = danmakuPlan?.transport?.polling?.method?.trimmingCharacters(in: .whitespacesAndNewlines), !method.isEmpty {
            pollingMethod = method.uppercased()
        } else if let method = parameters?["_polling_method"]?.trimmingCharacters(in: .whitespacesAndNewlines), !method.isEmpty {
            pollingMethod = method.uppercased()
        }

        if let intervalMs = danmakuPlan?.transport?.polling?.intervalMs {
            pollingInterval = max(Double(intervalMs) / 1000.0, 1.0)
        } else if let intervalText = parameters?["_polling_interval"], let intervalMs = Double(intervalText) {
            pollingInterval = max(intervalMs / 1000.0, 1.0)
        }
    }

    func runDriverTick() {
        guard shouldReconnect, let driver = pluginDriver, isConnected, !isRequestInFlight else { return }
        let reason = driverTimerReason
        workQueue.enqueue(key: "tick", operation: { try await driver.onTick(reason: reason) }) { [weak self] outcome in
            guard let self, self.shouldReconnect else { return }
            switch outcome {
            case .success(let result):
                self.applyDriverResult(result)
                if let poll = result.poll { self.executePoll(poll) }
            case .failure(let error):
                self.handleDriverFailure(error)
            }
        }
    }

    func applyDriverResult(_ result: LiveParseDanmakuDriverResult) {
        guard shouldReconnect else { return }
        deliverMessages(result.messages)
        updateTimer(result.timer)
    }

    func deliverMessages(_ messages: [LiveParseDanmakuMessage]?) {
        guard let messages else { return }
        for message in messages {
            delegate?.webSocketDidReceiveMessage(DanmakuDisplayMessage(message))
        }
    }

    func updateTimer(_ timer: LiveParseDanmakuTimerPlan?) {
        pollingTimer.update(timer) { [weak self] in self?.runDriverTick() }
        if let timer {
            switch timer.mode {
            case .heartbeat: driverTimerReason = .heartbeat
            case .polling: driverTimerReason = .polling
            case .off: break
            }
        }
    }

    func executePoll(_ poll: LiveParseDanmakuPollRequest) {
        guard isConnected, !isRequestInFlight else { return }
        guard let request = makeRequest(from: poll) else {
            handleDriverFailure(
                LiveParseError.danmuArgsParseError("弹幕轮询请求无效", "插件返回的轮询请求缺少可用 URL")
            )
            return
        }

        isRequestInFlight = true
        let token = workQueue.generation
        cancelRequest = executeRequest(request) { [weak self] response in
            guard let self, self.shouldReconnect, self.workQueue.generation == token else { return }
            self.cancelRequest = nil
            switch response {
            case .success(let (data, httpResponse)):
                self.handleHTTPResponse(data: data, response: httpResponse)
            case .failure(let error):
                self.handleDriverFailure(error)
            }
        }
    }

    func makeRequest(from poll: LiveParseDanmakuPollRequest) -> URLRequest? {
        let normalizedURL = poll.url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLText = (normalizedURL?.isEmpty == false) ? normalizedURL! : pollingURL
        guard !baseURLText.isEmpty else { return nil }

        var components = URLComponents(string: baseURLText)
        if let query = poll.query, !query.isEmpty {
            var queryItems = components?.queryItems ?? []
            for (key, value) in query {
                queryItems.removeAll { $0.name == key }
                queryItems.append(URLQueryItem(name: key, value: value))
            }
            components?.queryItems = queryItems
        }

        var mergedHeaders = headers ?? [:]
        if let pollHeaders = poll.headers {
            for (key, value) in pollHeaders {
                mergedHeaders[key] = value
            }
        }

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        let method = poll.method?.trimmingCharacters(in: .whitespacesAndNewlines)
        request.httpMethod = ((method?.isEmpty == false) ? method : pollingMethod)?.uppercased()

        for (key, value) in mergedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let bodyText = poll.bodyText {
            request.httpBody = bodyText.data(using: .utf8)
        } else if let bodyBase64 = poll.bodyBase64 {
            request.httpBody = Data(base64Encoded: bodyBase64)
        }

        return request
    }

    func handleHTTPResponse(data: Data, response: HTTPURLResponse?) {
        guard let pluginDriver else {
            handleDriverFailure(
                LiveParseError.danmuArgsParseError("弹幕驱动不受支持", "插件驱动在处理轮询响应时丢失")
            )
            return
        }

        let responseHeaders = response?.allHeaderFields.reduce(into: [String: String]()) { partialResult, item in
            if let key = item.key as? String {
                partialResult[key] = String(describing: item.value)
            }
        } ?? [:]

        let textBody = String(data: data, encoding: .utf8)

        workQueue.enqueue(operation: {
            try await pluginDriver.onFrame(
                frameType: .httpResponse,
                text: textBody,
                data: textBody == nil ? data : nil,
                statusCode: response?.statusCode,
                responseHeaders: responseHeaders
            )
        }) { [weak self] outcome in
            guard let self, self.shouldReconnect else { return }
            switch outcome {
            case .success(let result):
                self.isRequestInFlight = false
                if self.reconnectPolicy.attempts > 0 || !self.hasReceivedResponse {
                    self.reconnectPolicy.connected()
                    self.hasNotifiedDisconnect = false
                    self.hasReceivedResponse = true
                    self.delegate?.webSocketDidConnect()
                }
                self.applyDriverResult(result)
                if let poll = result.poll { self.executePoll(poll) }
            case .failure(let error):
                self.handleDriverFailure(error)
            }
        }
    }

    func handleDriverFailure(_ error: Error) {
        guard shouldReconnect else { return }
        tearDownAttempt(reason: .error)
        if !hasNotifiedDisconnect {
            hasNotifiedDisconnect = true
            delegate?.webSocketDidDisconnect(error: error)
        }
        guard cancelReconnect == nil else { return }
        let token = workQueue.generation
        cancelReconnect = schedule(reconnectPolicy.delay + Double.random(in: 0...1), false) { [weak self] in
            guard let self, self.shouldReconnect, self.workQueue.generation == token else { return }
            self.cancelReconnect?()
            self.cancelReconnect = nil
            self.reconnectPolicy.beginAttempt()
            self.delegate?.webSocketIsReconnecting(attempt: self.reconnectPolicy.attempts, maxAttempts: 0)
            self.startSession()
        }
    }
}
