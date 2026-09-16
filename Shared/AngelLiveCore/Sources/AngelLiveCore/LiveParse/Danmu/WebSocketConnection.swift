import Foundation
@preconcurrency import Starscream

/// 实现方均为三端 `RoomInfoViewModel`(UI 层),回调本就只在主线程消费,
/// 故协议显式标注 `@MainActor`,让隔离要求从"约定"变成"编译器保证"。
@MainActor
public protocol WebSocketConnectionDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceiveMessage(_ message: DanmakuDisplayMessage)
    /// 一次重连尝试开始时回调(attempt 为第几次,从 1 起;maxAttempts 为上限)。
    /// maxAttempts 为 0 时表示持续退避重试，没有次数上限。
    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int)
}

public extension WebSocketConnectionDelegate {
    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int) {}
}

/// 本类原本就是"事实上的主线程收口"——所有状态变更都靠 `DispatchQueue.main.async`、
/// `Task { @MainActor in }`、`await MainActor.run` 手工跳回主线程,只是编译器无从证明,
/// 于是每一次跳转都被判为"sending 非 Sendable self"。
///
/// 显式标注 `@MainActor` 后,这些手工收口全部变成可证明的冗余,得以删除;
/// Starscream 的 delegate 回调默认就在 `DispatchQueue.main`(其 `callbackQueue` 默认值),
/// 故 `didReceive` 用 `assumeIsolated` 而非 `Task {}` 跳板——后者会把事件推迟到下一轮,
/// 破坏弹幕消息与连接事件的到达顺序。
@MainActor
public final class WebSocketConnection {
    var socket: WebSocket?
    public var parameters: [String: String]?
    var headers: [String: String]?
    public weak var delegate: WebSocketConnectionDelegate?

    let liveType: LiveType

    private let pluginId: String?
    private let danmakuPlan: LiveParseDanmakuPlan?
    /// 重连时需要重建 PluginJSDanmakuDriver,故把房间/用户信息持有下来
    private let roomId: String?
    private let userId: String?
    private var pluginDriver: (any DanmakuRuntimeDriving)?
    var makeDriver: DanmakuDriverFactory = { PluginJSDanmakuDriver(pluginId: $0, roomId: $1, userId: $2, plan: $3) }
    var makeSocket: @MainActor (URLRequest) -> WebSocket = { WebSocket(request: $0) }
    var schedule: DanmakuSchedule = scheduleDanmakuWork
    private lazy var heartbeatTimer = DanmakuConnectionTimer(schedule: schedule)
    let workQueue = DanmakuConnectionWorkQueue()
    private var cancelReconnect: (@MainActor () -> Void)?
    private var shouldReconnect = false
    private var reconnectPolicy = DanmakuReconnectPolicy()
    private var socketIsOpen = false
    private var pendingWrites: [LiveParseDanmakuWriteAction] = []
    /// 去重断开通知:重连期间只首次回调 delegate,避免刷屏
    private var hasNotifiedDisconnect = false
    private var driverTimerReason: PluginJSDanmakuDriver.TickReason = .heartbeat
    /// 当前活动 console entry id —— 让 connect/connected/disconnected 三个事件能挂到同一行日志上。
    /// 仅在主队列回调链上读写,数据竞争可控。
    private var consoleEntryId: UUID?
    private var consoleConnectStart: Date?

