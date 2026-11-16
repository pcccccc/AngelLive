import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Plugin source friendly errors")
struct PluginSourceFriendlyErrorTests {
    @Test("response and decoding diagnostics do not leak into friendly messages")
    func privateDiagnosticsAreHidden() {
        let privateURL = "https://source.example.invalid/index?token=fixture-secret"
        let privateBody = "fixture-response-secret"
        let privateDebug = "fixture-debug-secret"
        let diagnostics = LiveParsePluginIndexResponseDiagnostics(
            url: URL(string: privateURL)!, statusCode: 200,
            contentType: "text/html", bodyPreview: privateBody
        )
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: privateDebug))
        let errors: [Error] = [
            LiveParsePluginIndexFetchError.nonJSONResponse(diagnostics),
            LiveParsePluginIndexFetchError.decodingFailed(diagnostics, decoding),
            decoding
        ]
        for (index, error) in errors.enumerated() {
            let message = PluginSourceManager.friendlySourceErrorDescription(error)
            #expect(!message.contains(privateURL))
            #expect(!message.contains(privateBody))
            #expect(!message.contains(privateDebug))
            #expect(message.contains(index == 0 ? "不是有效的订阅数据" : "格式不正确"))
            #expect(message.contains("联系订阅源提供者"))
        }
    }

    @Test("network errors give a reason and action", arguments: [
        (URLError.Code.timedOut, "超时", "网络"),
        (.notConnectedToInternet, "网络不可用", "检查网络"),
        (.cannotFindHost, "无法找到", "检查地址"),
        (.dnsLookupFailed, "无法找到", "检查地址"),
        (.cannotConnectToHost, "无法连接", "检查网络"),
        (.secureConnectionFailed, "安全连接", "证书"),
        (.unknown, "无法连接", "检查网络")
    ])
    func networkError(code: URLError.Code, reason: String, action: String) {
        let error = URLError(code, userInfo: [NSLocalizedDescriptionKey: "fixture-private-debug"])
        for value in [error as Error, error as NSError as Error] {
            let message = PluginSourceManager.friendlySourceErrorDescription(value)
            #expect(message.contains(reason))
            #expect(message.contains(action))
            #expect(!message.contains("fixture-private-debug"))
        }
    }

    @Test("unknown errors do not expose their description")
    func unknownError() {
        let error = NSError(domain: "fixture.error", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "fixture-private-debug"
        ])
        let message = PluginSourceManager.friendlySourceErrorDescription(error)
        #expect(message.contains("无法加载订阅源"))
        #expect(message.contains("稍后重试"))
        #expect(!message.contains("fixture-private-debug"))
    }

    @Test("HTTP response retains status through URL error and bridge", arguments: [
        (401, "拒绝访问", "访问权限"), (403, "拒绝访问", "访问权限"),
        (404, "地址不可用", "检查地址"), (410, "地址不可用", "检查地址"),
        (408, "响应超时", "稍后重试"), (504, "响应超时", "稍后重试"),
        (429, "请求过于频繁", "稍后重试"),
        (500, "服务暂时不可用", "稍后重试"), (503, "服务暂时不可用", "稍后重试"),
        (418, "请求失败", "联系订阅源提供者")
    ])
    func httpStatusFromFetch(status: Int, reason: String, action: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceStatusURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let storageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try LiveParsePluginStorage(baseDirectory: storageDirectory)
        let updater = LiveParsePluginUpdater(storage: storage, session: session)
        let url = try #require(URL(string: "https://source.example.invalid/\(status)"))

        do {
            _ = try await updater.fetchIndex(url: url)
            Issue.record("Expected HTTP error for \(status)")
        } catch {
            let urlError = try #require(error as? URLError)
            #expect(urlError.code == .badServerResponse)
            #expect(urlError.localizedDescription == "HTTP \(status)")
            let bridged = error as NSError
            #expect(bridged.userInfo[LiveParsePluginUpdater.httpStatusCodeUserInfoKey] as? Int == status)
            #expect(PluginSourceManager.detailedErrorDescription(error).contains("HTTP \(status)"))
            let message = PluginSourceManager.friendlySourceErrorDescription(bridged)
            #expect(message.contains("\(status)"))
            #expect(message.contains(reason))
            #expect(message.contains(action))
            #expect(!message.contains(url.absoluteString))
        }
    }
}

private final class SourceStatusURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let status = Int(url.lastPathComponent),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
