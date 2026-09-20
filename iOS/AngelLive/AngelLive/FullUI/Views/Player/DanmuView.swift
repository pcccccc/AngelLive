//
//  DanmuView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import UIKit
import AngelLiveCore

/// 弹幕视图（飞过屏幕的弹幕效果）
struct DanmuView: UIViewRepresentable {
    var coordinator: Coordinator

    // 弹幕配置
    var fontSize: CGFloat = 16
    var alpha: CGFloat = 1.0
    var showColorDanmu: Bool = true
    var speed: CGFloat = 0.5
    var areaIndex: Int = 2 // 显示区域索引：0=顶部1/4, 1=顶部1/2, 2=全屏, 3=底部1/2, 4=底部1/4

    func makeUIView(context: Context) -> DanmakuContainerView {
        let container = DanmakuContainerView(frame: .zero)
        let view = container.danmakuView
        view.playingSpeed = Float(speed)
        view.play()
        coordinator.uiView = view

        // 基础配置
        view.trackHeight = fontSize * 1.35


        return container
    }

    func updateUIView(_ container: DanmakuContainerView, context: Context) {
        let uiView = container.danmakuView
        // 更新配置(trackHeight didSet 仅在字号真变化时重算,且只影响新发弹幕)
        uiView.trackHeight = fontSize * 1.35
        uiView.playingSpeed = Float(speed)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: DanmakuView?
        private var generation = UUID()

        func setup(view: DanmakuView) {
            self.uiView = view
        }

        /// 发射弹幕。共享工厂负责图文片段取图、局部降级、布局模型和样式。
        @MainActor
        func shoot(_ message: DanmakuDisplayMessage, showColorDanmu: Bool = true, alpha: CGFloat = 1.0, font: CGFloat = 16) {
            let token = generation
            Task { @MainActor [weak self] in
                let model = await DanmakuDisplayModelFactory.makeModel(
                    for: message,
                    showColorDanmu: showColorDanmu,
                    alpha: alpha,
                    fontSize: font
                )
                guard let self, self.generation == token else { return }
                self.uiView?.shoot(danmaku: model)
            }
        }

        /// 暂停弹幕
        @MainActor
        func pause() {
            uiView?.pause()
        }

        /// 继续弹幕
        @MainActor
        func play() {
            uiView?.play()
        }

        /// 清空弹幕
        @MainActor
        func clear(resumeAfterClear: Bool = false) {
            generation = UUID()
            uiView?.stop()
            if resumeAfterClear { uiView?.play() }
        }
    }
}

/// SwiftUI owns the outer frame; UIKit updates the inner tracks after layout.
final class DanmakuContainerView: UIView {
    let danmakuView = DanmakuView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(danmakuView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frame = CGRect(origin: .zero, size: bounds.size)
        guard danmakuView.frame != frame else { return }
        danmakuView.frame = frame
        danmakuView.recalculateTracks()
    }
}
