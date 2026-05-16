import Foundation
@preconcurrency import JavaScriptCore

public final class JSRuntime: @unchecked Sendable {
    public typealias LogHandler = @Sendable (String) -> Void

    public static let supportedAPIVersion = 1

    private let queue: DispatchQueue
    private let context: JSContext
    private let pluginId: String
    private let session: URLSession
    private let nativeStream: ManifestNativeStream?

    public init(
        pluginId: String,
        session: URLSession = .shared,
        nativeStream: ManifestNativeStream? = nil,
        logHandler: LogHandler? = nil
    ) {
        self.queue = DispatchQueue(label: "liveparse.jsruntime.\(UUID().uuidString)")
        self.pluginId = pluginId
        self.session = session
        self.nativeStream = nativeStream

        var createdContext: JSContext?
        queue.sync {
            createdContext = JSContext()
        }
        self.context = createdContext!

        queue.sync {
            Self.configureConsole(in: context, logHandler: logHandler)
            Self.configureExceptionHandler(in: context)
            Self.configureHostHTTP(in: context, queue: queue, session: session, pluginId: pluginId)
            Self.configureHostCrypto(in: context)
            Self.configureHostSession(in: context)
            Self.configureHostRuntime(in: context)
            Self.configureHostBootstrap(in: context)
            Self.configureHostNativeStream(in: context, queue: queue, nativeStream: nativeStream)
            Self.configureHostWebSocket(in: context, queue: queue, pluginId: pluginId)
        }
    }

