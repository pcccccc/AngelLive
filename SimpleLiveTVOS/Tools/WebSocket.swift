import SwiftUI
import Starscream
import SwiftyJSON
import SWCompression
import JavaScriptCore
import Gzip

protocol WebSocketManagerDelegate: AnyObject {
    /// 建立连接成功通知
    func webSocketManagerDidConnect()
    /// 断开链接通知,参数 `isReconnecting` 表示是否处于等待重新连接状态。
    func webSocketManagerDidDisconnect(error: Error?)
    /// 接收到消息后的回调(String)
    func webSocketManagerDidReceiveMessage(text: String, color: UInt32)
    /// 接收到消息后的回调(Data)
    func webSocketManagerDidReceiveData(manager: WebSocketManager, data: Data)
}

class biliLiveWebSocket: NSObject {
    
    var heartbeatTimer: Timer? = nil
    var reConnectTimer: Timer? = nil
    var isConnected: Bool = false
    var receiveCounter: UInt64 = 0
    var lastReceiveCounts: UInt64 = 0
    var bilibiliDanmuModel: BilibiliDanmuModel?
    var buvid: String? //b站必要参数
    var roomId: String?
    var token: String = ""
    var socket: WebSocket?
    var liveType: LiveType?
    var lYyid: String? //虎牙必要参数
    var lChannelId: String? //虎牙必要参数
    var lSubChannelId: String? //虎牙必要参数
    let huyaJSContext = JSContext()
    var webRid: String? //抖音必要参数
    var dyRoomId: String? //抖音必要参数,这个roomID不是上面的roomId
    var userId: String? //抖音必要参数
    var cookie: String? //抖音必要参数
    
    
    var defaultServerURL: String {
        get {
            switch liveType {
            case .bilibili:
                return "ws://broadcastlv.chat.bilibili.com:2244/sub"
            case .huya:
                return "wss://cdnws.api.huya.com"
            case .douyin:
                return "wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/"
            case .douyu:
                return "wss://danmuproxy.douyu.com:8506/"
            case .qie:
                return ""
            case nil:
                return ""
            }
        }
    }
    
    weak var delegate: WebSocketManagerDelegate?

    override init() {
        super.init()
    }

    enum message: String {
        case dm = "DANMU_MSG" //弹幕消息
        case gift = "SEND_GIFT" //投喂礼物
        //case comboGift = "COMBO_SEND" //连击礼物
        //LIVE_INTERACTIVE_GAME
        case entry = "INTERACT_WORD" //进入房间
        //case ENTRY_EFFECT //欢迎舰长进入房间
        case sc = "SUPER_CHAT_MESSAGE"
    }
    

