//
//  DetailViewController.swift
//  Demo
//
//  Created by kintan on 2018/4/15.
//  Copyright © 2018年 kintan. All rights reserved.
//

import CoreServices
import KSPlayer
import UIKit
import Starscream

protocol DetailProtocol: UIViewController {
    var resource: KSPlayerResource? { get set }
}

class DetailViewController: UIViewController, DetailProtocol {

    private let playerView = LivePlayerView()
    
    var roomModel: LiveModel?

    var resource: KSPlayerResource? {
        didSet {
            if let resource {
                playerView.set(resource: resource)
                playerView.titleLabel.text = "\(roomModel?.userName ?? "") - \(roomModel?.roomTitle ?? "")"
            }
        }
    }
    public var didExitView: (Bool, String) -> Void = {_, _ in}
    private var isLiving: Bool = false
    private var socketManager = WebSocketManager.shard
    private var isConnected = false
    private var danmuModel: BilibiliDanmuModel?
    let socket = biliLiveWebSocket()
    
    var huyaLiveInfo: HuyaRoomInfoMainModel?//里面有获取虎牙弹幕必要参数，后期优化。

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(playerView)
        playerView.delegate = self
        if roomModel?.liveType == .bilibili {
            KSOptions.firstPlayerType = KSAVPlayer.self
        }else {
            KSOptions.firstPlayerType = KSMEPlayer.self
        }
       
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.isAutoPlay = true
        
        playerView.didExitView =  { [weak self] in
            self?.didExitView(false, "")
        }
        playerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.layoutIfNeeded()
        playerView.backBlock = { [unowned self] in
            navigationController?.popViewController(animated: true)
        }
        playerView.becomeFirstResponder()
        Task {
            await getPlayURL()
            await getDanmu()
        }
    }
    
    func getPlayURL() async {
        do {
            if try await getLiveState() == true {
                let url = try await roomModel?.getPlayArgs()
//                try await roomModel?.getPlayArgsV2()
                if url != nil {
                    self.resource = KSPlayerResource(url: URL(string: url!)!)
                }
            }else {
                self.didExitView(true, "该主播正在休息哦")
            }
        }catch {
            self.didExitView(true, "无法获取房间状态")
        }
    }
    
    func getDanmu() async {
        if roomModel == nil {
            return
        }
        do {
            var finalURL = ""
            var finalCookie = ""
            if roomModel?.liveType == .bilibili {
                let danmuData = try await Bilibili.getRoomDanmuDetail(roomId: roomModel!.roomId)
                danmuModel = danmuData
                var danmuDefaultUrl = "broadcastlv.chat.bilibili.com"
                var ws_port = 2244
                if danmuData.host_list.count != 0 {
                    danmuDefaultUrl = danmuData.host_list.first!.host
                }
                finalCookie = BiliBiliCookie.cookie
                finalURL = "ws://\(danmuDefaultUrl):\(ws_port)/sub"
                socket.bilibiliDanmuModel = danmuModel
                socket.buvid = try await Bilibili.getBuvid()
            }else if roomModel?.liveType == .douyu {
                
            }else if roomModel?.liveType == .huya {
                if huyaLiveInfo == nil {
                    return
                }
                socket.lYyid = "\(huyaLiveInfo?.roomInfo.tLiveInfo.lYyid ?? -1)"
                socket.lChannelId = "\(huyaLiveInfo?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first?.lChannelId ?? -1)"
                socket.lSubChannelId = "\(huyaLiveInfo?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first?.lSubChannelId ?? -1)"
            }else if roomModel?.liveType == .douyin {
                let userId = try await Douyin.getUserUniqueId(roomId: roomModel?.roomId ?? "")
                let webRid = roomModel?.roomId ?? ""
                let roomId = roomModel?.userId
                let cookie = try await Douyin.getCookie(roomId: roomModel?.roomId ?? "")
                socket.userId = userId
                socket.webRid = webRid
                socket.dyRoomId = roomId
                socket.cookie = cookie
            }
            socket.roomId = roomModel?.roomId ?? ""
            socket.liveType = roomModel?.liveType ?? .bilibili
            socket.delegate = self
            socket.connect(url: finalURL, cookie: finalCookie)
        }catch {
            print(error)
        }
    }

    func getLiveState() async throws -> Bool {
        if roomModel == nil {
            return false
        }
        if roomModel!.liveType == .bilibili { //1 正在直播 0 已下播
            let liveStatus = try await Bilibili.getLiveStatus(roomId: roomModel!.roomId)
            switch liveStatus {
                case 0:
                    return false
                case 1:
                    return true
                default:
                    return false
            }
        }else if roomModel!.liveType == .douyin {
            do {
                let dataReq = try await Douyin.getDouyinRoomDetail(streamerData: roomModel!)
                switch dataReq.data?.data?.first?.status {
                    case 4:
                        return false
                    case 2:
                        return true
                    default:
                        return false
                }
            }catch {
                return false
            }
        }else if roomModel!.liveType == .douyu {
            let liveStatus = try await Douyu.getLiveStatus(rid: roomModel!.roomId)
            switch liveStatus {
                case 0:
                    return false
                case 1:
                    return true
                case 2:
                    return false
                default:
                    return false
            }
        }else if roomModel!.liveType == .huya {
            huyaLiveInfo = try await Huya.getPlayArgs(rid: roomModel!.roomId)
            let liveStatus = huyaLiveInfo?.roomInfo.eLiveStatus
            switch liveStatus {
                case 2:
                    return true
                default:
                    return false
            }
        }else {
            return false
        }
    }

    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigationController?.setNavigationBarHidden(true, animated: true)
        }
        
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
        self.playerView.danMuView.stop()
        socket.disConnect()
    }
