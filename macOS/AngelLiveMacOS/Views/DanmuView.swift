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
        @MainActor private var roomGeneration = UUID()

        func attach(view: DanmakuView) {
            self.view = view
        }

        /// 发射弹幕。共享工厂负责图文片段取图、局部降级、布局模型和样式。
        @MainActor
        func shoot(_ message: DanmakuDisplayMessage, showColorDanmu: Bool, alpha: CGFloat, font: CGFloat) {
            let generation = roomGeneration
            Task { @MainActor [weak self] in
                let model = await DanmakuDisplayModelFactory.makeModel(
                    for: message,
                    showColorDanmu: showColorDanmu,
                    alpha: alpha,
                    fontSize: font
                )
                guard let self, self.roomGeneration == generation else { return }
                self.view?.shoot(danmaku: model)
            }
        }

        /// 换台时同步清空当前画面，并使仍在准备图文内容的旧房间消息失效。
        @MainActor
        func resetForRoomSwitch(showDanmu: Bool) {
            roomGeneration = UUID()
            view?.stop()
            if showDanmu { view?.play() }
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
