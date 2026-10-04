import Foundation
import os.lock
@preconcurrency import JavaScriptCore
@preconcurrency import Starscream

/// 通用 WebSocket 会话:供 JS 插件通过 Host.ws.* 驱动,宿主对协议 / 平台一无所知。
/// 单条会话拥有独立串行 queue 处理 Starscream 事件,事件序列化为 JSON 后透传给
/// 注册在 JS 侧的 message handler。
final class HostWebSocketSession: NSObject, @unchecked Sendable {
    let id: String
    let owner: UUID

    private let queue: DispatchQueue
    private let handler: @Sendable (String, Bool) -> Void
    private var socket: WebSocket?
    private var terminal = false

    init(
        id: String,
        owner: UUID,
        request: URLRequest,
        queue: DispatchQueue? = nil,
        handler: @escaping @Sendable (String, Bool) -> Void
    ) {
        self.id = id
        self.owner = owner
        self.queue = queue ?? DispatchQueue(label: "host.ws.session.\(id)")
        self.handler = handler
        super.init()

        let socket = WebSocket(request: request)
        socket.delegate = self
        self.socket = socket
    }

    func connect() {
        queue.async { [weak self] in
            self?.socket?.connect()
        }
    }

    func send(text: String) {
        queue.async { [weak self] in
            self?.socket?.write(string: text)
        }
    }

    func send(binary data: Data) {
        queue.async { [weak self] in
            self?.socket?.write(data: data)
        }
    }

    func close(code: UInt16, reason: String?) {
        queue.async {
            guard !self.terminal else { return }
            self.terminal = true
            self.socket?.disconnect(closeCode: code)
            self.finish(["type": "closed", "code": Int(code), "reason": reason ?? "closed"])
        }
    }

    func tearDown() {
        queue.async {
            self.socket?.delegate = nil
            self.socket?.disconnect()
            self.socket = nil
        }
    }

    func drainForTesting() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    /// 把事件 JSON 透传给 runtime；JS handler 只由对应 JS queue 持有和调用。
    private func emit(_ payload: [String: Any], terminal: Bool = false) {
        guard HostWebSocketRegistry.isActive(owner: owner) else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        handler(json, terminal)
    }

    private func finish(_ payload: [String: Any]) {
        _ = HostWebSocketRegistry.remove(id, owner: owner)
        emit(payload, terminal: true)
        socket?.delegate = nil
        socket = nil
    }
}

extension HostWebSocketSession: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client _: any Starscream.WebSocketClient) {
        receive(event)
    }

    func receive(_ event: Starscream.WebSocketEvent) {
        nonisolated(unsafe) let event = event
        queue.async {
            guard !self.terminal else { return }
            switch event {
            case .connected:
                self.emit(["type": "open"])
            case .binary(let data):
                self.emit(["type": "binary", "bytesBase64": data.base64EncodedString()])
            case .text(let text):
                self.emit(["type": "text", "text": text])
            case .disconnected(let reason, let code):
                self.terminal = true
                self.finish(["type": "closed", "code": Int(code), "reason": reason])
            case .error(let error):
                self.terminal = true
                self.finish(["type": "error", "message": error?.localizedDescription ?? "unknown"])
            case .cancelled:
                self.terminal = true
                self.finish(["type": "closed", "code": 0, "reason": "cancelled"])
            case .peerClosed:
                self.terminal = true
                self.finish(["type": "closed", "code": 0, "reason": "peer closed"])
            case .ping, .pong, .viabilityChanged, .reconnectSuggested:
                break
            }
        }
    }
}

/// 全局会话注册表。pluginId 仅做调试日志追踪用,不参与隔离。
enum HostWebSocketRegistry {
    private struct State: Sendable {
        var activeOwners: Set<UUID> = []
        var sessions: [String: HostWebSocketSession] = [:]
    }
    private static let state = OSAllocatedUnfairLock<State>(initialState: .init())

    static func registerOwner() -> UUID {
        let owner = UUID()
        _ = state.withLock { $0.activeOwners.insert(owner) }
        return owner
    }

