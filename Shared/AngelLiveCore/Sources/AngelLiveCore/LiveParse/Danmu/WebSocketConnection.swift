import Foundation
import Starscream

public protocol WebSocketConnectionDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceiveMessage(text: String, nickname: String, color: UInt32)
    /// 一次重连尝试开始时回调(attempt 为第几次,从 1 起;maxAttempts 为上限)。
    /// 提供默认空实现,既有实现方可不改;需要"正在重连"提示的平台再覆写。
    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int)
}

public extension WebSocketConnectionDelegate {
    func webSocketIsReconnecting(attempt: Int, maxAttempts: Int) {}
}

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
    private var pluginDriver: PluginJSDanmakuDriver?
    /// 心跳/轮询定时器。用 DispatchSourceTimer(而非 Timer)以摆脱 RunLoop 依赖:
    /// 驱动结果在并发续体线程上应用,那种线程 RunLoop 永不转,Timer 会静默失效。
    private var heartbeatTimer: DispatchSourceTimer?
    private var reconnectTimer: Timer?
    private var shouldReconnect = true
    private var isClosingAfterDriverFailure = false
    private var reconnectAttempts = 0
    /// 重连次数上限,达到后放弃并通知 UI
    private let maxReconnectAttempts = 8
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
        reconnectAttempts = 0
        hasNotifiedDisconnect = false
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
                handleRecoverableDriverFailure(error)
            }
        }
    }

    public func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        heartbeatTimer?.cancel()
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

    /// 安排下一次重连:指数退避 + 抖动 + 次数上限。到达上限则放弃并通知 UI。
    /// 可能从后台 Task(驱动回调)调入,Timer 必须落到主 runloop 才会触发,故统一切主线程。
    private func scheduleReconnect() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleReconnect() }
            return
        }
        guard shouldReconnect else { return }

        guard reconnectAttempts < maxReconnectAttempts else {
            // 连续重连仍失败:停止并给 UI 一条最终"已停止"通知
            shouldReconnect = false
            reconnectTimer?.invalidate()
            reconnectTimer = nil
            Logger.error("[DanmuWS] reconnect gave up after \(maxReconnectAttempts) attempts", category: .danmu)
            notifyDisconnected(
                error: LiveParseError.danmuArgsParseError(
                    "弹幕已断开",
                    "连续重连 \(maxReconnectAttempts) 次仍未成功,已停止重试"
                )
            )
            return
        }

        reconnectTimer?.invalidate()
        // 指数退避:2,4,8,16,30,30…(秒)+ 0~1s 抖动,避免雪崩式同步重连
        let backoff = min(2.0 * pow(2.0, Double(reconnectAttempts)), 30.0)
        let interval = backoff + Double.random(in: 0...1)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.shouldReconnect else { return }
            self.reconnectAttempts += 1
            self.reconnectWithFreshSession()
        }
        if let reconnectTimer {
            RunLoop.current.add(reconnectTimer, forMode: .common)
        }
    }

    /// 重连:销毁旧 driver,用新的 connectionId 重建并重跑 createSession(刷新握手/token),再连 socket。
    private func reconnectWithFreshSession() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reconnectWithFreshSession() }
            return
        }
        guard shouldReconnect else { return }

        // 通知 UI 本次重连已开始(attempt 已在调度时自增)
        delegate?.webSocketIsReconnecting(attempt: reconnectAttempts, maxAttempts: maxReconnectAttempts)

        heartbeatTimer?.cancel()
        heartbeatTimer = nil

        // 销毁旧 driver(归因 .reconnect);连接层路径并未销毁,这里统一兜底
        if let old = pluginDriver {
            Task { await old.destroy(reason: .reconnect) }
        }

        // 重建 driver 所需要素;缺任一则视为致命,停止重连
        guard let pluginId,
              let danmakuPlan,
              danmakuPlan.usesPluginRuntimeDriver,
              let roomId else {
            shouldReconnect = false
            notifyDisconnected(
                error: LiveParseError.danmuArgsParseError("弹幕重连失败", "缺少重建会话所需信息")
            )
            return
        }

        let driver = PluginJSDanmakuDriver(
            pluginId: pluginId,
            roomId: roomId,
            userId: userId,
            plan: danmakuPlan
        )
        pluginDriver = driver

        guard let requestURL else {
            shouldReconnect = false
            notifyDisconnected(
                error: LiveParseError.danmuArgsParseError("弹幕重连失败", "重连时连接地址缺失")
            )
            return
        }

        consoleBeginConnectEntry(method: "reconnect#\(reconnectAttempts)")

        Task {
            do {
                let result = try await driver.createSession()
                applyDriverResult(result)
                await MainActor.run {
                    guard self.shouldReconnect else { return }
                    self.connectSocket(url: requestURL)
                }
            } catch {
                await MainActor.run {
                    self.handleReconnectAttemptFailure(error)
                }
            }
        }
    }

    /// 一次重连尝试自身失败(如 createSession 抛错):记一次,继续退避重连。
    private func handleReconnectAttemptFailure(_ error: Error) {
        consoleFinishEntry(status: .error, message: consoleErrorDescription(for: error))
        Logger.error("[DanmuWS] reconnect attempt #\(reconnectAttempts) failed: \(error.localizedDescription)", category: .danmu)
        scheduleReconnect()
    }

    /// 包一层 delegate 调用,顺便把"连接成功"打到开发者控制台。连上即复位重连计数与断开通知闸。
    fileprivate func notifyConnected() {
        reconnectAttempts = 0
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
            reconnectTimer?.invalidate()
            reconnectTimer = nil

            guard let pluginDriver else {
                handleFatalDriverError(
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
                    handleRecoverableDriverFailure(error)
                }
            }
        case .disconnected(let reason, let code):
            heartbeatTimer?.cancel()
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
            notifyDisconnectedOnce(error: error)
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
            handleFatalDriverError(
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
                handleRecoverableDriverFailure(error)
            }
        }
    }

    /// 驱动结果应用:必须在主线程执行。
    /// 调用点均在 `Task { await pluginDriver.xxx() ... applyDriverResult }` 里,续体会恢复在
    /// Swift 并发协作线程池的后台线程上。心跳定时器、delegate 回调(UI)、socket 写入都要求主线程,
    /// 故整体切主线程,顺带消除 heartbeatTimer 属性的跨线程读写竞争。
    func applyDriverResult(_ result: LiveParseDanmakuDriverResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.applyDriverResult(result) }
            return
        }
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

    /// 只在主线程调用(经 applyDriverResult 收口)。DispatchSourceTimer 不依赖 RunLoop,
    /// 明确落在主队列触发;驱动每次返回新的 timer plan,故取消旧源、按需新建。
    func updateTimer(_ timer: LiveParseDanmakuTimerPlan?) {
        heartbeatTimer?.cancel()
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
        // 心跳允许抖动,给 leeway 省电。
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in self?.runDriverTick() }
        heartbeatTimer = source
        source.resume()
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
                handleRecoverableDriverFailure(error)
            }
        }
    }

    /// 可能从后台(socket 回调)调入,统一切主线程,保证 timer 操作安全。
    func handleConnectionFailure(_ error: Error?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleConnectionFailure(error) }
            return
        }
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        notifyDisconnectedOnce(error: error)
        scheduleReconnect()
    }

    /// 致命驱动错误(插件未声明 driver / 驱动丢失):不重连,彻底关闭。
    /// 可能从后台(socket/驱动回调)调入,统一切主线程,保证 timer/socket 操作安全。
    func handleFatalDriverError(_ error: Error) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleFatalDriverError(error) }
            return
        }
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        notifyDisconnected(error: error)
        if socket != nil {
            isClosingAfterDriverFailure = true
            socket?.disconnect()
            socket?.forceDisconnect()
            socket = nil
        }

        Task { [pluginDriver] in
            await pluginDriver?.destroy(reason: .error)
        }
    }

    /// 可恢复驱动错误(createSession/onOpen/onFrame/onTick 抛错):清理后走有限退避重连(重建 session)。
    /// 可能从后台 Task(驱动回调)调入,统一切主线程,保证 socket/timer/delegate 操作安全。
    func handleRecoverableDriverFailure(_ error: Error) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleRecoverableDriverFailure(error) }
            return
        }
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        notifyDisconnectedOnce(error: error)
        if socket != nil {
            // 主动关闭当前 socket;.disconnected 回调会消费此标记并销毁旧 driver,不再二次处理
            isClosingAfterDriverFailure = true
            socket?.disconnect()
            socket?.forceDisconnect()
            socket = nil
        }
        scheduleReconnect()
    }
}
