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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 弹幕配置
    var fontSize: CGFloat = 16
    var alpha: CGFloat = 1.0
    var showColorDanmu: Bool = true
    var speed: CGFloat = 0.5

    // 检测是否为 iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func makeUIView(context: Context) -> DanmakuView {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        let view = DanmakuView(frame: .init(x: 0, y: 0, width: screenWidth, height: screenHeight))
        view.playingSpeed = Float(speed)
        view.play()
        coordinator.uiView = view

        // 初始配置
        view.paddingTop = 5
        view.trackHeight = fontSize * 1.35
        view.displayArea = 1  // 1 = 全屏显示区域

        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {
        // 根据设备和方向动态调整尺寸
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        // 更新 frame
        uiView.frame = .init(x: 0, y: 0, width: screenWidth, height: screenHeight)

        // 更新配置
        uiView.paddingTop = 5
        uiView.trackHeight = fontSize * 1.35
        uiView.displayArea = 1
        uiView.playingSpeed = Float(speed)

        // 重新计算轨道
        uiView.recalculateTracks()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: DanmakuView?

        func setup(view: DanmakuView) {
            self.uiView = view
        }

        /// 发射弹幕
        func shoot(text: String, showColorDanmu: Bool = true, color: UInt32 = 0xFFFFFF, alpha: CGFloat = 1.0, font: CGFloat = 16) {
            let model = DanmakuTextCellModel(str: text, strFont: UIFont.systemFont(ofSize: font))

            // 特殊消息处理（醒目留言等）
            if text.contains("醒目留言") || text.contains("SC") {
                model.backgroundColor = UIColor.orange
                model.color = UIColor.white
            } else {
                // 普通弹幕：根据设置显示颜色或白色
                if showColorDanmu && color != 0xFFFFFF {
                    model.color = UIColor(rgb: Int(color), alpha: alpha)
                } else {
                    model.color = UIColor.white.withAlphaComponent(alpha)
                }
            }

            DispatchQueue.main.async {
                self.uiView?.shoot(danmaku: model)
            }
        }

        /// 暂停弹幕
        func pause() {
            DispatchQueue.main.async {
                self.uiView?.pause()
            }
        }

        /// 继续弹幕
        func play() {
            DispatchQueue.main.async {
                self.uiView?.play()
            }
        }

        /// 清空弹幕
        func clear() {
            DispatchQueue.main.async {
                self.uiView?.stop()
            }
        }
    }
}
