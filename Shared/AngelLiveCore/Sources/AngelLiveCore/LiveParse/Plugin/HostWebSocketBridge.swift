import Foundation
@preconcurrency import JavaScriptCore
@preconcurrency import Starscream

/// 通用 WebSocket 会话:供 JS 插件通过 Host.ws.* 驱动,宿主对协议 / 平台一无所知。
/// 单条会话拥有独立串行 queue 处理 Starscream 事件,事件序列化为 JSON 后透传给
/// 注册在 JS 侧的 message handler。
final class HostWebSocketSession: NSObject, @unchecked Sendable {
    let id: String

    private let queue: DispatchQueue
    private let handlerQueue: DispatchQueue
    private let handler: @Sendable (String) -> Void
    private var socket: WebSocket?
    private var pending: [String] = []
    private var didOpen: Bool = false
    private var didClose: Bool = false
    private let lock = NSLock()

    init(
        id: String,
        request: URLRequest,
        handlerQueue: DispatchQueue,
        handler: @escaping @Sendable (String) -> Void
    ) {
        self.id = id
        self.queue = DispatchQueue(label: "host.ws.session.\(id)")
        self.handlerQueue = handlerQueue
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
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.didClose = true
            self.lock.unlock()
            self.socket?.disconnect(closeCode: code)
        }
    }

    func tearDown() {
        queue.async { [weak self] in
            self?.socket?.disconnect()
            self?.socket?.delegate = nil
            self?.socket = nil
        }
    }

    /// 把事件 JSON 透传给 JS handler。在事件抵达但 JS 那边的 handler 尚未挂上前(open Promise
    /// resolve 前的极短窗口),先 buffer,JS 调 set_handler 时一次性 flush。
    private func emit(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        handlerQueue.async { [handler] in
            handler(json)
        }
    }
}

extension HostWebSocketSession: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client _: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            lock.lock()
            didOpen = true
            lock.unlock()
            emit(["type": "open"])
        case .binary(let data):
            emit(["type": "binary", "bytesBase64": data.base64EncodedString()])
        case .text(let text):
            emit(["type": "text", "text": text])
        case .disconnected(let reason, let code):
            emit(["type": "closed", "code": Int(code), "reason": reason])
        case .error(let error):
            emit(["type": "error", "message": error?.localizedDescription ?? "unknown"])
        case .cancelled:
            emit(["type": "closed", "code": 0, "reason": "cancelled"])
        case .peerClosed:
            emit(["type": "closed", "code": 0, "reason": "peer closed"])
        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            break
        }
    }
}

/// 全局会话注册表。pluginId 仅做调试日志追踪用,不参与隔离。
enum HostWebSocketRegistry {
    private static let lock = NSLock()
    private static var sessions: [String: HostWebSocketSession] = [:]

    static func add(_ session: HostWebSocketSession) {
        lock.lock(); defer { lock.unlock() }
        sessions[session.id] = session
    }

    static func get(_ id: String) -> HostWebSocketSession? {
        lock.lock(); defer { lock.unlock() }
        return sessions[id]
    }

    @discardableResult
    static func remove(_ id: String) -> HostWebSocketSession? {
        lock.lock(); defer { lock.unlock() }
        return sessions.removeValue(forKey: id)
    }
}