    public func evaluate(script: String, sourceURL: URL? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if let sourceURL {
                    self.context.evaluateScript(script, withSourceURL: sourceURL)
                } else {
                    self.context.evaluateScript(script)
                }
                if let exception = self.context.exception {
                    continuation.resume(throwing: LiveParsePluginError.fromJSException(exception.toString() ?? "<unknown>"))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    public func evaluate(contentsOf url: URL) async throws {
        let script = try String(contentsOf: url, encoding: .utf8)
        try await evaluate(script: script, sourceURL: url)
    }

    public func pluginAPIVersion() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let pluginObject = self.context.objectForKeyedSubscript("LiveParsePlugin") else {
                        throw LiveParsePluginError.invalidReturnValue("Missing globalThis.LiveParsePlugin")
                    }
                    let apiVersionValue = pluginObject.forProperty("apiVersion")
                    let apiVersion = apiVersionValue?.toInt32() ?? 0
                    continuation.resume(returning: Int(apiVersion))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func callPluginFunction(name: String, payload: [String: Any] = [:]) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    print("[JSRuntime:\(self.pluginId)] callPluginFunction(\(name)) 进入队列")
                    guard let pluginObject = self.context.objectForKeyedSubscript("LiveParsePlugin") else {
                        throw LiveParsePluginError.invalidReturnValue("Missing globalThis.LiveParsePlugin")
                    }
                    guard let fn = pluginObject.objectForKeyedSubscript(name), fn.isObject else {
                        throw LiveParsePluginError.invalidReturnValue("Missing function: \(name)")
                    }

                    let jsPayload = JSValue(object: payload, in: self.context) as Any
                    guard let result = pluginObject.invokeMethod(name, withArguments: [jsPayload]) else {
                        if let exception = self.context.exception {
                            throw LiveParsePluginError.fromJSException(exception.toString() ?? "<unknown>")
                        }
                        throw LiveParsePluginError.invalidReturnValue("Function returned nil")
                    }

                    if Self.isPromise(result) {
                        print("[JSRuntime:\(self.pluginId)] callPluginFunction(\(name)) 返回 Promise，等待解析")
                        self.awaitPromise(result, functionName: name, continuation: continuation)
                        return
                    }

                    print("[JSRuntime:\(self.pluginId)] callPluginFunction(\(name)) 同步返回")
                    continuation.resume(returning: try Self.convertToJSONObject(result, in: self.context))
                } catch {
                    print("[JSRuntime:\(self.pluginId)] callPluginFunction(\(name)) 异常: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension JSRuntime {
    static func configureConsole(in context: JSContext, logHandler: LogHandler?) {
        let console = JSValue(newObjectIn: context)
        let log: @convention(block) (JSValue) -> Void = { [logHandler] value in
            logHandler?(value.toString() ?? "")
        }
        console?.setObject(log, forKeyedSubscript: "log" as NSString)
        console?.setObject(log, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    static func configureExceptionHandler(in context: JSContext) {
        context.exceptionHandler = { _, exception in
            _ = exception
        }
    }

    static func configureHostBootstrap(in context: JSContext) {
        // 给插件提供一个稳定的 Host API 表层（底层由 __lp_* 提供）。
        let script = """
        (function () {
          // 提供最小浏览器环境 shim，供依赖 window/document/navigator 的第三方脚本使用
          if (typeof globalThis.document === "undefined") globalThis.document = {};
          if (typeof globalThis.window === "undefined") globalThis.window = {};
          if (typeof globalThis.navigator === "undefined") globalThis.navigator = {};
          if (!globalThis.navigator.userAgent) {
            globalThis.navigator.userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";
          }

          // JavaScriptCore 默认没有浏览器环境里的 btoa/atob，弹幕插件会用它处理二进制帧。
          var __lpBase64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
          if (typeof globalThis.btoa !== "function") {
            globalThis.btoa = function (input) {
              var source = String(input || "");
              var output = "";
              for (var i = 0; i < source.length; i += 3) {
                var byte1 = source.charCodeAt(i);
                var byte2 = i + 1 < source.length ? source.charCodeAt(i + 1) : NaN;
                var byte3 = i + 2 < source.length ? source.charCodeAt(i + 2) : NaN;

                if (byte1 > 0xff || (!isNaN(byte2) && byte2 > 0xff) || (!isNaN(byte3) && byte3 > 0xff)) {
                  throw new Error("InvalidCharacterError");
                }

                var chunk = (byte1 << 16) | ((isNaN(byte2) ? 0 : byte2) << 8) | (isNaN(byte3) ? 0 : byte3);
                output += __lpBase64Alphabet.charAt((chunk >> 18) & 63);
                output += __lpBase64Alphabet.charAt((chunk >> 12) & 63);
                output += isNaN(byte2) ? "=" : __lpBase64Alphabet.charAt((chunk >> 6) & 63);
                output += isNaN(byte3) ? "=" : __lpBase64Alphabet.charAt(chunk & 63);
              }
              return output;
            };
          }
          if (typeof globalThis.atob !== "function") {
            globalThis.atob = function (input) {
              var source = String(input || "").replace(/[\\t\\n\\f\\r ]+/g, "");
              if (source.length % 4 === 1) {
                throw new Error("InvalidCharacterError");
              }
              var output = "";
              for (var i = 0; i < source.length; i += 4) {
                var enc1 = source.charAt(i);
                var enc2 = source.charAt(i + 1);
                var enc3 = source.charAt(i + 2);
                var enc4 = source.charAt(i + 3);
                var idx1 = __lpBase64Alphabet.indexOf(enc1);
                var idx2 = __lpBase64Alphabet.indexOf(enc2);
                var idx3 = enc3 === "=" ? 0 : __lpBase64Alphabet.indexOf(enc3);
                var idx4 = enc4 === "=" ? 0 : __lpBase64Alphabet.indexOf(enc4);

                if (idx1 < 0 || idx2 < 0 || (enc3 !== "=" && idx3 < 0) || (enc4 !== "=" && idx4 < 0)) {
                  throw new Error("InvalidCharacterError");
                }

                var chunk = (idx1 << 18) | (idx2 << 12) | (idx3 << 6) | idx4;
                output += String.fromCharCode((chunk >> 16) & 0xff);
                if (enc3 !== "=") output += String.fromCharCode((chunk >> 8) & 0xff);
                if (enc4 !== "=") output += String.fromCharCode(chunk & 0xff);
              }
              return output;
            };
          }

          globalThis.Host = globalThis.Host || {};
          Host.makeError = function (code, message, context) {
            var normalizedContext = {};
            if (context && typeof context === "object" && !Array.isArray(context)) {
              Object.keys(context).forEach(function (key) {
                var value = context[key];
                if (value === undefined || value === null) return;
                normalizedContext[String(key)] = String(value);
              });
            }
            var payload = {
              code: String(code || "UNKNOWN"),
              message: String(message || ""),
              context: normalizedContext
            };
            return new Error("LP_PLUGIN_ERROR:" + JSON.stringify(payload));
          };
          Host.raise = function (code, message, context) {
            throw Host.makeError(code, message, context);
          };

          Host.http = Host.http || {};
          Host.http.request = function (options) {
            var url = (options && options.url) || (options && options.request && options.request.url) || "";
            console.log("[Host.http.request] 发起请求: " + url);
            return new Promise(function (resolve, reject) {
              __lp_host_http_request(
                JSON.stringify(options || {}),
                function (resultJSON) {
                  console.log("[Host.http.request] resolve 回调触发: " + url);
                  resolve(JSON.parse(resultJSON));
                },
                function (err) {
                  console.log("[Host.http.request] reject 回调触发: " + url + " err=" + err);
                  reject(Host.makeError("NETWORK", String(err || "host http request failed"), { url: url }));
                }
              );
            });
          };

          Host.crypto = Host.crypto || {};
          Host.crypto.md5 = function (input) {
            return __lp_crypto_md5(String(input));
          };
          Host.crypto.base64Decode = function (input) {
            return __lp_crypto_base64_decode(String(input));
          };

          Host.session = Host.session || {};
          Host.session.getCookieHeader = function (platformId) {
            return __lp_host_session_get_cookie_header(String(platformId || ""));
          };

          Host.runtime = Host.runtime || {};
          Host.runtime.loadBuiltinScript = function (name) {
            return !!__lp_host_load_builtin_script(String(name || ""));
          };

          Host.nativeStream = Host.nativeStream || {};
          Host.nativeStream.resolve = function (options) {
            var request = options && typeof options === "object" ? options : {};
            return new Promise(function (resolve, reject) {
              __lp_host_native_stream_resolve(
                JSON.stringify(request),
                function (resultJSON) {
                  try {
                    resolve(JSON.parse(resultJSON || "{}"));
                  } catch (err) {
                    reject(Host.makeError("PARSE", String(err || "native stream parse failed"), {}));
                  }
                },
                function (err) {
                  reject(Host.makeError("UPSTREAM", String(err || "native stream request failed"), {
                    provider: request.provider || request.providerId || request.platformId || ""
                  }));
                }
              );
            });
          };

          Host.stream = Host.stream || {};
          Host.stream.resolve = Host.nativeStream.resolve;
          Host.stream.getInfo = Host.nativeStream.resolve;

          // 通用 WebSocket 桥:平台特定协议(TARS / 心跳 / 鉴权)全部在 plugin JS 里实现,
          // 宿主只搬字节,对协议零知识。
          Host.ws = Host.ws || {};
          Host.ws.open = function (options) {
            return new Promise(function (resolve, reject) {
              var pending = [];
              var handler = null;
              var bridgeHandler = function (eventJSON) {
                var event;
                try { event = JSON.parse(eventJSON); }
                catch (e) { event = { type: "error", message: String(e) }; }
                if (handler) {
                  try { handler(event); }
                  catch (err) { /* 用户回调异常不影响传输层 */ }
                } else {
                  pending.push(event);
                }
              };

              var sessionId;
              try {
                sessionId = String(__lp_host_ws_open(JSON.stringify(options || {}), bridgeHandler) || "");
              } catch (err) {
                reject(Host.makeError("WS_OPEN", String(err && err.message ? err.message : err), {}));
                return;
              }
              if (!sessionId) {
                reject(Host.makeError("WS_OPEN", "ws open failed: invalid options", {}));
                return;
              }

              var session = {
                sessionId: sessionId,
                onMessage: function (cb) {
                  handler = (typeof cb === "function") ? cb : null;
                  if (handler) {
                    while (pending.length) {
                      var ev = pending.shift();
                      try { handler(ev); } catch (e) { /* swallow */ }
                    }
                  }
                },
                send: function (frame) {
                  return new Promise(function (res, rej) {
                    __lp_host_ws_send(sessionId, JSON.stringify(frame || {}),
                      function () { res(); },
                      function (err) { rej(Host.makeError("WS_SEND", String(err || "ws send failed"), { sessionId: sessionId })); }
                    );
                  });
                },
                close: function (opts) {
                  return new Promise(function (res, rej) {
                    __lp_host_ws_close(sessionId, JSON.stringify(opts || {}),
                      function () { handler = null; pending.length = 0; res(); },
                      function (err) { rej(Host.makeError("WS_CLOSE", String(err || "ws close failed"), { sessionId: sessionId })); }
                    );
                  });
                }
              };
              resolve(session);
            });
          };

        })();
        """
        context.evaluateScript(script)
    }

    static func configureHostRuntime(in context: JSContext) {
        let loadBuiltinScript: @convention(block) (String) -> Bool = { scriptName in
            let raw = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return false }

            let fileName = (raw as NSString).deletingPathExtension
            let ext = (raw as NSString).pathExtension.isEmpty ? "js" : (raw as NSString).pathExtension
            guard let url = Bundle.main.url(forResource: fileName, withExtension: ext) else {
                return false
            }
            guard let script = try? String(contentsOf: url, encoding: .utf8) else {
                return false
            }

            context.evaluateScript(script, withSourceURL: url)
            return context.exception == nil
        }
        context.setObject(loadBuiltinScript, forKeyedSubscript: "__lp_host_load_builtin_script" as NSString)
    }

    static func configureHostHTTP(in context: JSContext, queue: DispatchQueue, session: URLSession, pluginId: String) {
        let requestBlock: @convention(block) (String, JSValue, JSValue) -> Void = { optionsJSON, resolve, reject in
            let optionsData = optionsJSON.data(using: .utf8) ?? Data()
            let options = (try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any]) ?? [:]

            guard let envelope = makeHostHTTPRequestEnvelope(options: options, pluginId: pluginId) else {
                reject.call(withArguments: ["Invalid url"]) // already on JS thread
                return
            }

            var request = URLRequest(url: envelope.url)
            request.httpMethod = envelope.method
            request.timeoutInterval = envelope.timeout

            var requestHeaders = envelope.headers
            if envelope.authMode == .platformCookie {
                requestHeaders = removeProtectedHeaders(requestHeaders)
                if let cookieHeader = LiveParsePlatformSessionVault.mergedCookieHeader(for: envelope.platformId) {
                    requestHeaders["Cookie"] = cookieHeader
                }
            }

            var requestBody = envelope.body

            // 通用 cookieInject：从 cookie 取值注入到 header、query 或 body
            if !envelope.cookieInject.isEmpty {
                var mutableURL = envelope.urlString
                var bodyJSON: [String: Any]?

                for rule in envelope.cookieInject {
                    guard let value = LiveParsePlatformSessionVault.cookieValue(named: rule.cookieName, for: envelope.platformId),
                          !value.isEmpty else { continue }
                    let injectedValue = (rule.prefix ?? "") + value

                    switch rule.target {
                    case .header:
                        guard let headerName = rule.headerName else { continue }
                        requestHeaders[headerName] = injectedValue
                    case .query:
                        guard let queryName = rule.queryName else { continue }
                        var components = URLComponents(string: mutableURL)
                        var queryItems = components?.queryItems ?? []
                        queryItems.removeAll { $0.name == queryName }
                        queryItems.append(URLQueryItem(name: queryName, value: injectedValue))
                        components?.queryItems = queryItems
                        mutableURL = components?.string ?? mutableURL
                    case .body:
                        guard let bodyPath = rule.bodyPath else { continue }
                        if bodyJSON == nil {
                            if let existing = requestBody,
                               let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
                                bodyJSON = parsed
                            } else {
                                bodyJSON = [:]
                            }
                        }
                        let keyPath = bodyPath.split(separator: ".").map(String.init)
                        bodyJSON = Self.setNestedValue(in: bodyJSON ?? [:], keyPath: keyPath, value: injectedValue)
                    }
                }

                if mutableURL != envelope.urlString, let newURL = URL(string: mutableURL) {
                    request.url = newURL
                }
                if let bodyJSON {
                    // Keep cookieInject body changes as the final request body.
                    // Previously this was overwritten by envelope.body below.
                    requestBody = try? JSONSerialization.data(withJSONObject: bodyJSON)
                }
            }

            for (key, value) in requestHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }

            request.httpBody = requestBody

            // 开发者控制台：记录请求开始时间
            let httpStartTime = CFAbsoluteTimeGetCurrent()

            let task = session.dataTask(with: request) { data, response, error in
                queue.async { [weak context] in
                    guard let context else { return }

                    let httpElapsed = CFAbsoluteTimeGetCurrent() - httpStartTime

                    if let error {
                        // 开发者控制台：记录失败的 HTTP 请求
                        Self.logHTTPRecord(
                            pluginId: pluginId, envelope: envelope,
                            requestHeaders: requestHeaders,
                            statusCode: nil, responseHeaders: nil,
                            responseBody: nil, error: error.localizedDescription,
                            duration: httpElapsed
                        )
                        reject.call(withArguments: [error.localizedDescription])
                        context.evaluateScript("void(0)")
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        Self.logHTTPRecord(
                            pluginId: pluginId, envelope: envelope,
                            requestHeaders: requestHeaders,
                            statusCode: nil, responseHeaders: nil,
                            responseBody: nil, error: "Invalid response",
                            duration: httpElapsed
                        )
                        reject.call(withArguments: ["Invalid response"])
                        context.evaluateScript("void(0)")
                        return
                    }

                    var headersDict: [String: String] = http.allHeaderFields.reduce(into: [:]) { acc, item in
                        if let k = item.key as? String {
                            acc[k] = String(describing: item.value)
                        }
                    }
                    // httpCookieAcceptPolicy=.never 会导致 allHeaderFields 过滤 Set-Cookie，
                    // 但部分 JS 插件需要读取它，因此单独补回。
                    if envelope.authMode != .platformCookie,
                       headersDict["Set-Cookie"] == nil,
                       let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
                        headersDict["Set-Cookie"] = setCookie
                    }
                    if envelope.authMode == .platformCookie {
                        headersDict = removeSetCookieHeaders(headersDict)
                    }

                    let bodyText = data.flatMap { String(data: $0, encoding: .utf8) }
                    let bodyBase64 = data?.base64EncodedString()
                    let responseURL = http.url?.absoluteString ?? envelope.urlString
                    let rawBodyLog = debugHTTPResponseBody(bodyText: bodyText, bodyBase64: bodyBase64)
                    print("[JSRuntime][HTTP] pluginId=\(pluginId) method=\(envelope.method) status=\(http.statusCode) url=\(responseURL) headers=\(headersDict) rawBody=\(rawBodyLog)")

                    // 开发者控制台：记录成功的 HTTP 请求
                    Self.logHTTPRecord(
                        pluginId: pluginId, envelope: envelope,
                        requestHeaders: requestHeaders,
                        statusCode: http.statusCode, responseHeaders: headersDict,
                        responseBody: bodyText.map { String($0.prefix(2000)) },
                        error: nil, duration: httpElapsed
                    )

                    let result: [String: Any] = [
                        "status": http.statusCode,
                        "headers": headersDict,
                        "url": responseURL,
                        "bodyText": bodyText ?? NSNull(),
                        "bodyBase64": bodyBase64 ?? NSNull()
                    ]

                    let jsonData = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                    resolve.call(withArguments: [jsonString])
                    context.evaluateScript("void(0)")
                }
            }
            task.resume()
        }

        context.setObject(requestBlock, forKeyedSubscript: "__lp_host_http_request" as NSString)
    }