    private var requestURL: URL? {
        if let raw = danmakuPlan?.transport?.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        if let raw = parameters?["ws_url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        if let raw = parameters?["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return nil
    }

    public init(parameters: [String: String]?, headers: [String: String]?, liveType: LiveType) {
        self.parameters = parameters
        self.headers = headers
        self.liveType = liveType
        self.pluginId = nil
        self.danmakuPlan = nil
        self.roomId = nil
        self.userId = nil
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
        self.pluginId = pluginId
        self.danmakuPlan = danmakuPlan
        self.roomId = roomId
        self.userId = userId

    }

    /// `isolated deinit`:在主 actor 上执行析构。
    /// 否则 nonisolated deinit 无法访问 `socket` / `cancelReconnect` 这类非 Sendable 存储属性
    /// (Swift 6 会报错),也就没法复用 `disconnect()` 的完整拆除逻辑。
    isolated deinit {
        disconnect()
    }

    public func connect() {
        guard !shouldReconnect else { return }
        shouldReconnect = true
        reconnectPolicy.connected()
        hasNotifiedDisconnect = false
        reconnectWithFreshSession()
    }

    public func disconnect() {
        shouldReconnect = false
        cancelReconnect?()
        cancelReconnect = nil
        tearDownAttempt()
        retireDriver(reason: .disconnect)
    }

    private func tearDownAttempt() {
        workQueue.invalidate()
        heartbeatTimer.stop()
        socketIsOpen = false
        pendingWrites.removeAll()
        let oldSocket = socket
        socket = nil
        oldSocket?.delegate = nil
        oldSocket?.disconnect()
        oldSocket?.forceDisconnect()
    }

    private func retireDriver(reason: PluginJSDanmakuDriver.DestroyReason) {
        let old = pluginDriver
        pluginDriver = nil
        Task { await old?.destroy(reason: reason) }
    }

    private func connectSocket(url: URL) {
        // Starscream 的 TCPTransport 在 NWEndpoint.Port(rawValue: UInt16(port))! 上做了强解,
        // 当 port==0(URL 显式带 :0,或非 ws/wss 协议下被默认为 0 的极端情况)会直接 trap。
        // 这里在交给 Starscream 之前拦截非法端口,改为正常错误回调,避免崩溃。
        guard WebSocketConnection.hasUsableEndpoint(url) else {
            handleFatalDriverError(
                LiveParseError.danmuArgsParseError("弹幕连接地址非法", "URL 缺少有效 host/port")
            )
            return
        }

        var request = URLRequest(url: url)

        if let subprotocols = danmakuPlan?.transport?.subprotocols, !subprotocols.isEmpty {
            request.setValue(subprotocols.joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        for (key, value) in effectiveWebSocketHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let socket = makeSocket(request)
        socket.delegate = self
        self.socket = socket
        socket.connect()
    }

    /// 校验 URL 在 Starscream/Network.framework 下能否安全建连。
    /// 必须满足:host 非空,且 NWEndpoint.Port 能用有效 port 构造(即 1..65535)。
    private static func hasUsableEndpoint(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        let port: Int
        if let explicit = url.port {
            port = explicit
        } else {
            let scheme = url.scheme?.lowercased() ?? ""
            port = (scheme == "wss" || scheme == "https") ? 443 : 80
        }
        return port > 0 && port <= 65535
    }

    /// Keep retrying at a bounded rate while the user remains in this room.
    private func scheduleReconnect() {
        guard shouldReconnect, cancelReconnect == nil else { return }
        let token = workQueue.generation
        cancelReconnect = schedule(reconnectPolicy.delay + Double.random(in: 0...1), false) { [weak self] in
            guard let self, self.shouldReconnect, self.workQueue.generation == token else { return }
            self.cancelReconnect?()
            self.cancelReconnect = nil
            self.reconnectPolicy.beginAttempt()
            self.reconnectWithFreshSession()
        }
    }

    private func reconnectWithFreshSession() {
        guard shouldReconnect else { return }
        if reconnectPolicy.attempts > 0 {
            delegate?.webSocketIsReconnecting(attempt: reconnectPolicy.attempts, maxAttempts: 0)
        }
        tearDownAttempt()
        retireDriver(reason: .reconnect)

        guard let pluginId, let danmakuPlan, danmakuPlan.usesPluginRuntimeDriver, let roomId else {
            handleFatalDriverError(
                LiveParseError.danmuArgsParseError("弹幕驱动不受支持", "缺少重建会话所需信息")
            )
            return
        }
        guard let requestURL else {
            handleFatalDriverError(
                LiveParseError.danmuArgsParseError("弹幕连接地址缺失", "插件未返回可用的 transport.url / ws_url")
            )
            return
        }
        let driver = makeDriver(pluginId, roomId, userId, danmakuPlan)
        pluginDriver = driver
        consoleBeginConnectEntry(method: reconnectPolicy.attempts == 0 ? "connect" : "reconnect#\(reconnectPolicy.attempts)")
        workQueue.enqueue(operation: { try await driver.createSession() }) { [weak self] outcome in
            guard let self, self.shouldReconnect else { return }
            switch outcome {
            case .success(let result):
                self.connectSocket(url: requestURL)
                self.applyDriverResult(result)
            case .failure(let error):
                self.handleRecoverableDriverFailure(error)
            }
        }
    }

    /// 包一层 delegate 调用,顺便把"连接成功"打到开发者控制台。连上即复位重连计数与断开通知闸。
    fileprivate func notifyConnected() {
        reconnectPolicy.connected()
        hasNotifiedDisconnect = false
        consoleFinishEntry(status: .success, message: "WebSocket 连接已建立")
        delegate?.webSocketDidConnect()
    }

    /// 强制把"断开/失败"回调给 delegate(致命错误 / 最终放弃):总是通知。
    fileprivate func notifyDisconnected(error: Error?) {
        consoleFinishEntry(status: .error, message: consoleErrorDescription(for: error))
        hasNotifiedDisconnect = true
        delegate?.webSocketDidDisconnect(error: error)
    }

    /// 去重版断开回调:重连期间只首次通知 UI,后续失败仅记日志,避免刷屏。
    fileprivate func notifyDisconnectedOnce(error: Error?) {
        consoleFinishEntry(status: .error, message: consoleErrorDescription(for: error))
        guard !hasNotifiedDisconnect else { return }
        hasNotifiedDisconnect = true
        delegate?.webSocketDidDisconnect(error: error)
    }
}

// MARK: - DevConsole 钩子

private extension WebSocketConnection {
    /// 开一行 console 日志记录本次连接尝试。后续 notifyConnected/notifyDisconnected 会把它结掉。
    func consoleBeginConnectEntry(method: String) {
        let liveTypeRaw = liveType.rawValue
        let pluginIdSnapshot = pluginId ?? "-"
        let urlSnapshot = requestURL?.host ?? "<missing>"
        let start = Date()
        consoleConnectStart = start
        let id = PluginConsoleService.shared.log(tag: "Danmaku", method: method, status: .loading)
        PluginConsoleService.shared.updateRequest(
            id: id,
            body: """
            liveType: \(liveTypeRaw)
            pluginId: \(pluginIdSnapshot)
            roomId: \(self.roomId ?? "-")
            url: \(urlSnapshot)
            """
        )
        self.consoleEntryId = id
    }

    func consoleFinishEntry(status: PluginConsoleEntryStatus, message: String?) {
        let start = consoleConnectStart
        consoleConnectStart = nil
        guard let id = self.consoleEntryId else { return }
        self.consoleEntryId = nil
        let duration: TimeInterval? = start.map { Date().timeIntervalSince($0) }
        PluginConsoleService.shared.updateStatus(
            id: id,
            status: status,
            duration: duration,
            responseBody: status == .success ? message : nil,
            errorMessage: status == .error ? message : nil
        )
    }

    func consoleErrorDescription(for error: Error?) -> String {
        guard let error else { return "未知错误" }
        if let nsError = error as NSError? {
            var lines: [String] = [nsError.localizedDescription]
            lines.append("domain: \(nsError.domain) code: \(nsError.code)")
            for (key, value) in nsError.userInfo where key != NSLocalizedDescriptionKey {
                lines.append("\(key): \(value)")
            }
            return lines.joined(separator: "\n")
        }
        return error.localizedDescription
    }
}

extension WebSocketConnection: WebSocketDelegate {
    /// Starscream 的 `callbackQueue` 默认值就是 `DispatchQueue.main`,且本类从未覆盖它,
    /// 因此该回调必定在主线程。这里用 `assumeIsolated` 直接复用主 actor 隔离,
    /// **刻意不用 `Task { @MainActor in }`** —— 后者会把事件推迟到下一轮,
    /// 打乱 connected / message / disconnected 的到达顺序,对弹幕流是实质行为变更。
    ///
    /// A delayed event from a retired socket must never mutate the replacement.
    public nonisolated func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        MainActor.assumeIsolated {
            guard shouldReconnect, let socket, client === socket else { return }
            handleSocketEvent(event)
        }
    }

    private func handleSocketEvent(_ event: Starscream.WebSocketEvent) {
        switch event {
        case .connected:
            guard !socketIsOpen else { return }
            socketIsOpen = true
            let writes = pendingWrites
            pendingWrites.removeAll()
            sendWrites(writes)
            cancelReconnect?()
            cancelReconnect = nil
            guard let driver = pluginDriver else { return }
            workQueue.enqueue(operation: { try await driver.onOpen() }) { [weak self] outcome in
                guard let self, self.shouldReconnect else { return }
                switch outcome {
                case .success(let result):
                    self.applyDriverResult(result)
                    self.notifyConnected()
                case .failure(let error):
                    self.handleRecoverableDriverFailure(error)
                }
            }
        case .disconnected(let reason, let code):
            handleConnectionFailure(NSError(
                domain: "websocket.disconnected", code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: reason]
            ))
        case .text(let string):
            handleIncomingFrame(frameType: .text, text: string, data: nil)
        case .binary(let data):
            handleIncomingFrame(frameType: .binary, text: nil, data: data)
        case .error(let error):
            if let upgradeError = error as? HTTPUpgradeError {
                switch upgradeError {
                case .notAnUpgrade(let statusCode, _):
                    Logger.error(
                        "[DanmuWS] HTTP upgrade rejected status=\(statusCode)",
                        category: .danmu
                    )
                case .invalidData:
                    Logger.error(
                        "[DanmuWS] HTTP upgrade invalidData",
                        category: .danmu
                    )
                }
            } else {
                Logger.error(
                    "[DanmuWS] websocket error: \(error?.localizedDescription ?? "nil")",
                    category: .danmu
                )
            }
            handleConnectionFailure(error)
        case .cancelled:
            handleConnectionFailure(
                NSError(
                    domain: "websocket.cancelled",
                    code: -999,
                    userInfo: [NSLocalizedDescriptionKey: "WebSocket cancelled"]
                )
            )
        case .peerClosed:
            handleConnectionFailure(
                NSError(
                    domain: "websocket.peerClosed",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "WebSocket peer closed"]
                )
            )
        default:
            break
        }
    }
}

