//
//  DanmuView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/5.
//

import SwiftUI
import UIKit
import AngelLiveCore

final class TVDanmakuContainerView: UIView {
    let danmakuView = DanmakuView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(danmakuView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let innerFrame: CGRect
        if let window {
            let safeAreaFrame = window.safeAreaLayoutGuide.layoutFrame
            let safeAreaFrameInContainer = convert(safeAreaFrame, from: window)
            let intersection = bounds.intersection(safeAreaFrameInContainer)
            if intersection.isNull {
                innerFrame = CGRect(x: 0, y: 0, width: bounds.width, height: 0)
            } else {
                innerFrame = CGRect(
                    x: 0,
                    y: intersection.minY,
                    width: bounds.width,
                    height: max(0, intersection.height)
                )
            }
        } else {
            innerFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        }

        if danmakuView.frame != innerFrame {
            danmakuView.frame = innerFrame
            danmakuView.recalculateTracks()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}

struct DanmuView: UIViewRepresentable {
    var coordinator: Coordinator
    var height: CGFloat
    @Environment(AppState.self) var appViewModel

    func makeUIView(context: Context) -> TVDanmakuContainerView {
        let container = TVDanmakuContainerView(
            frame: .init(x: 0, y: 0, width: 1920, height: height)
        )
        let view = container.danmakuView
        // 各端统一采用顶部首个安全轨道;此处显式设置以固定 tvOS 行为。
        view.floatingTrackPolicy = .topPriority
        view.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        view.play()
        coordinator.uiView = view
        return container
    }

    func updateUIView(_ uiView: TVDanmakuContainerView, context: Context) {
        let danmakuView = uiView.danmakuView
        danmakuView.paddingTop = 5
        danmakuView.trackHeight = CGFloat(Double(appViewModel.danmuSettingsViewModel.danmuFontSize) * 1.35)
        danmakuView.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        danmakuView.displayArea = 1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: DanmakuView?

        func setup(view: DanmakuView) {
            self.uiView = view
        }

        /// 发射弹幕。共享工厂负责图文片段取图、局部降级、布局模型和样式。
        @MainActor
        func shoot(_ message: DanmakuDisplayMessage, showColorDanmu: Bool, alpha: CGFloat, font: CGFloat) {
            Task { @MainActor [weak self] in
                let model = await DanmakuDisplayModelFactory.makeModel(
                    for: message,
                    showColorDanmu: showColorDanmu,
                    alpha: alpha,
                    fontSize: font
                )
                self?.uiView?.shoot(danmaku: model)
            }
        }

        func pause() {
            DispatchQueue.main.async {
                self.uiView?.pause()
            }
        }

        func play() {
            DispatchQueue.main.async {
                self.uiView?.play()
            }
        }

        func clear() {
            DispatchQueue.main.async {
                self.uiView?.stop()
            }
        }
    }
}