    static func isActive(owner: UUID) -> Bool {
        state.withLock { $0.activeOwners.contains(owner) }
    }

    static func add(_ session: HostWebSocketSession, owner: UUID) -> Bool {
        state.withLock {
            guard $0.activeOwners.contains(owner), $0.sessions[session.id] == nil else { return false }
            $0.sessions[session.id] = session
            return true
        }
    }

    static func get(_ id: String, owner: UUID) -> HostWebSocketSession? {
        state.withLock {
            guard $0.sessions[id]?.owner == owner else { return nil }
            return $0.sessions[id]
        }
    }

    @discardableResult
    static func remove(_ id: String, owner: UUID) -> HostWebSocketSession? {
        state.withLock {
            guard $0.sessions[id]?.owner == owner else { return nil }
            return $0.sessions.removeValue(forKey: id)
        }
    }

    static func invalidate(owner: UUID) -> [HostWebSocketSession] {
        state.withLock {
            $0.activeOwners.remove(owner)
            let removed = $0.sessions.values.filter { $0.owner == owner }
            for session in removed { $0.sessions.removeValue(forKey: session.id) }
            return removed
        }
    }

    static func sessionCount(owner: UUID) -> Int {
        state.withLock { state in
            state.sessions.values.count { $0.owner == owner }
        }
    }
}

