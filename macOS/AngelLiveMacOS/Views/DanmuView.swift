//
//  DanmuView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/12/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AppKit
import AngelLiveCore

/// macOS 平台弹幕承载视图，基于 DanmakuKit 的 NSView 封装
struct DanmuView: NSViewRepresentable {
    var coordinator: Coordinator
    var size: CGSize
    var fontSize: CGFloat
    var speed: CGFloat
    var paddingTop: CGFloat
    var paddingBottom: CGFloat

    func makeNSView(context: Context) -> DanmakuView {
        let view = DanmakuView(frame: CGRect(origin: .zero, size: size))
        view.danmakuBackgroundColor = .clear
        view.playingSpeed = Float(speed)
        view.trackHeight = fontSize * 1.35
        view.paddingTop = paddingTop
        view.paddingBottom = paddingBottom
        view.layer?.masksToBounds = true
        view.play()
        coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ nsView: DanmakuView, context: Context) {
        nsView.frame = CGRect(origin: .zero, size: size)
        nsView.danmakuBackgroundColor = .clear
        nsView.playingSpeed = Float(speed)
        nsView.trackHeight = fontSize * 1.35
        nsView.paddingTop = paddingTop
        nsView.paddingBottom = paddingBottom
        nsView.layer?.masksToBounds = true
        nsView.recalculateTracks()
        if nsView.status != .play {
            nsView.play()
        }
        coordinator.attach(view: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var view: DanmakuView?

        func attach(view: DanmakuView) {
            self.view = view
        }

        func shoot(text: String, showColorDanmu: Bool, color: UInt32, alpha: CGFloat, font: CGFloat) {
            let model = DanmakuTextCellModel(str: text, strFont: NSFont.systemFont(ofSize: font))

            if text.contains("醒目留言") || text.contains("SC") {
                model.backgroundColor = DanmakuColor.orange
                model.color = DanmakuColor.white
            } else if showColorDanmu && color != 0xFFFFFF {
                model.color = DanmakuColor(rgb: Int(color), alpha: alpha)
            } else {
                model.color = DanmakuColor.white.withAlphaComponent(alpha)
            }

            DispatchQueue.main.async { [weak self] in
                self?.view?.shoot(danmaku: model)
            }
        }

        func play() {
            DispatchQueue.main.async { [weak self] in
                self?.view?.play()
            }
        }

        func pause() {
            DispatchQueue.main.async { [weak self] in
                self?.view?.pause()
            }
        }

        func clear() {
            DispatchQueue.main.async { [weak self] in
                self?.view?.stop()
            }
        }
    }
}
