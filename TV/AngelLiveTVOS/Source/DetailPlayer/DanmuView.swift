//
//  DanmuView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/5.
//

import SwiftUI
import UIKit

struct DanmuView: UIViewRepresentable {
    var coordinator: Coordinator
    var height: CGFloat
    @Environment(AppState.self) var appViewModel

    func makeUIView(context: Context) -> DanmakuView {
        let view = DanmakuView(frame: .init(x: 0, y: 0, width: 1920, height: height))
        view.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        view.play()
        coordinator.uiView = view
        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {
        uiView.frame = .init(x: 0, y: 0, width: 1920, height: height)
        uiView.paddingTop = 5
        uiView.trackHeight = CGFloat(Double(appViewModel.danmuSettingsViewModel.danmuFontSize) * 1.35)
        uiView.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        uiView.displayArea = 1
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

        func shoot(text: String, showColorDanmu: Bool, color: UInt32, alpha: CGFloat, font: CGFloat) {
            let model = DanmakuTextCellModel(str: text, strFont: .systemFont(ofSize: font))
            if text.contains("醒目留言") || text.contains("SC") {
                model.backgroundColor = .orange
                model.color = .white
            } else {
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