extension JSRuntime {
    /// 给 JSContext 注册 4 个 native bridge,供 Host.ws.* 在 JS 侧调用:
    /// - `__lp_host_ws_open(optionsJSON, handler) -> sessionId`
    /// - `__lp_host_ws_send(sessionId, frameJSON, resolve, reject)`
    /// - `__lp_host_ws_close(sessionId, optionsJSON, resolve, reject)`
    /// - 不暴露 set_handler:open 时同步把 handler 闭包传进 native 端,事件直接回调。
    func configureHostWebSocket(in context: JSContext) {
        let openBlock: @convention(block) (String, JSValue) -> String = { [weak self] optionsJSON, handler in
            guard let self, HostWebSocketRegistry.isActive(owner: self.hostWebSocketOwner) else { return "" }
            let data = optionsJSON.data(using: .utf8) ?? Data()
            guard
                let options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let urlString = (options["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                let url = URL(string: urlString)
            else {
                return ""
            }

            let authMode = ((options["authMode"] as? String) ?? "none")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let usesPlatformCredential = authMode == "platform_cookie"
            if usesPlatformCredential {
                let runtimePluginId = LiveParsePlatformSessionVault.canonicalPlatformId(self.hostWebSocketPluginID)
                let requestedPluginId = LiveParsePlatformSessionVault.canonicalPlatformId(
                    (options["platformId"] as? String) ?? self.hostWebSocketPluginID
                )
                guard !runtimePluginId.isEmpty,
                      requestedPluginId == runtimePluginId,
                      Self.isAllowedCredentialWebSocketURL(url, domains: self.hostWebSocketCredentialDomains) else {
                    return ""
                }
            }

            var request = URLRequest(url: url)
            let timeoutMs = (options["timeoutMs"] as? Int) ?? (options["timeout_ms"] as? Int) ?? 30_000
            request.timeoutInterval = max(1, TimeInterval(timeoutMs) / 1000)

            if let headers = options["headers"] as? [String: Any] {
                for (key, value) in headers {
                    if usesPlatformCredential,
                       key.caseInsensitiveCompare("Cookie") == .orderedSame {
                        continue
                    }
                    request.setValue(String(describing: value), forHTTPHeaderField: key)
                }
            }
            if usesPlatformCredential,
               let cookie = LiveParsePlatformSessionVault.mergedCookieHeader(
                   for: self.hostWebSocketPluginID,
                   sessionOverride: self.hostWebSocketSessionOverride
               ) {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            if let protocols = options["protocols"] as? [Any], !protocols.isEmpty {
                let joined = protocols.map { String(describing: $0) }.joined(separator: ", ")
                request.setValue(joined, forHTTPHeaderField: "Sec-WebSocket-Protocol")
            }

            let sessionId = UUID().uuidString
            self.hostWebSocketHandlers[sessionId] = handler
            let owner = self.hostWebSocketOwner
            let session = HostWebSocketSession(
                id: sessionId,
                owner: owner,
                request: request,
                handler: { [weak self] json, terminal in
                    self?.deliverHostWebSocketEvent(owner: owner, sessionID: sessionId, json: json, terminal: terminal)
                }
            )
            guard HostWebSocketRegistry.add(session, owner: owner) else {
                self.hostWebSocketHandlers.removeValue(forKey: sessionId)
                session.tearDown()
                return ""
            }
            session.connect()
            let loggedDestination = usesPlatformCredential
                ? "\(url.scheme ?? "wss")://\(url.host ?? "")"
                : urlString
            Logger.debug("[Host.ws] open pluginId=\(self.hostWebSocketPluginID) sessionId=\(sessionId) url=\(loggedDestination)", category: .plugin)
            return sessionId
        }

        let sendBlock: @convention(block) (String, String, JSValue, JSValue) -> Void = { [weak self] sessionId, frameJSON, resolve, reject in
            guard let self else { return }
            nonisolated(unsafe) let resolve = resolve
            nonisolated(unsafe) let reject = reject

            guard let session = HostWebSocketRegistry.get(sessionId, owner: self.hostWebSocketOwner) else {
                self.rejectHostWebSocket(reject, message: "ws session not found: \(sessionId)")
                return
            }

            let data = frameJSON.data(using: .utf8) ?? Data()
            guard let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                self.rejectHostWebSocket(reject, message: "ws send invalid frame json")
                return
            }

            let type = (frame["type"] as? String)?.lowercased() ?? "text"
            switch type {
            case "binary":
                guard let base64 = frame["bytesBase64"] as? String,
                      let bytes = Data(base64Encoded: base64) else {
                    self.rejectHostWebSocket(reject, message: "ws send: missing bytesBase64")
                    return
                }
                session.send(binary: bytes)
            case "text":
                let text = (frame["text"] as? String) ?? ""
                session.send(text: text)
            default:
                self.rejectHostWebSocket(reject, message: "ws send: unknown frame type \(type)")
                return
            }

            self.resolveHostWebSocket(resolve)
        }

        let closeBlock: @convention(block) (String, String, JSValue, JSValue) -> Void = { [weak self] sessionId, optionsJSON, resolve, reject in
            guard let self else { return }
            nonisolated(unsafe) let resolve = resolve
            nonisolated(unsafe) let reject = reject

            let data = optionsJSON.data(using: .utf8) ?? Data()
            let options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let requestedCode = (options["code"] as? Int) ?? 1000
            guard (0...Int(UInt16.max)).contains(requestedCode) else {
                self.rejectHostWebSocket(reject, message: "ws close: invalid close code")
                return
            }
            let code = UInt16(requestedCode)
            let reason = options["reason"] as? String

            guard let session = HostWebSocketRegistry.remove(sessionId, owner: self.hostWebSocketOwner) else {
                // 已不在注册表也算成功(幂等)。
                self.resolveHostWebSocket(resolve)
                _ = reject  // suppress unused
                return
            }

            session.close(code: code, reason: reason)
            session.tearDown()
            self.hostWebSocketHandlers.removeValue(forKey: sessionId)
            self.resolveHostWebSocket(resolve)
        }

        context.setObject(openBlock, forKeyedSubscript: "__lp_host_ws_open" as NSString)
        context.setObject(sendBlock, forKeyedSubscript: "__lp_host_ws_send" as NSString)
        context.setObject(closeBlock, forKeyedSubscript: "__lp_host_ws_close" as NSString)
    }

    private static func isAllowedCredentialWebSocketURL(_ url: URL, domains: [String]) -> Bool {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased() ?? ""
        let secureTransport = scheme == "wss"
        let loopbackTransport = scheme == "ws"
            && (host == "localhost" || host == "127.0.0.1" || host == "::1")
        guard secureTransport || loopbackTransport else { return false }
        return domains.contains { rawDomain in
            let domain = rawDomain
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !domain.isEmpty else { return false }
            return host == domain || host.hasSuffix(".\(domain)")
        }
    }
}
