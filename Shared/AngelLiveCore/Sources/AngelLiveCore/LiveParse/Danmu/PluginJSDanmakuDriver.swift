import Foundation

/// 无可变状态:全部存储属性均为 `let` 且类型 `Sendable`,方法只是把调用透传给插件运行时。
/// 故本类天然 `Sendable`,可安全跨隔离域捕获(连接层的 `Task { [pluginDriver] ... }` 依赖这一点)。
final class PluginJSDanmakuDriver: Sendable {
    enum TickReason: String {
        case heartbeat
        case polling
    }

    enum DestroyReason: String {
        case disconnect
        case fallback
        case deinitialized = "deinit"
        case error
        case reconnect
    }

    enum IncomingFrameType: String {
        case text
        case binary
        case httpResponse = "http_response"
    }

    let pluginId: String
    let roomId: String
    let userId: String?
    let plan: LiveParseDanmakuPlan
    let connectionId: String

    init(pluginId: String, roomId: String, userId: String?, plan: LiveParseDanmakuPlan) {
        self.pluginId = pluginId
        self.roomId = roomId
        self.userId = userId
        self.plan = plan
        self.connectionId = UUID().uuidString
    }

    func createSession() async throws -> LiveParseDanmakuDriverResult {
        var payload: [String: Any] = [
            "connectionId": connectionId,
            "roomId": roomId,
            "args": plan.args
        ]
        if let userId {
            payload["userId"] = userId
        }
        if let headers = plan.headers {
            payload["headers"] = headers
        }
        if let platformSession = LiveParsePlatformSessionVault.session(for: pluginId) {
            if !platformSession.cookie.isEmpty {
                // Plugins can request native Host.http / Host.ws credential
                // injection, but never receive the Cookie bytes themselves.
                payload["credentialAvailable"] = true
            }
            if let uid = platformSession.uid, !uid.isEmpty {
                payload["uid"] = uid
            }
        }
        if let transport = plan.transport?.dictionaryValue() {
            payload["transport"] = transport
        }
        return try await call("createDanmakuSession", payload: payload)
    }

    func onOpen() async throws -> LiveParseDanmakuDriverResult {
        try await call(
            "onDanmakuOpen",
            payload: [
                "connectionId": connectionId
            ]
        )
    }

    func onTick(reason: TickReason) async throws -> LiveParseDanmakuDriverResult {
        try await call(
            "onDanmakuTick",
            payload: [
                "connectionId": connectionId,
                "reason": reason.rawValue
            ]
        )
    }

    func onFrame(
        frameType: IncomingFrameType,
        text: String? = nil,
        data: Data? = nil,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil
    ) async throws -> LiveParseDanmakuDriverResult {
        var payload: [String: Any] = [
            "connectionId": connectionId,
            "frameType": frameType.rawValue
        ]
        if let text {
            payload["text"] = text
        }
        if let data {
            payload["bytesBase64"] = data.base64EncodedString()
        }
        if let statusCode {
            payload["statusCode"] = statusCode
        }
        if let responseHeaders {
            payload["responseHeaders"] = responseHeaders
        }
        return try await call("onDanmakuFrame", payload: payload)
    }

    func destroy(reason: DestroyReason) async {
        do {
            let _: LiveParseDanmakuDriverResult = try await call(
                "destroyDanmakuSession",
                payload: [
                    "connectionId": connectionId,
                    "reason": reason.rawValue
                ]
            )
        } catch {
            Logger.warning("[PluginJSDanmakuDriver] destroy failed pluginId=\(pluginId) connectionId=\(connectionId) error=\(error)", category: .danmu)
        }
    }

    private func call(_ function: String, payload: [String: Any]) async throws -> LiveParseDanmakuDriverResult {
        try await LiveParsePlugins.shared.callDecodable(
            pluginId: pluginId,
            function: function,
            payload: payload
        )
    }
}