    func connect(url: String, cookie: String) {
        print("preConnected")
        var finalURL = ""
        if url.count == 0 {
            finalURL = defaultServerURL
        }else {
            finalURL = defaultServerURL
        }
        
        if liveType == .douyin {
            
            let url = URL(string: defaultServerURL)!
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                fatalError("Invalid URL")
            }

            components.scheme = "wss"
            let ts = Int(Date().timeIntervalSince1970 * 1000)
            components.queryItems = [
                URLQueryItem(name: "app_name", value: "douyin_web"),
                URLQueryItem(name: "version_code", value: "180800"),
                URLQueryItem(name: "webcast_sdk_version", value: "1.3.0"),
                URLQueryItem(name: "update_version_code", value: "1.3.0"),
                URLQueryItem(name: "compress", value: "gzip"),
                URLQueryItem(name: "cursor", value: "h-1_t-\(ts)_r-1_d-1_u-1"),
                URLQueryItem(name: "host", value: "https://live.douyin.com"),
                URLQueryItem(name: "aid", value: "6383"),
                URLQueryItem(name: "live_id", value: "1"),
                URLQueryItem(name: "did_rule", value: "3"),
                URLQueryItem(name: "debug", value: "false"),
                URLQueryItem(name: "maxCacheMessageNumber", value: "20"),
                URLQueryItem(name: "endpoint", value: "live_pc"),
                URLQueryItem(name: "support_wrds", value: "1"),
                URLQueryItem(name: "im_path", value: "/webcast/im/fetch/"),
                URLQueryItem(name: "user_unique_id", value: userId ?? ""), // Replace with your user ID
                URLQueryItem(name: "device_platform", value: "web"),
                URLQueryItem(name: "cookie_enabled", value: "true"),
                URLQueryItem(name: "screen_width", value: "1920"),
                URLQueryItem(name: "screen_height", value: "1080"),
                URLQueryItem(name: "browser_language", value: "zh-CN"),
                URLQueryItem(name: "browser_platform", value: "Win32"),
                URLQueryItem(name: "browser_name", value: "Mozilla"),
                URLQueryItem(name: "browser_version", value: "5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51"),
                URLQueryItem(name: "browser_online", value: "true"),
                URLQueryItem(name: "tz_name", value: "Asia/Shanghai"),
                URLQueryItem(name: "identity", value: "audience"),
                URLQueryItem(name: "room_id", value: dyRoomId ?? ""), // Replace with your room ID
                URLQueryItem(name: "heartbeatDuration", value: "0"),
                URLQueryItem(name: "signature", value: "00000000")
            ]

            if let uri = components.url {
                let urlString = uri.absoluteString
                finalURL = NSString(string: urlString).replacingOccurrences(of: "webcast3-ws-web-lq", with: "webcast5-ws-web-lf")
            } else {
                print("Invalid URL")
            }
        }
        
        
        var request = URLRequest(url: URL(string: finalURL)!)
        if cookie.count > 0 {
            request.setValue(cookie, forHTTPHeaderField: "cookie")
        }
        if liveType == .douyin {
            
            request.setValue(self.cookie, forHTTPHeaderField: "Cookie")
            request.setValue( "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51", forHTTPHeaderField: "User-Agnet")
        }
        socket = WebSocket(request: request)
        socket!.delegate = self
        socket!.connect()
        isConnected = true
    }
    
    func disConnect() {
        if (isConnected) {
            socket?.disconnect()
            isConnected = false
        }
    }
    
    func packet(_ type:Int) -> Data { 
        // 该函数修改自https://github.com/komeiji-koishi-ww/bilibili_danmakuhime_swiftUI/
        //数据包
        var bodyDatas = Data()
        
        switch type {
        case 7: //认证包
            let str = "{\"uid\": 0,\"roomid\": \(self.roomId ?? ""),\"protover\": 2,\"buvid\":\"\(buvid ?? "")\",\"platform\":\"web\",\"type\": 2,\"key\": \"\(self.bilibiliDanmuModel?.token ?? "")\"}"
            bodyDatas = str.data(using: String.Encoding.utf8)!
            
        default: //心跳包
            bodyDatas = "{}".data(using: String.Encoding.utf8)!
        }
        
        //header总长度,  body长度+header长度
        var len: UInt32 = CFSwapInt32HostToBig(UInt32(bodyDatas.count + 16))
        let lengthData = Data(bytes: &len, count: 4)
        
        //header长度, 固定16
        var headerLen: UInt16 = CFSwapInt16HostToBig(UInt16(16))
        let headerLenghData = Data(bytes: &headerLen, count: 2)
        
        //协议版本
        var versionLen: UInt16 = CFSwapInt16HostToBig(UInt16(1))
        let versionLenData = Data(bytes: &versionLen, count: 2)
        
        //操作码
        var optionCode: UInt32 = CFSwapInt32HostToBig(UInt32(type))
        let optionCodeData = Data(bytes: &optionCode, count: 4)
        
        //数据包头部长度（固定为 1）
        var bodyHeaderLength: UInt32 = CFSwapInt32HostToBig(UInt32(1))
        let bodyHeaderLengthData = Data(bytes: &bodyHeaderLength, count: 4)
        
        //按顺序添加到数据包中
        var packData = Data()
        packData.append(lengthData)
        packData.append(headerLenghData)
        packData.append(versionLenData)
        packData.append(optionCodeData)
        packData.append(bodyHeaderLengthData)
        packData.append(bodyDatas)
        
        return packData
    }
    
    
    
    func unpack(data: Data) -> String {
        let header = data.subdata(in: Range(NSRange(location: 0, length: 16))!)
        //let packetLen = header.subdata(in: Range(NSRange(location: 0, length: 4))!)
        //let headerLen = header.subdata(in: Range(NSRange(location: 4, length: 2))!)
        let protocolVer = header.subdata(in: Range(NSRange(location: 6, length: 2))!)
        let operation = header.subdata(in: Range(NSRange(location: 8, length: 4))!)
        //let sequenceID = header.subdata(in: Range(NSRange(location: 12, length: 4))!)
        let body = data.subdata(in: Range(NSRange(location: 16, length: data.count-16))!)
        
        var result = ""
        
        switch protocolVer._2BytesToInt() {
        case 0: // JSON
            print("[Protocol Version] 0")
            try! result = JSON(data: body).rawString()!
            print(result)
            
        case 1: // 人气值
            print("[Protocol Version] 1")
            break
            
        case 2: // zlib JSON
            print("[Protocol Version] 2")
            print("[Operation] \(operation._4BytesToInt())")
            guard let unzipData = try? ZlibArchive.unarchive(archive: body) else {
                print("[Warning] Failed Unzip Data")
                break
            }
            unpackUnzipData(data: unzipData)

            
        case 3: // brotli JSON
            print("[Protocol Version] 3")
            break
            
        default:
            print("[Protocol Version] default (\(protocolVer._2BytesToInt()))")
            break
        }
        
        return result
    }
    
    func unpackUnzipData(data: Data) {
        let bodyLen = data.subdata(in: Range(NSRange(location: 0, length: 4))!)._4BytesToInt()
        //print("[BodyLen] \(bodyLen)")
        if bodyLen > 16 {
            let cur = data.subdata(in: Range(NSRange(location: 16, length: bodyLen-16))!)
            A(json: JSON(cur))
            if data.count > bodyLen {
                let res = data.subdata(in: Range(NSRange(location: bodyLen, length: data.count-bodyLen))!)
                unpackUnzipData(data: res)
            }
        }
    }
    
    func A(json: JSON) {
        switch json["cmd"].stringValue {
        case message.dm.rawValue:
            if json["info"].arrayValue[3].count <= 0 {
                delegate?.webSocketManagerDidReceiveMessage(text: json["info"].arrayValue[1].stringValue, color: json["info"].arrayValue[0].arrayValue[3].uInt32Value)

            } else {
                delegate?.webSocketManagerDidReceiveMessage(text: json["info"].arrayValue[1].stringValue, color: json["info"].arrayValue[0].arrayValue[3].uInt32Value)
            }
        case message.sc.rawValue:
            print("===============SUPER CHAT==============")
            print(json)
            print("===============SUPER CHAT==============")
            delegate?.webSocketManagerDidReceiveMessage(text: "醒目留言: \(json["data"]["message"].stringValue)", color: json["data"]["background_price_color"].uInt32Value)
        default:
            break
        }
    }
    
    @objc func sendHeartbeat() {
        
        var heartSecond = 60
        if liveType == .bilibili {
            heartSecond = 60
        }else if liveType == .douyu {
            heartSecond = 45
        }else if liveType == .huya {
            heartSecond = 60
        }else if liveType == .douyin {
            heartSecond = 10
        }
        heartbeatTimer = Timer(timeInterval: TimeInterval(heartSecond), repeats: true) {_ in
            if self.liveType == .bilibili {
                self.socket?.write(data: self.packet(2))
            }else if self.liveType == .douyu {
                let timestamp = Int(Date().timeIntervalSince1970)
                let msg = "type@=keeplive/tick@=\(timestamp)/"
                self.socket?.write(data: self.dyEncode(msg: msg))
            }else if self.liveType == .huya {
                self.socket?.write(data: "ABQdAAwsNgBM".data(using: .utf8)!)
            }else if self.liveType == .douyin {
                do {
                    var obj = Douyin_PushFrame()
                    obj.payloadType = "hb"
                    let data = try obj.serializedData()
                    self.socket?.write(data: data)
                }catch {
                    
                }
            }
        }
        RunLoop.current.add(heartbeatTimer!, forMode: .common)
    }
    
    @objc func reConnect() {
        reConnectTimer = Timer(timeInterval: 10, repeats: true) {_ in
            // 每10秒检测一次，如果未接收到任何信息，可能连接已经断开
            if (self.receiveCounter > self.lastReceiveCounts) {
                self.lastReceiveCounts = self.receiveCounter
            } else {
                print("[Warning] Reconnecting ...")
                self.socket?.connect()
                print("[Warning] Reconnect successed")
            }
        }
    }
    
    func dyEncode(msg: String) -> Data {
        var data = Data()
        
        // 头部8字节，尾部1字节，与字符串长度相加即数据长度
        let dataLen = msg.utf8.count + 9
        let lenByte = Data(bytes: withUnsafeBytes(of: UInt32(dataLen).littleEndian) { Data($0) })
        
        // 前两个字节按照小端顺序拼接为0x02b1，转化为十进制即689（《协议》中规定的客户端发送消息类型）
        // 后两个字节即《协议》中规定的加密字段与保留字段，置0
        var sendByte = Data([0xb1, 0x02, 0x00, 0x00])
        
        // 将字符串转化为字节流
        if let msgByte = msg.data(using: .utf8) {
            sendByte.append(msgByte)
        }
        
        // 尾部以"\0"结束
        let endByte = Data([0x00])
        
        // 按顺序拼接在一起
        data.append(contentsOf: lenByte)
        data.append(contentsOf: lenByte)
        data.append(contentsOf: sendByte)
        data.append(contentsOf: endByte)
        
        return data
    }
    
    func douyuData(_ data: Data, isAuthData yesOrNo: Bool) {
        var contents: [String] = []
        var subData = data
        var _loction: Int = 0
        var _length: Int = 0
        
        repeat {
            // 获取数据长度
            if subData.count < 12 {
                break
            }
            
            _length = Int(subData.withUnsafeBytes { buffer in
                buffer.load(fromByteOffset: 0, as: Int32.self)
            }) - 12
            
            if _length > data.count {
                break
            }
            
            // 截取相应的数据
            let contentData = subData.subdata(in: 12..<_length + 12)
            if let content = String(data: contentData, encoding: .utf8) {
                contents.append(content)
            }
            
            // 截取余下的数据
            _loction += 12
            if _length + _loction > data.count {
                break
            }
            subData = data.subdata(in: _length + _loction..<data.count)

            
            _loction += _length
        } while _loction < data.count
        
        if contents.count > 0 {
            let str = contents.first!
            
            print("===content:\(contents)===")
            if NSString(string: str).contains("chatmsg") == true {
                formatBarrageDict(msg: str)
            }
        }
    }
    
    func huyaDecodeData(data: Data) {
//        print("got some data: \(data.count)")
        let bytes = [UInt8](data)
        if let re = huyaJSContext?.evaluateScript("test(\(bytes));"), let json = try? JSONSerialization.jsonObject(with: Data((re.toString() ?? "").utf8), options: []) as? [String: Any] {
            guard let str = json["sContent"] as? String else {
                return
            }
            let userInfo = json["tUserInfo"] as? [String: Any]
            let nn = userInfo?["sNickName"] as? String ?? ""
            let uid = userInfo?["lUid"] as? String ?? ""
            let tFormat = json["tFormat"] as? [String: Any]
            let col = tFormat?["iFontColor"] as? Int ?? -1
            guard str != "HUYA.EWebSocketCommandType.EWSCmd_RegisterRsp" else {
                print("huya websocket inited EWSCmd_RegisterRsp")
                return
            }
            guard str != "HUYA.EWebSocketCommandType.Default" else {
                print("huya websocket WebSocketCommandType.Default \(data)")
                return
            }
            guard !str.contains("分享了直播间，房间号"), !str.contains("录制并分享了小视频"), !str.contains("进入直播间"), !str.contains("刚刚在打赏君活动中") else { return }
            delegate?.webSocketManagerDidReceiveMessage(text: str, color: UInt32(getHuyaLiveColor(col: col)))
        }
    }
    
    func decodeDouyinData(data: Data) {
        do {
            let wssPackage = try Douyin_PushFrame(serializedData: data)
            let logID = wssPackage.logID
            let decompressed = Data.decompressGzipData(data: wssPackage.payload)
//            print(decompressed as! NSData)
            let decompressedData: Data
            if wssPackage.payload.isGzipped {
                decompressedData = try! wssPackage.payload.gunzipped()
            } else {
                decompressedData = wssPackage.payload
            }
            print( String(data: decompressedData, encoding: .utf8))
            let payloadPackage = try Douyin_Response(serializedData: decompressed ?? Data())
            
            if payloadPackage.needAck {
                douyinSendAck(logID, payloadPackage.internalExt)
            }
            for msg in payloadPackage.messagesList {
                if msg.method == "WebcastChatMessage" {
                    dyUnPackWebcastChatMessage(msg.payload)
                }else if msg.method == "WebcastRoomUserSeqMessage" {
                    dyUnPackWebcastRoomUserSeqMessage(msg.payload)
                }
            }
        }catch {
            print(error)
        }
    }
    
    func douyinSendAck(_ logId: UInt64, _ internalExt: String ) {
        do {
            var obj = Douyin_PushFrame()
            obj.payloadType = "ack"
            obj.logID = logId
            obj.payloadType = internalExt
            let data = try obj.serializedData()
            socket?.write(data: data)
        }catch {
            
        }
    }
    
    func dyUnPackWebcastChatMessage(_ payload: Data) {
        do {
            let chatMessage = try Douyin_ChatMessage(serializedData: payload)
            delegate?.webSocketManagerDidReceiveMessage(text: chatMessage.content, color: 0xFFFFFF)
            
        }catch {
            
        }
    }
    
    func dyUnPackWebcastRoomUserSeqMessage(_ payload: Data) {
        do {
            let roomUserSeqMessage = try Douyin_RoomUserSeqMessage(serializedData: payload)
            
        }catch {
            
        }
    }
    
    func formatBarrageDict(msg: String) -> [String: Any] {
       do {
           
           
           let keys = ["rid", "uid", "nn", "level", "bnn", "bl", "brid", "diaf", "txt", "col"]
           var values: [Any] = []
           
           for key in keys {
               let regex = try NSRegularExpression(pattern: #"\#(key)@=(.*?)/"#)
               if let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)) {
                   let matchedString = String(msg[Range(match.range(at: 1), in: msg)!])
                   print(matchedString)
                   values.append(matchedString)
               }else {
                   values.append("")
               }
           }
           
           let barrageDict: [String: Any] = [
               "rid": Int(values[0] as? String ?? "") ?? 0,
               "uid": Int(values[1] as? String ?? "") ?? 0,
               "nickname": values[2] as? String ?? "",
               "level": Int(values[3] as? String ?? "") ?? 0,
               "bnn": values[4] as? String ?? "",
               "bnn_level": Int(values[5] as? String ?? "") ?? 0,
               "brid": Int(values[6] as? String ?? "") ?? 0,
               "is_diaf": Int(values[7] as? String ?? "") ?? 0,
               "content": values[8] as? String ?? "",
               "col": Int(values[9] as? String ?? "") ?? 0
           ]
           delegate?.webSocketManagerDidReceiveMessage(text: barrageDict["content"] as? String ?? "", color: UInt32(getDouyinLiveColor(col: barrageDict["col"] as? Int ?? 0)))
           return barrageDict
       } catch {
           // Handle error
           print("Error: \(error)")
           return [:]
       }
   }
    
    func getDouyinLiveColor(col: Int) -> Int {
        switch col {
        case 1:
            return 0xFF0000
        case 2:
            return 0x1E7DF0
        case 3:
            return 0x7AC84B
        case 4:
            return 0xFF7F00
        case 5:
            return 0x9B39F4
        case 6:
            return 0xFF69B4
        default:
            return 0xffffff
        }
    }
    
    func getHuyaLiveColor(col: Int) -> Int {
        switch col {
        case 1:
            return 0xccff
        case 2:
            return 0xccff
        case 3:
            return 0x9AFF02
        case 4:
            return 0xFFFF00
        case 5:
            return 0xBF3EFF
        case 6:
            return 0xFF60AF
        default:
            return 0xFFFFFF
        }
    }
    
    
}

