//
//  SyncSocketManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/1.
//

import Foundation
import AngelLiveCore
import AngelLiveDependencies

nonisolated enum SimpleSyncType: CustomStringConvertible, Sendable {
    
    var description: String {
        switch self {
        case .favorite: return "收藏同步"
        case .history: return "观看历史同步"
        case .danmuBlockWords: return "弹幕屏蔽词同步"
        case .platformCredential: return "平台登录信息同步"
        }
    }
    
    case favorite
    case history
    case danmuBlockWords
    case platformCredential
}

nonisolated let httpPort = 23234
let udpPort = 23235

@MainActor
protocol SyncManagerDelegate: AnyObject {
    func syncManagerDidConnectError(error: Error)
    func syncManagerDidReceiveRequest(type: SimpleSyncType, needOverlay: Bool, rooms: [LiveModel])
}

class SyncManager {
    
    var serverChannel: Channel?
    var delegate: SyncManagerDelegate?
    
    init() {
        
        let syncSuccess: @Sendable (SimpleSyncType, Bool, [LiveModel]) -> Void = { [weak self] type, needOverlay, rooms in
            Task { @MainActor in
                self?.delegate?.syncManagerDidReceiveRequest(type: type, needOverlay: needOverlay, rooms: rooms)
            }
        }
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { @Sendable channel in
                channel.eventLoop.makeCompletedFuture {
                    let pipeline = channel.pipeline.syncOperations
                    try pipeline.configureHTTPServerPipeline()
                    try pipeline.addHandler(HTTPHandler(syncSuccess: syncSuccess))
                }
            }
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        do {
            serverChannel = try bootstrap.bind(host: Common.getWiFiIPAddress() ?? "localhost", port: httpPort).wait()
            Logger.debug("Server is running on \(serverChannel?.localAddress?.ipAddress ?? "")", category: .sync)
        } catch {
            self.delegate?.syncManagerDidConnectError(error: error)
            Logger.warning("Failed to start server: \(error)", category: .sync)
        }
        
    }
    
    func closeServer() {
        try? serverChannel?.close().wait()
    }
}


class UDPListener: NSObject, GCDAsyncUdpSocketDelegate {
    
    var udpSocket: GCDAsyncUdpSocket?
    
    override init() {
        super.init()
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do {
            try udpSocket?.bind(toPort: UInt16(udpPort)) // 绑定到任意可用端口
            try udpSocket?.beginReceiving() // 开始接收数据
        } catch {
            Logger.warning("Failed to start UDP server: \(error)", category: .sync)
        }
    }
    
    func closeServer() {
        udpSocket?.close()
    }
    
    // GCDAsyncUdpSocketDelegate 方法
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        // 处理接收到的数据
        if let message = String(data: data, encoding: .utf8) {
            Logger.debug("Received message: \(message)", category: .sync)
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["type"] as? String == "hello" {
                    let response: [String: Any] = ["id": UUID().uuidString, "type": "tv", "name": Common.hostName() ?? "Apple TV"]
                    let responseData = try JSONSerialization.data(withJSONObject: response)
                    udpSocket?.send(responseData, toAddress: address, withTimeout: 10, tag: 0)
                }
            }catch {
                
            }
        }
    }
}


