import Foundation
import Starscream

public protocol WebSocketConnectionDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceiveMessage(text: String, nickname: String, color: UInt32)
}

public final class WebSocketConnection {
    var socket: WebSocket?
    public var parameters: [String: String]?
    var headers: [String: String]?
    public weak var delegate: WebSocketConnectionDelegate?

    let liveType: LiveType

    private let pluginId: String?
    private let danmakuPlan: LiveParseDanmakuPlan?
    private var pluginDriver: PluginJSDanmakuDriver?
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var shouldReconnect = true
    private var isClosingAfterDriverFailure = false
    private var reconnectAttempts = 0
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

        if danmakuPlan.usesPluginRuntimeDriver {
            self.pluginDriver = PluginJSDanmakuDriver(
                pluginId: pluginId,
                roomId: roomId,
                userId: userId,
                plan: danmakuPlan
            )
        }
    }

    deinit {
        Task { [pluginDriver] in
            await pluginDriver?.destroy(reason: .deinitialized)
        }
        disconnect()
    }

    public func connect() {
        shouldReconnect = true
        consoleBeginConnectEntry(method: "connect")

        guard let pluginDriver else {
            notifyDisconnected(
                error: LiveParseError.danmuArgsParseError("弹幕驱动不受支持", "插件未声明 runtime.driver=plugin_js_v1：\(liveType.rawValue)")
            )
            return
        }

        guard let requestURL else {
            notifyDisconnected(
                error: LiveParseError.danmuArgsParseError("弹幕连接地址缺失", "插件未返回可用的 transport.url / ws_url")
            )
            return
        }

        Task {
            do {
                let result = try await pluginDriver.createSession()
                applyDriverResult(result)
                await MainActor.run {
                    self.connectSocket(url: requestURL)
                }
            } catch {
                handleDriverFailure(error)
            }
        }
    }

    public func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        socket?.disconnect()
        socket?.forceDisconnect()
        socket = nil

        Task { [pluginDriver] in
            await pluginDriver?.destroy(reason: .disconnect)
        }
    }

    private func connectSocket(url: URL) {
        // Starscream 的 TCPTransport 在 NWEndpoint.Port(rawValue: UInt16(port))! 上做了强解,
        // 当 port==0(URL 显式带 :0,或非 ws/wss 协议下被默认为 0 的极端情况)会直接 trap。
        // 这里在交给 Starscream 之前拦截非法端口,改为正常错误回调,避免崩溃。
        guard WebSocketConnection.hasUsableEndpoint(url) else {
            shouldReconnect = false
            notifyDisconnected(
                error: LiveParseError.danmuArgsParseError("弹幕连接地址非法", "URL 缺少有效 host/port:\(url.absoluteString)")
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

        let socket = WebSocket(request: request)
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

    private func scheduleReconnect() {
        guard shouldReconnect else { return }

        reconnectTimer?.invalidate()
        let interval: TimeInterval = 10
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.shouldReconnect, let url = self.requestURL else { return }
            self.reconnectAttempts += 1
            self.consoleBeginConnectEntry(method: "reconnect#\(self.reconnectAttempts)")
            self.connectSocket(url: url)
        }
        if let reconnectTimer {
            RunLoop.current.add(reconnectTimer, forMode: .common)
        }
    }

    /// 包一层 delegate 调用,顺便把"连接成功"打到开发者控制台。
    fileprivate func notifyConnected() {
        consoleFinishEntry(status: .success, message: "WebSocket 连接已建立")
        delegate?.webSocketDidConnect()
    }

    /// 包一层 delegate 调用,顺便把"连接断开/失败"打到开发者控制台。
    fileprivate func notifyDisconnected(error: Error?) {
        consoleFinishEntry(status: .error, message: consoleErrorDescription(for: error))
        delegate?.webSocketDidDisconnect(error: error)
    }
}

// MARK: - DevConsole 钩子

private extension WebSocketConnection {
    /// 开一行 console 日志记录本次连接尝试。后续 notifyConnected/notifyDisconnected 会把它结掉。
    func consoleBeginConnectEntry(method: String) {
        let liveTypeRaw = liveType.rawValue
        let pluginIdSnapshot = pluginId ?? "-"
        let urlSnapshot = requestURL?.absoluteString ?? "<missing>"
        let driverSnapshot = pluginDriver
        let start = Date()
        consoleConnectStart = start
        Task { @MainActor in
            let id = PluginConsoleService.shared.log(tag: "Danmaku", method: method, status: .loading)
            PluginConsoleService.shared.updateRequest(
                id: id,
                body: """
                liveType: \(liveTypeRaw)
                pluginId: \(pluginIdSnapshot)
                roomId: \(driverSnapshot?.roomId ?? "-")
                userId: \(driverSnapshot?.userId ?? "-")
                url: \(urlSnapshot)
                """
            )
            self.consoleEntryId = id
        }
    }

    func consoleFinishEntry(status: PluginConsoleEntryStatus, message: String?) {
        let start = consoleConnectStart
        consoleConnectStart = nil
        Task { @MainActor in
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
    public func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected:
            reconnectAttempts = 0
            reconnectTimer?.invalidate()
            reconnectTimer = nil

            guard let pluginDriver else {
                handleDriverFailure(
                    LiveParseError.danmuArgsParseError("弹幕驱动不受支持", "插件驱动在连接建立后丢失")
                )
                return
            }

            Task {
                do {
                    let result = try await pluginDriver.onOpen()
                    applyDriverResult(result)
                    notifyConnected()
                } catch {
                    handleDriverFailure(error)
                }
            }
        case .disconnected(let reason, let code):
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil

            if isClosingAfterDriverFailure {
                isClosingAfterDriverFailure = false
                Task { [pluginDriver] in
                    await pluginDriver?.destroy(reason: .error)
                }
                return
            }

            let error = NSError(
                domain: "websocket.disconnected",
                code: Int(code),
                userInfo: [
                    "reason": reason,
                    NSLocalizedDescriptionKey: reason
                ]
            )
            notifyDisconnected(error: error)
            scheduleReconnect()
        case .text(let string):
            handleIncomingFrame(frameType: .text, text: string, data: nil)
        case .binary(let data):
            handleIncomingFrame(frameType: .binary, text: nil, data: data)
        case .error(let error):
            if let upgradeError = error as? HTTPUpgradeError {
                switch upgradeError {
                case .notAnUpgrade(let statusCode, let responseHeaders):
                    Logger.error(
                        "[DanmuWS] HTTP upgrade rejected status=\(statusCode), headers=\(responseHeaders)",
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
        guard let pluginDriver else {
            handleDriverFailure(
                LiveParseError.danmuArgsParseError("弹幕驱动不受支持", "插件驱动在收包时丢失")
            )
            return
        }

        Task {
            do {
                let result = try await pluginDriver.onFrame(
                    frameType: frameType,
                    text: text,
                    data: data
                )
                applyDriverResult(result)
            } catch {
                handleDriverFailure(error)
            }
        }
    }

    func applyDriverResult(_ result: LiveParseDanmakuDriverResult) {
        deliverMessages(result.messages)
        sendWrites(result.writes)
        updateTimer(result.timer)
    }

    func deliverMessages(_ messages: [LiveParseDanmakuMessage]?) {
        guard let messages else { return }
        for message in messages {
            delegate?.webSocketDidReceiveMessage(
                text: message.text,
                nickname: message.nickname,
                color: message.color ?? 0xFFFFFF
            )
        }
    }

    func sendWrites(_ writes: [LiveParseDanmakuWriteAction]?) {
        guard let writes else { return }
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
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        guard let timer else { return }
        switch timer.mode {
        case .off:
            return
        case .heartbeat:
            driverTimerReason = .heartbeat
        case .polling:
            driverTimerReason = .polling
        }

        let interval = max(Double(timer.intervalMs ?? 0) / 1000.0, 1.0)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runDriverTick()
        }
        if let heartbeatTimer {
            RunLoop.current.add(heartbeatTimer, forMode: .common)
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
        guard let pluginDriver else { return }
        Task {
            do {
                let result = try await pluginDriver.onTick(reason: driverTimerReason)
                applyDriverResult(result)
            } catch {
                handleDriverFailure(error)
            }
        }
    }

    func handleConnectionFailure(_ error: Error?) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        notifyDisconnected(error: error)
        scheduleReconnect()
    }

    func handleDriverFailure(_ error: Error) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        shouldReconnect = false
        notifyDisconnected(error: error)
        isClosingAfterDriverFailure = true
        socket?.disconnect()
        socket?.forceDisconnect()
        socket = nil

        Task { [pluginDriver] in
            await pluginDriver?.destroy(reason: .error)
        }
    }
}