    private enum HostHTTPAuthMode: String {
        case none
        case platformCookie = "platform_cookie"
    }

    /// 通用 cookie 值注入规则：从 cookie 取值注入到 header、query 或 JSON body
    private struct CookieInjectRule {
        enum Target: String { case header, query, body }
        let cookieName: String
        let target: Target
        /// header name（target=header）
        let headerName: String?
        /// query parameter name（target=query）
        let queryName: String?
        /// JSON body key path，如 "data.token" → {"data":{"token":"xxx"}}（target=body）
        let bodyPath: String?
        /// 值前缀，如 "OAuth "
        let prefix: String?
    }

    private struct HostHTTPRequestEnvelope {
        let url: URL
        let urlString: String
        let method: String
        let headers: [String: String]
        let body: Data?
        let timeout: TimeInterval
        let authMode: HostHTTPAuthMode
        let platformId: String
        let cookieInject: [CookieInjectRule]
    }

    private static func makeHostHTTPRequestEnvelope(options: [String: Any], pluginId: String) -> HostHTTPRequestEnvelope? {
        let request = (options["request"] as? [String: Any]) ?? options
        guard let urlString = (request["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }

        let method = (request["method"] as? String)?.uppercased() ?? "GET"
        var headers = normalizedHeaders(request["headers"])

        let timeout = resolveTimeout(request: request, options: options)
        let body = resolveBody(request: request)

        let authRaw = ((options["authMode"] as? String) ?? "none").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let authMode = HostHTTPAuthMode(rawValue: authRaw) ?? .none
        let platformId = LiveParsePlatformSessionVault.canonicalPlatformId(
            ((options["platformId"] as? String) ?? pluginId)
        )

        if authMode == .platformCookie {
            headers = removeProtectedHeaders(headers)
        }

        return HostHTTPRequestEnvelope(
            url: url,
            urlString: urlString,
            method: method,
            headers: headers,
            body: body,
            timeout: timeout,
            authMode: authMode,
            platformId: platformId,
            cookieInject: resolveCookieInject(options: options)
        )
    }

    private static func resolveCookieInject(options: [String: Any]) -> [CookieInjectRule] {
        guard let rawArray = options["cookieInject"] as? [[String: Any]] else { return [] }
        var rules: [CookieInjectRule] = []
        for item in rawArray {
            guard let cookieName = (item["cookieName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cookieName.isEmpty else { continue }
            let targetRaw = (item["target"] as? String)?.lowercased() ?? "header"
            let target = CookieInjectRule.Target(rawValue: targetRaw) ?? .header
            let headerName = (item["headerName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryName = (item["queryName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyPath = (item["bodyPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = item["prefix"] as? String

            // 校验对应 target 的必填字段
            switch target {
            case .header: guard headerName != nil && !headerName!.isEmpty else { continue }
            case .query:  guard queryName != nil && !queryName!.isEmpty else { continue }
            case .body:   guard bodyPath != nil && !bodyPath!.isEmpty else { continue }
            }

            rules.append(CookieInjectRule(
                cookieName: cookieName,
                target: target,
                headerName: headerName,
                queryName: queryName,
                bodyPath: bodyPath,
                prefix: prefix
            ))
        }
        return rules
    }

    private static func resolveTimeout(request: [String: Any], options: [String: Any]) -> TimeInterval {
        func seconds(from any: Any?) -> TimeInterval? {
            if let value = any as? Double { return value }
            if let value = any as? NSNumber { return value.doubleValue }
            if let value = any as? String, let doubleValue = Double(value) { return doubleValue }
            return nil
        }

        func milliseconds(from any: Any?) -> TimeInterval? {
            guard let millis = seconds(from: any), millis > 0 else { return nil }
            return millis / 1000.0
        }

        if let timeoutMs = milliseconds(from: request["timeoutMs"]) {
            return timeoutMs
        }
        if let timeout = seconds(from: request["timeout"]) {
            return timeout
        }
        if let timeoutMs = milliseconds(from: options["timeoutMs"]) {
            return timeoutMs
        }
        if let timeout = seconds(from: options["timeout"]) {
            return timeout
        }
        return 20
    }

    private static func resolveBody(request: [String: Any]) -> Data? {
        if let bodyBase64 = request["bodyBase64"] as? String,
           let bodyData = Data(base64Encoded: bodyBase64) {
            return bodyData
        }
        if let body = request["body"] as? String {
            return body.data(using: .utf8)
        }
        return nil
    }

    private static func debugHTTPResponseBody(bodyText: String?, bodyBase64: String?) -> String {
        let limit = 4_000
        if let bodyText, !bodyText.isEmpty {
            if bodyText.count > limit {
                return String(bodyText.prefix(limit)) + "...(truncated)"
            }
            return bodyText
        }
        if let bodyBase64, !bodyBase64.isEmpty {
            if bodyBase64.count > limit {
                return "<base64> " + String(bodyBase64.prefix(limit)) + "...(truncated)"
            }
            return "<base64> \(bodyBase64)"
        }
        return "<empty>"
    }

    private static func normalizedHeaders(_ raw: Any?) -> [String: String] {
        guard let headers = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in headers {
            if let stringValue = value as? String {
                result[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                result[key] = numberValue.stringValue
            }
        }
        return result
    }

    /// 将 HTTP 请求/响应记录到开发者控制台
    private static func logHTTPRecord(
        pluginId: String,
        envelope: HostHTTPRequestEnvelope,
        requestHeaders: [String: String],
        statusCode: Int?,
        responseHeaders: [String: String]?,
        responseBody: String?,
        error: String?,
        duration: TimeInterval
    ) {
        let console = PluginConsoleService.shared
        guard console.isEnabled,
              let entryId = console.activeEntryId(for: pluginId) else { return }

        let bodyStr: String? = envelope.body.flatMap { String(data: $0, encoding: .utf8) }

        let record = PluginConsoleHTTPRecord(
            url: envelope.urlString,
            method: envelope.method,
            headers: requestHeaders,
            body: bodyStr,
            statusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            error: error,
            duration: duration
        )

        Task { @MainActor in
            console.appendHTTPRecord(entryId: entryId, record: record)
        }
    }

    /// 按 key path 设置嵌套字典值，如 ["data","token"] → {"data":{"token":"xxx"}}
    private static func setNestedValue(in dict: [String: Any], keyPath: [String], value: Any) -> [String: Any] {
        guard let first = keyPath.first else { return dict }
        var result = dict
        if keyPath.count == 1 {
            result[first] = value
        } else {
            let nested = (result[first] as? [String: Any]) ?? [:]
            result[first] = setNestedValue(in: nested, keyPath: Array(keyPath.dropFirst()), value: value)
        }
        return result
    }

    private static func removeProtectedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.filter { key, _ in
            let lowered = key.lowercased()
            return lowered != "cookie" && lowered != "authorization"
        }
    }

    private static func removeSetCookieHeaders(_ headers: [String: String]) -> [String: String] {
        headers.filter { key, _ in
            key.lowercased() != "set-cookie"
        }
    }

    static func configureHostCrypto(in context: JSContext) {
        let md5Block: @convention(block) (String) -> String = { input in
            input.md5
        }
        let base64DecodeBlock: @convention(block) (String) -> String = { input in
            guard let decoded = input.removingPercentEncoding,
                  let data = Data(base64Encoded: decoded),
                  let str = String(data: data, encoding: .utf8)
            else {
                return ""
            }
            return str
        }
        context.setObject(md5Block, forKeyedSubscript: "__lp_crypto_md5" as NSString)
        context.setObject(base64DecodeBlock, forKeyedSubscript: "__lp_crypto_base64_decode" as NSString)
    }

    static func configureHostSession(in context: JSContext) {
        let getCookieHeaderBlock: @convention(block) (String) -> String = { platformId in
            let trimmed = platformId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return LiveParsePlatformSessionVault.mergedCookieHeader(for: trimmed) ?? ""
        }
        context.setObject(getCookieHeaderBlock, forKeyedSubscript: "__lp_host_session_get_cookie_header" as NSString)
    }

    static func isPromise(_ value: JSValue) -> Bool {
        guard value.isObject else { return false }
        let then = value.forProperty("then")
        return then?.isObject == true
    }

    func awaitPromise(_ promise: JSValue, functionName: String = "", continuation: CheckedContinuation<Any, Error>) {
        let pluginId = self.pluginId
        let context = self.context

        // 用唯一 key 将 promise 和回调注册到 JS 全局空间，
        // 然后通过 evaluateScript 执行 .then()，确保回调在 JS 引擎内部被调度。
        let key = "_lp_await_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        let resolve: @convention(block) (JSValue) -> Void = { [weak context] value in
            print("[JSRuntime:\(pluginId)] awaitPromise(\(functionName)) resolve 回调触发")
            // 清理全局变量
            context?.evaluateScript("delete globalThis.\(key); delete globalThis.\(key)_r; delete globalThis.\(key)_j;")
            do {
                let converted = try Self.convertToJSONObject(value, in: context!)
                continuation.resume(returning: converted)
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let reject: @convention(block) (JSValue) -> Void = { [weak context] value in
            print("[JSRuntime:\(pluginId)] awaitPromise(\(functionName)) reject 回调触发: \(value.toString() ?? "")")
            context?.evaluateScript("delete globalThis.\(key); delete globalThis.\(key)_r; delete globalThis.\(key)_j;")
            continuation.resume(throwing: LiveParsePluginError.fromJSException(value.toString() ?? "<unknown>"))
        }

        // 将 promise 和回调注册到 JS 全局空间
        context.setObject(promise, forKeyedSubscript: key as NSString)
        context.setObject(resolve, forKeyedSubscript: "\(key)_r" as NSString)
        context.setObject(reject, forKeyedSubscript: "\(key)_j" as NSString)

        // 通过 evaluateScript 执行 .then()，这样回调会在 JS 引擎的正常执行流中被调度
        context.evaluateScript("globalThis.\(key).then(globalThis.\(key)_r, globalThis.\(key)_j);")
    }

    static func convertToJSONObject(_ value: JSValue, in context: JSContext) throws -> Any {
        if value.isUndefined || value.isNull {
            return NSNull()
        }

        let json = context.objectForKeyedSubscript("JSON")
        guard let jsonStringValue = json?.invokeMethod("stringify", withArguments: [value]),
              let jsonString = jsonStringValue.toString()
        else {
            throw LiveParsePluginError.invalidReturnValue("JSON.stringify failed")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw LiveParsePluginError.invalidReturnValue("Invalid UTF-8 JSON")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Native Stream Bridge

    static func configureHostNativeStream(in context: JSContext, queue: DispatchQueue, nativeStream: ManifestNativeStream?) {
        let resolveNativeStream: @convention(block) (String, JSValue, JSValue) -> Void = { optionsJSON, resolve, reject in
            nonisolated(unsafe) let resolve = resolve
            nonisolated(unsafe) let reject = reject
            let data = optionsJSON.data(using: .utf8) ?? Data()
            let options = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            Task {
                do {
                    let streamInfo = try await NativeStreamBridge.resolve(
                        options: options,
                        declaration: nativeStream
                    )

                    queue.async {
                        do {
                            let jsonString = try Self.jsonString(from: streamInfo)
                            resolve.call(withArguments: [jsonString])
                            context.evaluateScript("void(0)")
                        } catch {
                            reject.call(withArguments: ["Native stream serialize failed: \(error.localizedDescription)"])
                            context.evaluateScript("void(0)")
                        }
                    }
                } catch {
                    queue.async {
                        reject.call(withArguments: [error.localizedDescription])
                        context.evaluateScript("void(0)")
                    }
                }
            }
        }

        context.setObject(resolveNativeStream, forKeyedSubscript: "__lp_host_native_stream_resolve" as NSString)
    }

    static func jsonString(from object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NSError(
                domain: "LiveParse.JSRuntime",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "object is not JSON serializable"]
            )
        }
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}
