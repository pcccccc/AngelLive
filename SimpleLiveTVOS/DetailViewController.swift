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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(playerView)
        playerView.delegate = self
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSAVPlayer.self
        KSOptions.isAutoPlay = true
        playerView.didExitView =  { [weak self] in
            self?.didExitView(false, "")
        }
        playerView.translatesAutoresizingMaskIntoConstraints = false
        #if os(iOS)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.readableContentGuide.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #else
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #endif
        view.layoutIfNeeded()
        playerView.backBlock = { [unowned self] in
            navigationController?.popViewController(animated: true)
        }
        playerView.becomeFirstResponder()
        Task {
            await getPlayURL()
        }
    }
    
    func getPlayURL() async {
        do {
            if try await getLiveState() == true {
                let url = try await roomModel?.getPlayArgs()
                try await roomModel?.getPlayArgsV2()
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
            let liveStatus = try await Huya.getPlayArgs(rid: roomModel!.roomId)?.roomInfo.eLiveStatus
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

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigationController?.setNavigationBarHidden(true, animated: true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
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
    func playerController(state _: KSPlayerState) {}

    func playerController(currentTime _: TimeInterval, totalTime _: TimeInterval) {}

    func playerController(finish _: Error?) {}

    func playerController(maskShow _: Bool) {
        #if os(iOS)
        setNeedsStatusBarAppearanceUpdate()
        #endif
    }

    func playerController(action _: PlayerButtonType) {}

    func playerController(bufferedCount _: Int, consumeTime _: TimeInterval) {}
}
