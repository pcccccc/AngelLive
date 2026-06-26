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
    var displayHeight: CGFloat // 实际显示区域的高度
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 弹幕配置
    var fontSize: CGFloat = 16
    var alpha: CGFloat = 1.0
    var showColorDanmu: Bool = true
    var speed: CGFloat = 0.5
    var areaIndex: Int = 2 // 显示区域索引：0=顶部1/4, 1=顶部1/2, 2=全屏, 3=底部1/2, 4=底部1/4

    func makeUIView(context: Context) -> DanmakuView {
        let screenWidth = UIScreen.main.bounds.width

        let view = DanmakuView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: displayHeight))
        view.playingSpeed = Float(speed)
        view.play()
        coordinator.uiView = view

        // 基础配置
        view.trackHeight = fontSize * 1.35


        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {
        // 根据设备和方向动态调整尺寸
        let screenWidth = UIScreen.main.bounds.width

        // §6.1 切字号:仅当 frame 真变化(旋转/尺寸变)时才重算轨道,避免无关刷新扰动在飞弹幕
        let newFrame = CGRect(x: 0, y: 0, width: screenWidth, height: displayHeight)
        if uiView.frame != newFrame {
            uiView.frame = newFrame
            uiView.recalculateTracks()
        }

        // 更新配置(trackHeight didSet 仅在字号真变化时重算,且只影响新发弹幕)
        uiView.trackHeight = fontSize * 1.35
        uiView.playingSpeed = Float(speed)
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
            // §6.2 错落感:displayTime ±15% 微抖动,同 tick 发出的弹幕速度自然拉开
            model.displayTime = model.displayTime * Double.random(in: 0.85...1.15)

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