extension biliLiveWebSocket: WebSocketDelegate {

    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        receiveCounter += 1
        switch event {
        
        case .connected(let header):
            delegate?.webSocketManagerDidConnect()

            print("[log] Connected! Header is \(header)")
            if liveType == .bilibili {
                socket?.write(data: self.packet(7)) {
                    self.performSelector(onMainThread: #selector(self.sendHeartbeat), with: nil, waitUntilDone: false) // NSObject
                }
            }else if liveType == .douyu {
                socket?.write(data: dyEncode(msg: "type@=loginreq/roomid@=\(roomId ?? "")/")) {
                    print("============login")
                    self.socket?.write(data: self.dyEncode(msg: "type@=joingroup/rid@=\(self.roomId ?? "")/gid@=-9999/")) {
                        print("============group")
                        self.performSelector(onMainThread: #selector(self.sendHeartbeat), with: nil, waitUntilDone: false) // NSObject
                    }
                }
            }else if liveType == .huya {
                if let huyaFilePath = Bundle.main.path(forResource: "huya", ofType: "js") {
                    huyaJSContext?.evaluateScript(try? String(contentsOfFile: huyaFilePath))
                    huyaJSContext?.evaluateScript("""
                                    var wsUserInfo = new HUYA.WSUserInfo;
                                    wsUserInfo.lUid = "\(lYyid ?? "")";
                                    wsUserInfo.lTid = "\(lChannelId ?? "")";
                                    wsUserInfo.lSid = "\(lSubChannelId ?? "")";
                                    """)
                    let result = huyaJSContext?.evaluateScript("""
                        new Uint8Array(sendRegister(wsUserInfo));
                    """)
                                
                    let data = Data(result?.toArray() as? [UInt8] ?? [])
            //        try? webSocket.send(data: data)
                    socket?.write(data: data) {
                        self.performSelector(onMainThread: #selector(self.sendHeartbeat), with: nil, waitUntilDone: false) // NSObject
                    }
                }
            }else if liveType == .douyin {
                do {
//                    var obj = try Douyin_PushFrame(jsonString: "{\"webRid\": \(self.webRid ?? ""),\"roomId\": \(self.dyRoomId ?? ""),\"userId\": \(self.userId ?? ""),\"cookie\":\"\(self.cookie ?? "")\"}")
                    var obj = Douyin_PushFrame()
                    obj.payloadType = "hb"
                    let data = try obj.serializedData()
                    socket?.write(data: data)
                }catch {
                    print("====\(error)=====")
                }
            }
            
            
        case .disconnected(let reason, let code):
            print("[log] Disconnected: \(reason) with code: \(code)")
            isConnected = false
            print("[isConnected]: \(isConnected)")
            delegate?.webSocketManagerDidDisconnect(error: nil)
            
        case .binary(let data):
            print("[Received] binary: \(data)")//\n[Received json] \(json)")
            if liveType == .bilibili {
                unpack(data: data)
            }else if (liveType == .huya) {
                huyaDecodeData(data: data)
            }else if liveType == .douyin {
                decodeDouyinData(data: data)
            }else {
                douyuData(data, isAuthData: true)
            }
            
        case .text(let str):
            print("[Received] \(str)")
            
        case .error(let error):
            print("[Error] \(String(describing: error))")
            
        case .cancelled:
            print("[log] Cancelled")
            
        case .ping(_):
//            pingCount += 1
            print("[Ping]")
        
        case .pong(_):
            print("[Pong]")
            
        case.viabilityChanged(let viabilityChanged):
            print("[viabilityChanged] \(viabilityChanged)")
            
        case.reconnectSuggested(let reconnectSuggested):
            print("[reconnectSuggested] \(reconnectSuggested)")
                
        case .peerClosed:
            print("[peerClosed]")
        }
    }
}


struct DM: Identifiable { // cmd = DANMU_MSG
    let timestamp: Int
    let uid: Int?
    let color: UInt32
    let metal_level: Int
    let metal_color: UInt32
    let metal_name: String
    let uname: String
    let content: String
    let id = UUID()
}

extension DM: Equatable {
    static func == (l: DM, r: DM) -> Bool {
        if l.id == r.id {
            return true
        } else {
            return false
        }
    }
    
    static func != (l: DM, r: DM) -> Bool {
        if l.id == r.id {
            return false
        } else {
            return true
        }
    }
}

struct GIFT: Identifiable {
    let is_first: Bool
    
    let timestamp: Int
    
    //let super_gift_num: Int
    let combo_stay_time: Int
    
    let giftId: Int
    //let remain: Int
    let price: Int
    //let uid: Int
    let num: Int
    //let giftType: Int
    
    // medal info
    let medal_level: Int
    let medal_color: UInt32
    let medal_color_start: UInt32
    let medal_color_border: UInt32
    let medal_color_end: UInt32
    let medal_name: String
    
    let uname: String
    let giftName: String
    
    let id = UUID()
}

extension GIFT: Equatable {
    static func == (l: GIFT, r: GIFT) -> Bool {
        if l.id == r.id {
            return true
        } else {
            return false
        }
    }
    
    static func != (l: GIFT, r: GIFT) -> Bool {
        if l.id == r.id {
            return false
        } else {
            return true
        }
    }
}

struct ENTRY: Identifiable {
    let timestamp: Int

    let metal_level: Int
    let metal_color: UInt32
    let metal_name: String
    
    //let uname_color: String
    let uname: String

    let id = UUID()
}

extension ENTRY: Equatable {
    static func == (l: ENTRY, r: ENTRY) -> Bool {
        if l.id == r.id {
            return true
        } else {
            return false
        }
    }
    
    static func != (l: ENTRY, r: ENTRY) -> Bool {
        if l.id == r.id {
            return false
        } else {
            return true
        }
    }
}

// https://www.jianshu.com/p/04e76474ec6d
struct FixedSizeArray<T: Equatable> : Equatable, RandomAccessCollection {
    private var maxSize: Int
    private var array: [T] = []
    var count = 0
    
    init (maxSize: Int) {
        self.maxSize = maxSize
        self.array = [T]()
    }
    
    var startIndex: Int { array.startIndex }
    var endIndex: Int { array.endIndex }
    
    mutating func append(newElement: T) {
        while (count >= maxSize) {
            array.removeFirst()
            count -= 1
        }
        array.append(newElement)
        count += 1
    }
    
    mutating func setMaxSize(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    static func == (l: FixedSizeArray<T>, r: FixedSizeArray<T>) -> Bool {
        if (l.array == r.array) {
            return true
        } else {
            return false
        }
    }
    
    subscript(index: Int) -> T {
        assert(index >= 0)
        assert(index < count)
        return array[index]
    }
    
    
//    mutating func append(newElements: [T]) {
//
//    }
//
//    mutating func removeSubrange(from: Int, to: Int) {
//        array.removeSubrange(from..<to)
//    }
}