//    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
//        guard let buttonPress = presses.first?.type else { return }
////        print("buttonPress.rawValue=====\(buttonPress.rawValue)")
////        let alertCtl = UIAlertController(title: "提示", message:"rawValue:\(buttonPress.rawValue)", preferredStyle: .alert)
////        alertCtl.addAction(.init(title: "cancel", style: .cancel))
////        self.present(alertCtl, animated: true)
//        if buttonPress == .menu || buttonPress.rawValue == 2041 {
////            navigationController?.popViewController(animated: true)
////            if playerView.isMaskShow {
////                playerView.isMaskShow.toggle()
////            }
//        }else if buttonPress == .playPause || buttonPress.rawValue == 2040 {
//            if playerView.playerLayer?.player.isPlaying ?? false == true {
//                playerView.pause()
//            }else {
//                playerView.play()
//                playerView.autoFadeOutViewWithAnimation()
//            }
//        }else if (buttonPress == .select) {
//            if playerView.isMaskShow == false {
//                playerView.isMaskShow = true
//                playerView.toolBar.playButton.setNeedsFocusUpdate()
//                playerView.toolBar.playButton.updateFocusIfNeeded()
//            }else {
////                if playerView.playerLayer?.player.isPlaying ?? false == true {
////                    playerView.pause()
////                    playerView.isMaskShow = true
////                }else {
////                    playerView.play()
////                    playerView.isMaskShow = true
////                    playerView.autoFadeOutViewWithAnimation()
////                }
//            }
//        }
//    }
}

extension DetailViewController: PlayerControllerDelegate {
    func playerController(seek: TimeInterval) {
        
    }
    
    func playerController(state : KSPlayerState) {
 
    }

    func playerController(currentTime _: TimeInterval, totalTime _: TimeInterval) {
        
    }

    func playerController(finish _: Error?) {
        
    }

    func playerController(maskShow _: Bool) {
        #if os(iOS)
        setNeedsStatusBarAppearanceUpdate()
        #endif
    }

    func playerController(action _: PlayerButtonType) {
        
    }

    func playerController(bufferedCount _: Int, consumeTime _: TimeInterval) {
        
    }
}

extension DetailViewController: WebSocketManagerDelegate {
    func webSocketManagerDidConnect() {
        self.playerView.danMuView.play()
    }
    
    func webSocketManagerDidDisconnect(error: Error?) {
        self.playerView.danMuView.pause()
    }
    
    func webSocketManagerDidReceiveData(manager: WebSocketManager, data: Data) {
        
    }
    
    func webSocketManagerDidReceiveMessage(text: String, color: UInt32) {
        self.playerView.shootDanmu(text, color)
    }
}
