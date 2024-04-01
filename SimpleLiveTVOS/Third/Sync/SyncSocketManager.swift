//
//  SyncSocketManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/1.
//

import Foundation
import CocoaAsyncSocket
import SwiftyJSON
import NIO
import NIOHTTP1
import LiveParse

enum SimpleSyncType {
    case favorite
    case history
    case danmuBlockWords
    case bilibiliCookie
}

class SyncManager {
    
    let httpHandler = HTTPHandler()
    
    init() {
        
        httpHandler.syncSuccess = { type, result in
            print(result)
        }
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(self.httpHandler)
                }
            }
//            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        do {
            let serverChannel = try bootstrap.bind(host: getWiFiIPAddress() ?? "localhost", port: 23234).wait()
            print("Server is running on \(serverChannel.localAddress!)")
//            try serverChannel.closeFuture.wait() // This line will block to keep the server running.
        } catch {
            fatalError("Failed to start server: \(error)")
        }
    }
}


class UDPListener: NSObject, GCDAsyncUdpSocketDelegate {
    
    var udpSocket: GCDAsyncUdpSocket?
    
    override init() {
        super.init()
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do {
            try udpSocket?.bind(toPort: 23235) // 绑定到任意可用端口
            try udpSocket?.beginReceiving() // 开始接收数据
        } catch {
            print("Failed to start UDP server: \(error)")
        }
    }
    
    
    // GCDAsyncUdpSocketDelegate 方法
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        // 处理接收到的数据
        if let message = String(data: data, encoding: .utf8) {
            print("Received message: \(message)")
            do {
                let json = try JSON(data: data)
                if json["type"] == "hello" {
//                    udpSocket?.send(try JSON(["id": UUID().uuidString, "type": "tv", "name": hostName()]).rawData(), withTimeout: 10, tag: 0)
                    udpSocket?.send(try JSON(["id": UUID().uuidString, "type": "tv", "name": hostName()]).rawData(), toAddress: address, withTimeout: 10, tag: 0)
                }
            }catch {
                
            }
        }
    }
}


final class HTTPHandler: ChannelInboundHandler {
    
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    var response: HTTPServerResponsePart?
    var responseBody: HTTPServerResponsePart?
    private var requestBody: ByteBuffer?
    var requestHeaderT: HTTPRequestHead?
    var syncSuccess: ((SimpleSyncType, Any) -> Void)?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        switch reqPart {
        case .head(let requestHeader):
            requestHeaderT = requestHeader
            if requestHeader.uri == "/" {
                responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: "Hello, World!")))
                response = .head(HTTPResponseHead(version: requestHeader.version, status: .ok))
            }else if requestHeader.uri == "/info" {
                let resp = JSON([
                    "id": UUID().uuidString,
                    "type": "tv",
                    "name": hostName() ?? "Apple TV",
                    "version": "1.1.0",
                    "address": getWiFiIPAddress() ?? "127.0.0.1",
                    "port": 23234
                ]).rawString()
                
                responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                response = .head(HTTPResponseHead(version: requestHeader.version, status: .ok, headers: headers))
            }
        case .body(let byteBuffer):
            // 处理请求体
            requestBody = byteBuffer
        case .end:
            // 请求体已完全接收，处理请求
            if let body = requestBody, let bodyString = body.getString(at: 0, length: body.readableBytes) {
                print("Request body: \(bodyString)")
                do {
                    if requestHeaderT?.uri.contains("sync/follow") == true {
                        let resp = JSON([
                            "status": true,
                            "message": "success",
                        ]).rawString()
                        if let respFollowList = try? JSON(data: bodyString.data(using: .utf8)!) {
                            var tempArray:[LiveModel] = []
                            for item in respFollowList.arrayValue {
                                var liveType = LiveType.bilibili
                                switch item["siteId"].stringValue {
                                    case "bilibili":
                                        liveType = .bilibili
                                    case "huya":
                                        liveType = .huya
                                    case "douyu":
                                        liveType = .douyu
                                    case "douyin":
                                        liveType = .douyin
                                    default:
                                        liveType = .bilibili
                                }
                                tempArray.append(LiveModel(userName: item["userName"].stringValue, roomTitle: "", roomCover: "", userHeadImg: item["face"].stringValue, liveType: liveType, liveState: nil, userId: "", roomId: item["roomId"].stringValue, liveWatchedCount: nil))
                            }
                            if self.syncSuccess != nil {
                                self.syncSuccess!(.favorite, tempArray)
                            }
                        }
                        responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                        response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
                    }
                }catch {
                    let resp = JSON([
                        "status": false,
                        "message": "解析数据异常",
                    ]).rawString()
                    responseBody = HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: resp ?? "")))
                    response = .head(HTTPResponseHead(version: requestHeaderT!.version, status: .ok, headers: headers))
                }
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
            
            let end = HTTPServerResponsePart.end(nil)
            context.writeAndFlush(self.wrapOutboundOut(end), promise: nil)
            context.close(promise: nil)
        }
    }
}

func getWiFiIPAddress() -> String? {
    var address: String?
    // Get list of all interfaces on the local machine:
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    guard let firstAddr = ifaddr else { return nil }

    // For each interface ...
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee

        // Check for IPv4 or IPv6 interface:
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) {

            // Check if interface is en0 which is the Wi-Fi connection on the iPhone
            let name = String(cString: interface.ifa_name)
            if name == "en0" || name == "en1" {
                // Convert interface address to a human readable string:
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                address = String(cString: hostname)
            }
        }
    }
    freeifaddrs(ifaddr)

    return address
}

func hostName() -> String? {
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXHOSTNAMELEN))
    let ret = gethostname(ptr, Int(MAXHOSTNAMELEN))
    var name: String?
    if ret == 0 {
        name = String(cString: ptr)
    }
    ptr.deallocate()
    return name
}
