#if canImport(KSPlayer)

//
//  KSCorePlayerView.swift
//  AngelLive
//
//  Forked and modified from KSPlayer by kintan
//  Created by pangchong on 10/26/25.
//

import Foundation
import SwiftUI
import KSPlayer

public struct KSCorePlayerView: View {
    @ObservedObject
    private var config: KSVideoPlayer.Coordinator
    public let url: URL
    public let options: KSOptions
    @Binding
    private var title: String
    private let subtitleDataSource: SubtitleDataSource?

    public init(config: KSVideoPlayer.Coordinator, url: URL, options: KSOptions, title: Binding<String>, subtitleDataSource: SubtitleDataSource?) {
        self.config = config
        self.url = url
        self.options = options
        _title = title
        self.subtitleDataSource = subtitleDataSource
    }

    public var body: some View {
        KSVideoPlayer(coordinator: config, url: url, options: options)
            .onStateChanged { playerLayer, state in
                if state == .readyToPlay {
                    if let subtitleDataSource {
                        config.playerLayer?.subtitleModel.addSubtitle(dataSource: subtitleDataSource)
                    }
                    if let movieTitle = playerLayer.player.dynamicInfo.metadata["title"] {
                        title = movieTitle
                    }
                }
            }
            .onBufferChanged { bufferedCount, consumeTime in
                KSLog("bufferedCount:\(bufferedCount),consumeTime:\(consumeTime)")
            }
        #if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
            .translationView()
        #endif
        #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(iOS)
        .focusable(!config.isMaskShow)
        #endif
        #if !os(visionOS)
        .onKeyPressLeftArrow {
            config.skip(interval: -15)
        }
        .onKeyPressRightArrow {
            config.skip(interval: 15)
        }
        .onKeyPressSapce {
            if config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        }
        #endif
        #if os(macOS)
        .navigationTitle(title)
        .onTapGesture(count: 2) {
            guard let view = config.playerLayer?.player.view else {
                return
            }
            view.window?.toggleFullScreen(nil)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
        }
        .onExitCommand {
            config.playerLayer?.player.view.exitFullScreenMode()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                config.skip(interval: -15)
            case .right:
                config.skip(interval: 15)
            case .up:
                config.playerLayer?.player.playbackVolume += 0.2
            case .down:
                config.playerLayer?.player.playbackVolume -= 0.2
            @unknown default:
                break
            }
        }
        #endif
    }
}

extension KSCorePlayerView: Equatable {
    public nonisolated static func == (lhs: KSCorePlayerView, rhs: KSCorePlayerView) -> Bool {
        lhs.url == rhs.url
    }
}

#endif
