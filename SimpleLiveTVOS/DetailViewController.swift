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
    var roomModel: DouyuRoomModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(playerView)
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
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
            try await getDouyuPlay()
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
        let dataReq = try await Douyu.getPlayArgs(rid: "\(roomModel?.rid ?? 0)")
        print("\(dataReq.data?.rtmp_url ?? "")/\(dataReq.data?.rtmp_live ?? "")")
        self.resource = KSPlayerResource(url: URL(string: "\(dataReq.data?.rtmp_url ?? "")/\(dataReq.data?.rtmp_live ?? "")")!)
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
