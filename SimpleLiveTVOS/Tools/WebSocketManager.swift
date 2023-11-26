//
//  WebSocketManager.swift
//  SwiftTools
//
//  Created by 网易词典 on 2019/12/1.
//  Copyright © 2019 xuanhe. All rights reserved.
//

import UIKit
import Starscream



enum WebSocketConnectType {
    case closed       //初始状态,未连接
    case connect      //已连接
    case disconnect   //连接后断开
    case reconnecting //重连中...
}



class WebSocketManager: NSObject {
    /// 单例,可以使用单例,也可以使用[alloc]init 根据情况自己选择
    static let shard = WebSocketManager()
    /// WebSocket对象
    private var webSocket : WebSocket?
    /// 是否连接
    var isConnected : Bool = false
    /// 代理
    weak var delegate: WebSocketManagerDelegate?
    
    private var heartbeatInterval: TimeInterval = 1
    
    /// 重连次数
    private var reConnectCount: Int = 0
    //存储要发送给服务端的数据,本案例不实现此功能,如有需求自行实现
    private var sendDataArray = [String]()
    
    
    ///心跳包定时器
    var heartBeatTimer: Timer?
    ///网络监听定时器
    var netWorkTimer:Timer?
    
    
    var connectType : WebSocketConnectType = .closed
    /// 用于判断是否主动关闭长连接，如果是主动断开连接，连接失败的代理中，就不用执行 重新连接方法
    private var isActivelyClose:Bool = false
    
    /// 当前是否有网络,👇👇👇👇👇应该由各自项目提供,本处为了方便,简历一个属性作为临时变量
    private var isHaveNet:Bool = true
    
    var url: String?
    var cookie: String?
    
    override init() {
        // webSocket.advancedDelegate = self
        
    }
    