// Each connection owns a handler whose request state lives on its NIO event loop.
nonisolated private final class HTTPHandler: ChannelInboundHandler {
    
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    var response: HTTPServerResponsePart?
    var responseBody: HTTPServerResponsePart?
    private var requestBody: ByteBuffer?
    var requestHeaderT: HTTPRequestHead?
    private let syncSuccess: @Sendable (SimpleSyncType, Bool, [LiveModel]) -> Void

    init(syncSuccess: @escaping @Sendable (SimpleSyncType, Bool, [LiveModel]) -> Void) {
        self.syncSuccess = syncSuccess
    }

    private func jsonString(_ dict: [String: Any]) -> String? {
        (try? JSONSerialization.data(withJSONObject: dict)).flatMap { String(data: $0, encoding: .utf8) }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        var headers = NIOHTTP1.HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        switch reqPart {
        case .head(let requestHeader):
            requestBody = nil
            requestHeaderT = requestHeader
            if requestHeader.uri == "/" {
                responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: "Hello, World!")))
                response = .head(HTTPResponseHead(version: requestHeader.version, status: .ok))
            }else if requestHeader.uri == "/info" {
                let infoDict: [String: Any] = [
                    "id": UUID().uuidString,
                    "type": "tv",
                    "name": Common.hostName() ?? "Apple TV",
                    "version": "1.2.0",
                    "address": Common.getWiFiIPAddress() ?? "127.0.0.1",
                    "port": httpPort
                ]
                let resp = (try? JSONSerialization.data(withJSONObject: infoDict)).flatMap { String(data: $0, encoding: .utf8) }
                
                responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                response = .head(HTTPResponseHead(version: requestHeader.version, status: .ok, headers: headers))
            }
        case .body(var byteBuffer):
            // 处理请求体
            if requestBody == nil {
                requestBody = byteBuffer
            } else {
                requestBody?.writeBuffer(&byteBuffer)
            }
        case .end:
            // 请求体已完全接收，处理请求
            if let body = requestBody, let bodyString = body.getString(at: 0, length: body.readableBytes) {
                Logger.debug("Request body: \(bodyString)", category: .sync)
                if requestHeaderT?.uri.contains("sync/follow") == true {
                    let resp = jsonString(["status": true, "message": "success"])
                    
                    let respList = formatDatas(bodyString: bodyString)
                    let overlay = getOverlayFormat(url: requestHeaderT?.uri ?? "")
                    syncSuccess(.favorite, overlay, respList)
                    requestBody = nil
                    
                    responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                    response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
                }
                if requestHeaderT?.uri.contains("sync/history") == true {
                    let resp = jsonString(["status": true, "message": "success"])
                    let respList = formatDatas(bodyString: bodyString)
                    let overlay = getOverlayFormat(url: requestHeaderT?.uri ?? "")
                    syncSuccess(.history, overlay, respList)
                    requestBody = nil
                    responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                    response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
                }
                if requestHeaderT?.uri.contains("blocked_word") == true {
                    let resp = jsonString(["status": false, "message": "Apple TV 端暂不支持此功能"])
                    responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                    response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
                    // 重置为下一个请求
                    requestBody = nil
                }
                if requestHeaderT?.uri.contains("account/") == true {
                    let resp = jsonString(["status": false, "message": "Apple TV 端暂不支持此功能"])
                    responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                    response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
                    // 重置为下一个请求
                    requestBody = nil
                }
//                do {
//
//                    
//                }catch {
//                    let resp = JSON([
//                        "status": false,
//                        "message": "解析数据异常",
//                    ]).rawString()
//                    responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
//                    response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
//                    // 重置为下一个请求
//                    requestBody = nil
//                }
            }
            // Create and write the response
            if response == nil {
                response = HTTPServerResponsePart.head(HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            }
            context.write(self.wrapOutboundOut(response!), promise: nil)
            if responseBody == nil {
                responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: "welcome")))
            }
            context.write(self.wrapOutboundOut(responseBody!), promise: nil)
            // 重置为下一个请求
            requestBody = nil
            let end = HTTPServerResponsePart.end(nil)
            context.writeAndFlush(self.wrapOutboundOut(end), promise: nil)
            context.close(promise: nil)
        }
    
    func formatDatas(bodyString: String) -> [LiveModel] {
        var tempArray:[LiveModel] = []
        if let data = bodyString.data(using: .utf8),
           let respFollowList = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in respFollowList {
                guard let liveType = liveType(forSiteId: item["siteId"] as? String) else { continue }
                tempArray.append(LiveModel(userName: item["userName"] as? String ?? "", roomTitle: "", roomCover: "", userHeadImg: item["face"] as? String ?? "", liveType: liveType, liveState: nil, userId: "", roomId: item["roomId"] as? String ?? "", liveWatchedCount: nil))
            }
        }
        return tempArray
    }

    func liveType(forSiteId siteId: String?) -> LiveType? {
        let normalized = siteId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return nil }
        if let platform = LiveParseJSPlatformManager.platform(forPluginId: normalized) {
            return platform.liveType
        }
        if let liveType = LiveType(rawValue: normalized),
           LiveParseJSPlatformManager.platform(for: liveType) != nil {
            return liveType
        }
        return LiveParseJSPlatformManager.availablePlatforms.first { platform in
            platform.sessionMigration?.legacyPluginIds?.contains(normalized) == true
        }?.liveType
    }
        
        func getOverlayFormat(url: String) -> Bool {
            do {
                let pattern = "\\?overlay=(\\d+)"
                let regex = try NSRegularExpression(pattern: pattern)
                let nsString = url as NSString
                let results = regex.matches(in: url, options: [], range: NSMakeRange(0, nsString.length))
                var overlay = "0"
                for result in results {
                    overlay = nsString.substring(with: result.range(at: 1))
                }
                return Int(overlay) == 1 ? true : false
            }catch {
                return false
            }
        }
    }
}