extension JSRuntime {
    /// 给 JSContext 注册 4 个 native bridge,供 Host.ws.* 在 JS 侧调用:
    /// - `__lp_host_ws_open(optionsJSON, handler) -> sessionId`
    /// - `__lp_host_ws_send(sessionId, frameJSON, resolve, reject)`
    /// - `__lp_host_ws_close(sessionId, optionsJSON, resolve, reject)`
    /// - 不暴露 set_handler:open 时同步把 handler 闭包传进 native 端,事件直接回调。
    static func configureHostWebSocket(in context: JSContext, queue: DispatchQueue, pluginId: String) {
        let openBlock: @convention(block) (String, JSValue) -> String = { optionsJSON, handler in
            let data = optionsJSON.data(using: .utf8) ?? Data()
            guard
                let options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let urlString = (options["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                let url = URL(string: urlString)
            else {
                return ""
            }

            var request = URLRequest(url: url)
            let timeoutMs = (options["timeoutMs"] as? Int) ?? (options["timeout_ms"] as? Int) ?? 30_000
            request.timeoutInterval = max(1, TimeInterval(timeoutMs) / 1000)

            if let headers = options["headers"] as? [String: Any] {
                for (key, value) in headers {
                    request.setValue(String(describing: value), forHTTPHeaderField: key)
                }
            }
            if let protocols = options["protocols"] as? [Any], !protocols.isEmpty {
                let joined = protocols.map { String(describing: $0) }.joined(separator: ", ")
                request.setValue(joined, forHTTPHeaderField: "Sec-WebSocket-Protocol")
            }

            let sessionId = UUID().uuidString
            // handler 在另一个 thread 触发,要切回 JS queue 才能安全调 JS 函数。
            nonisolated(unsafe) let capturedHandler = handler
            let session = HostWebSocketSession(
                id: sessionId,
                request: request,
                handlerQueue: queue
            ) { json in
                capturedHandler.call(withArguments: [json])
                context.evaluateScript("void(0)")
            }
            HostWebSocketRegistry.add(session)
            session.connect()
            Logger.debug("[Host.ws] open pluginId=\(pluginId) sessionId=\(sessionId) url=\(urlString)", category: .plugin)
            return sessionId
        }

        let sendBlock: @convention(block) (String, String, JSValue, JSValue) -> Void = { sessionId, frameJSON, resolve, reject in
            nonisolated(unsafe) let resolve = resolve
            nonisolated(unsafe) let reject = reject

            guard let session = HostWebSocketRegistry.get(sessionId) else {
                queue.async {
                    reject.call(withArguments: ["ws session not found: \(sessionId)"])
                    context.evaluateScript("void(0)")
                }
                return
            }

            let data = frameJSON.data(using: .utf8) ?? Data()
            guard let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                queue.async {
                    reject.call(withArguments: ["ws send invalid frame json"])
                    context.evaluateScript("void(0)")
                }
                return
            }

            let type = (frame["type"] as? String)?.lowercased() ?? "text"
            switch type {
            case "binary":
                guard let base64 = frame["bytesBase64"] as? String,
                      let bytes = Data(base64Encoded: base64) else {
                    queue.async {
                        reject.call(withArguments: ["ws send: missing bytesBase64"])
                        context.evaluateScript("void(0)")
                    }
                    return
                }
                session.send(binary: bytes)
            case "text":
                let text = (frame["text"] as? String) ?? ""
                session.send(text: text)
            default:
                queue.async {
                    reject.call(withArguments: ["ws send: unknown frame type \(type)"])
                    context.evaluateScript("void(0)")
                }
                return
            }

            queue.async {
                resolve.call(withArguments: [])
                context.evaluateScript("void(0)")
            }
        }

        let closeBlock: @convention(block) (String, String, JSValue, JSValue) -> Void = { sessionId, optionsJSON, resolve, reject in
            nonisolated(unsafe) let resolve = resolve
            nonisolated(unsafe) let reject = reject

            guard let session = HostWebSocketRegistry.remove(sessionId) else {
                // 已不在注册表也算成功(幂等)。
                queue.async {
                    resolve.call(withArguments: [])
                    context.evaluateScript("void(0)")
                }
                _ = reject  // suppress unused
                return
            }

            let data = optionsJSON.data(using: .utf8) ?? Data()
            let options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let code = UInt16((options["code"] as? Int) ?? 1000)
            let reason = options["reason"] as? String

            session.close(code: code, reason: reason)
            session.tearDown()
            queue.async {
                resolve.call(withArguments: [])
                context.evaluateScript("void(0)")
            }
        }

        context.setObject(openBlock, forKeyedSubscript: "__lp_host_ws_open" as NSString)
        context.setObject(sendBlock, forKeyedSubscript: "__lp_host_ws_send" as NSString)
        context.setObject(closeBlock, forKeyedSubscript: "__lp_host_ws_close" as NSString)
    }
}