private extension WebSocketConnection {
    func handleIncomingFrame(
        frameType: PluginJSDanmakuDriver.IncomingFrameType,
        text: String?,
        data: Data?
    ) {
        guard shouldReconnect, let driver = pluginDriver else { return }
        workQueue.enqueue(operation: {
            try await driver.onFrame(frameType: frameType, text: text, data: data, statusCode: nil, responseHeaders: nil)
        }) { [weak self] outcome in
            guard let self, self.shouldReconnect else { return }
            switch outcome {
            case .success(let result): self.applyDriverResult(result)
            case .failure(let error): self.handleRecoverableDriverFailure(error)
            }
        }
    }

    /// 驱动结果应用:心跳定时器、delegate 回调(UI)、socket 写入都要求主线程。
    /// 类已是 `@MainActor`,调用点里 `await` 的续体会自动恢复到主 actor,
    /// 原先手写的 `Thread.isMainThread` 收口与 heartbeatTimer 跨线程竞争问题一并由隔离保证。
    func applyDriverResult(_ result: LiveParseDanmakuDriverResult) {
        guard shouldReconnect else { return }
        deliverMessages(result.messages)
        sendWrites(result.writes)
        updateTimer(result.timer)
    }

    func deliverMessages(_ messages: [LiveParseDanmakuMessage]?) {
        guard let messages else { return }
        for message in messages {
            delegate?.webSocketDidReceiveMessage(DanmakuDisplayMessage(message))
        }
    }