    // MARK: - 公开方法,外部调用
    func connectSocket(url: String, cookie: String) {
        guard let url = URL(string: "wss://broadcastlv.chat.bilibili.com:443/sub") else {
            return
        }
        
        self.isActivelyClose = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        //添加头信息
        if cookie.count > 0 {
            request.setValue(cookie, forHTTPHeaderField: "cookie")
        }

        webSocket = WebSocket(request: request)
        webSocket?.delegate = self
        webSocket?.connect()
        // 自定义队列,一般不需要设置,默认主队列
        //webSocket?.callbackQueue = DispatchQueue(label: "com.vluxe.starscream.myapp")
        
    }
    /// 发送消息
    func sendMessage(_ data: Data) {
        if self.isHaveNet {
            // 有网络直接发消息
            if self.connectType == .connect {  //已经连接
                self.webSocket?.write(data: data)
            }else if self.connectType == .reconnecting {
//                self.sendDataArray.append(text)
            }else if self.connectType == .disconnect {
                reConnectSocket()
            }else{
//                self.sendDataArray.append(text)
            }
            
        } else {
            // 无网络的时候的操作
            //1.提示无网络
            //2.存储消息
//            self.sendDataArray.append(text)
            //等待来网
            guard isActivelyClose else {
                initNetWorkTestingTimer()
                return
            }
        }
    }
    /// 断开链接
    func disconnect() {
        self.isActivelyClose = true
        self.connectType = .disconnect
        webSocket?.disconnect()
        destoryHeartBeat()
        destoryNetWorkStartTesting()
    }
    /// 重新连接
    func reConnectSocket() {
        if self.reConnectCount > 10 { //重连10次
            self.reConnectCount = 0;
            return
        }
        //重连10次,每两次间隔5s
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) {
            if self.connectType == .reconnecting {
                return
            }
            /// 连接
            self.connectSocket(url: self.url ?? "", cookie: self.cookie ?? "")
            self.reConnectCount = self.reConnectCount + 1
        }
    }
    
    // MARK: - 网络监听
    func networkNotifation() {
        //外部最好也传进来一个网络变化的通知
        //当断开网络时候,不在进行重新连接
        
        //当网络恢复的时候,重新连接,根据自己业务进行更新.
        
        //更新网络状态
        isHaveNet = false
    }
    
    
    // MARK: - 私有方法
    /// 初始化心跳
    private func initHeartBeat() {
        
        if self.heartBeatTimer != nil {
            return
        }
        self.heartBeatTimer = Timer(timeInterval: heartbeatInterval, target: self, selector: #selector(sendHeartBeat), userInfo: nil, repeats: true)
        RunLoop.current.add(self.heartBeatTimer!, forMode: RunLoop.Mode.common)
    }
    
    private func initNetWorkTestingTimer() {
        if self.netWorkTimer != nil {
            return
        }
        self.netWorkTimer = Timer(timeInterval: 5, target: self, selector: #selector(noNetWorkStartTesting), userInfo: nil, repeats: true)
        RunLoop.current.add(self.netWorkTimer!, forMode: RunLoop.Mode.common)
    }
    
    /// 心跳
    @objc private func sendHeartBeat() {
        if self.isConnected {
            
            webSocket?.write(data: packet(str: "", 2))
            
            // 我在网上查阅资料显示,也可以使用webSocket?.write(string: "")
            // 即: webSocket?.write(string: text)
            // write方法中ping和text是一样的,只是传入的枚举不一样,可以参考源代码
        }else{
            // 发现没有连接,根据需求做判断
        }
    }
    
    /// 没有网络的时候开始定时 -- 用于网络检测
    @objc private func noNetWorkStartTesting() {
        //有网络
        if isHaveNet {//这里可以根据业务需要修改
            //1.关闭网络监测定时器
            destoryNetWorkStartTesting()
            //2.重新连接
            reConnectSocket()
        }
    }
    
    //关闭心跳定时器
    private func destoryHeartBeat() {
        self.heartBeatTimer?.invalidate()
        self.heartBeatTimer = nil
    }
    
    //关闭网络监测定时器
    private func destoryNetWorkStartTesting() {
        self.netWorkTimer?.invalidate()
        self.netWorkTimer = nil
    }
    
}

extension WebSocketManager: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(let headers):
            isConnected = true
//            delegate?.webSocketManagerDidConnect(manager: self)
            initHeartBeat()
            _ = "连接成功,在这里处理成功后的逻辑,比如将发送失败的消息重新发送等等..."
            print("websocket is connected: \(headers)")
            break
        case .disconnected(let reason, let code):
            isConnected = false
            
            let error = NSError(domain: reason, code: Int(code), userInfo: nil) as Error
//            delegate?.webSocketManagerDidDisconnect(manager: self, error: error)
            
            self.connectType = .disconnect
            if self.isActivelyClose {
                self.connectType = .closed
            } else {
                self.connectType = .disconnect
                destoryHeartBeat() //断开心跳定时器
                if self.isHaveNet {
                    reConnectSocket()  //重新连接
                } else {
                    initNetWorkTestingTimer()
                }
            }
            print("websocket is disconnected: \(reason) with code: \(code)")
            break
        case .text(let string):
//            delegate?.webSocketManagerDidReceiveMessage(manager: self, text: string)
            
            //当全局都需要数据时,这里使用通知.
            let dic = ["text" : string]
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "webSocketManagerDidReceiveMessage"), object: dic)
            print("Received text: \(string)")
            break
        case .binary(let data):
            print("Received data: \(data.count)")
            break
        case .ping(_):
            print("ping")
            break
        case .pong(_):
            print("pong")
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            isConnected = false
        case .error(let error):
            isConnected = false
            handleError(error)
        case .peerClosed:


            isConnected = false
        }
    }
    
    
    // custom
    func handleError(_ error: Error?) {
        if let e = error as? WSError {
            print("websocket encountered an error: \(e.message)")
        } else if let e = error {
            print("websocket encountered an error: \(e.localizedDescription)")
        } else {
            print("websocket encountered an error")
        }
    }
    
    
    // MARK: - 老版本的代理,不要了
    /// 👇👇👇👇👇👇👇👇👇👇
    ///都是分开的,现在都合成一个了,就是上面的didReceive,但是可以参考一下,理解逻辑,.知道哪些是重要的
    /// 连接成功后的回调
    func websocketDidConnect(socket: WebSocketClient) {
        print(#function)
    }
    /// 断开连接后的回调
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print(#function)
    }
    
    /// 接收到消息后的回调(String)
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print(#function)
    }
    /// 接收到消息后的回调(Data)
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print(#function)
    }
    
    ///  👆👆👆👆👆👆👆👆👆👆👆
    func packet(str: String ,_ type:Int) -> Data {
        // 该函数修改自https://github.com/komeiji-koishi-ww/bilibili_danmakuhime_swiftUI/
        
        //数据包
        var bodyDatas = Data()
        
        switch type {
        case 7: //认证包
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
}
