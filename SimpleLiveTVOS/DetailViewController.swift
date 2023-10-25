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
    #if os(iOS)
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        !playerView.isMaskShow
    }

    private let playerView = IOSVideoPlayerView()
    #elseif os(tvOS)
    private let playerView = VideoPlayerView()
    #else
    private let playerView = CustomVideoPlayerView()
    #endif
    var resource: KSPlayerResource? {
        didSet {
            if let resource {
                playerView.set(resource: resource)
            }
        }
    }
    var roomModel: LiveModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(playerView)
//        playerView.controllerView.isHidden = true
//        playerView.topMaskView.isHidden = true
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.isAutoPlay = true
        playerView.delegate = self
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
            #if os(iOS)
            if UIApplication.shared.statusBarOrientation.isLandscape {
                playerView.updateUI(isLandscape: false)
            } else {
                navigationController?.popViewController(animated: true)
            }
            #else
            navigationController?.popViewController(animated: true)
            #endif
        }
        playerView.becomeFirstResponder()
        Task {
            if roomModel?.liveType == .douyu {
                try await getDouyuPlay()
            }else if roomModel?.liveType == .huya {
                try await getHuyaPlay()
            }
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
    
    func getDouyuPlay() async throws {
        let dataReq = try await Douyu.getPlayArgs(rid: roomModel?.roomId ?? "")
        self.resource = KSPlayerResource(url: URL(string: "\(dataReq.data?.rtmp_url ?? "")/\(dataReq.data?.rtmp_live ?? "")")!)
    }
    
    func getHuyaPlay() async throws {
        let liveData = try await Huya.getPlayArgs(rid: roomModel?.roomId ?? "")
        if liveData != nil {
            let streamInfo = liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first
            var playQualitiesInfo: Dictionary<String, String> = [:]
            if let urlComponent = URLComponents(string: "?\(streamInfo?.sFlvAntiCode ?? "")") {
                if let queryItems = urlComponent.queryItems {
                    for item in queryItems {
                        playQualitiesInfo.updateValue(item.value ?? "", forKey: item.name)
                    }
                }
            }
            playQualitiesInfo.updateValue("1", forKey: "ver")
            playQualitiesInfo.updateValue("2110211124", forKey: "sv")
            let uid = try await Huya.getAnonymousUid()
            let now = Int(Date().timeIntervalSince1970) * 1000
            playQualitiesInfo.updateValue("\((Int(uid) ?? 0) + Int(now))", forKey: "seqid")
            playQualitiesInfo.updateValue(uid, forKey: "uid")
            playQualitiesInfo.updateValue(Huya.getUUID(), forKey: "uuid")
            playQualitiesInfo.updateValue("100", forKey: "t")
            playQualitiesInfo.updateValue("huya_live", forKey: "ctype")
            let ss = "\(playQualitiesInfo["seqid"] ?? "")|\("huya_live")|\("100")".md5
            let base64EncodedData = (playQualitiesInfo["fm"] ?? "").data(using: .utf8)!
            if let data = Data(base64Encoded: base64EncodedData) {
                let fm = String(data: data, encoding: .utf8)!
                var nsFM = fm as NSString
                nsFM = nsFM.replacingOccurrences(of: "$0", with: uid).replacingOccurrences(of: "$1", with: streamInfo?.sStreamName ?? "").replacingOccurrences(of: "$2", with: ss).replacingOccurrences(of: "$3", with: playQualitiesInfo["wsTime"] ?? "") as NSString
                playQualitiesInfo.updateValue((nsFM as String).md5, forKey: "wsSecret")
                playQualitiesInfo.removeValue(forKey: "fm")
                playQualitiesInfo.removeValue(forKey: "txyp")
                var playInfo: Array<URLQueryItem> = []
                for key in playQualitiesInfo.keys {
                    let value = playQualitiesInfo[key] ?? ""
                    playInfo.append(.init(name: key, value: value))
                }
                var urlComps = URLComponents(string: "")!
                urlComps.queryItems = playInfo
                let result = urlComps.url!
                var res = result.absoluteString as NSString
                for streamInfo in liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value ?? [] {
                    print("\(streamInfo.sFlvUrl)/\(streamInfo.sStreamName).\(streamInfo.sFlvUrlSuffix)\(res)")
                    print("\(streamInfo.sHlsUrl)/\(streamInfo.sStreamName).\(streamInfo.sHlsUrlSuffix)\(res)")
                    self.resource = KSPlayerResource(url: URL(string: "\(streamInfo.sFlvUrl)/\(streamInfo.sStreamName).\(streamInfo.sFlvUrlSuffix)\(res)")!)
                    break
                }
            }
        }
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let buttonPress = presses.first?.type else { return }
//        print("buttonPress.rawValue=====\(buttonPress.rawValue)")
//        let alertCtl = UIAlertController(title: "提示", message:"rawValue:\(buttonPress.rawValue)", preferredStyle: .alert)
//        alertCtl.addAction(.init(title: "cancel", style: .cancel))
//        self.present(alertCtl, animated: true)
        if buttonPress == .menu || buttonPress.rawValue == 2041 {
//            navigationController?.popViewController(animated: true)
            if playerView.isMaskShow {
                playerView.isMaskShow.toggle()
            }
        }else if buttonPress == .playPause || buttonPress.rawValue == 2040 {
            if playerView.playerLayer?.player.isPlaying ?? false == true {
                playerView.pause()
            }else {
                playerView.play()
            }
        }
    }
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