    func sendWrites(_ writes: [LiveParseDanmakuWriteAction]?) {
        guard let writes else { return }
        guard socketIsOpen else { pendingWrites.append(contentsOf: writes); return }
        for write in writes {
            switch write.kind {
            case .text:
                guard let text = write.text else { continue }
                socket?.write(string: text)
            case .binary:
                guard let bytesBase64 = write.bytesBase64,
                      let data = Data(base64Encoded: bytesBase64) else { continue }
                socket?.write(data: data)
            }
        }
    }

    func updateTimer(_ timer: LiveParseDanmakuTimerPlan?) {
        heartbeatTimer.update(timer) { [weak self] in self?.runDriverTick() }
        if let timer {
            switch timer.mode {
            case .heartbeat: driverTimerReason = .heartbeat
            case .polling: driverTimerReason = .polling
            case .off: break
            }
        }
    }

    func effectiveWebSocketHeaders() -> [String: String] {
        guard let headers else { return [:] }

        if danmakuPlan?.runtime?.webSocketHeaderMode == .minimalNoCookie {
            var effective: [String: String] = [:]

            if let userAgent = headerValue(named: "User-Agent", in: headers) {
                effective["User-Agent"] = userAgent
            }
            if let origin = headerValue(named: "Origin", in: headers) {
                effective["Origin"] = origin
            }
            if let host = requestURL?.host, !host.isEmpty {
                effective["Host"] = host
            }

            // Some transports require a minimal handshake and no auto-injected cookies.
            effective["Cookie"] = ""
            return effective
        }

        return headers
    }

    func headerValue(named name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func runDriverTick() {
        guard shouldReconnect, let driver = pluginDriver else { return }
        let reason = driverTimerReason
        workQueue.enqueue(key: "tick", operation: { try await driver.onTick(reason: reason) }) { [weak self] outcome in
            guard let self, self.shouldReconnect else { return }
            switch outcome {
            case .success(let result): self.applyDriverResult(result)
            case .failure(let error): self.handleRecoverableDriverFailure(error)
            }
        }
    }

    func handleConnectionFailure(_ error: Error?) {
        guard shouldReconnect else { return }
        tearDownAttempt()
        retireDriver(reason: .error)
        notifyDisconnectedOnce(error: error)
        scheduleReconnect()
    }

    func handleFatalDriverError(_ error: Error) {
        disconnect()
        notifyDisconnected(error: error)
    }

    func handleRecoverableDriverFailure(_ error: Error) {
        handleConnectionFailure(error)
    }
}
