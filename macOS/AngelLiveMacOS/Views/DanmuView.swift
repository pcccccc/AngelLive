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
        // 轨道高度 = 文字实际高度 + padding，约为 fontSize * 1.2 + 12
        view.trackHeight = fontSize * 1.2 + 12
        view.paddingTop = paddingTop
        view.paddingBottom = paddingBottom
        view.layer?.masksToBounds = true
        view.play()
        coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ nsView: DanmakuView, context: Context) {
        // §6.1 切字号:仅当 frame 真变化(窗口尺寸变)时才重算轨道;trackHeight/padding 各自 didSet 已在真变化时重算
        let newFrame = CGRect(origin: .zero, size: size)
        if nsView.frame != newFrame {
            nsView.frame = newFrame
            nsView.recalculateTracks()
        }
        nsView.danmakuBackgroundColor = .clear
        nsView.playingSpeed = Float(speed)
        // 轨道高度 = 文字实际高度 + padding，约为 fontSize * 1.2 + 12
        nsView.trackHeight = fontSize * 1.2 + 12
        nsView.paddingTop = paddingTop
        nsView.paddingBottom = paddingBottom
        nsView.layer?.masksToBounds = true
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
            // §6.2 错落感:displayTime ±15% 微抖动,同 tick 发出的弹幕速度自然拉开
            model.displayTime = model.displayTime * Double.random(in: 0.85...1.15)

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

        /// 更新弹幕视图的配置，避免等待 SwiftUI 重新创建视图
        func applyConfiguration(speed: CGFloat, font: CGFloat, paddingTop: CGFloat, paddingBottom: CGFloat) {
            DispatchQueue.main.async { [weak self] in
                guard let view = self?.view else { return }
                view.playingSpeed = Float(speed)
                // §6.1 切字号:trackHeight/padding didSet 仅在真变化时重算,只影响新弹幕,不扰动在飞
                view.trackHeight = font * 1.2 + 12
                view.paddingTop = paddingTop
                view.paddingBottom = paddingBottom
                if view.status != .play {
                    view.play()
                }
            }
        }
    }
}
