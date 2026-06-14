//
//  AirPlayView.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI
import AVKit
import AngelLiveCore

/// AirPlay 投屏选择器
struct AirPlayView: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.backgroundColor = .clear
        routePickerView.tintColor = .white
        routePickerView.prioritizesVideoDevices = true // 优先显示视频设备（Apple TV 等）
        routePickerView.delegate = context.coordinator
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // 不需要更新
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, AVRoutePickerViewDelegate {
        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            Logger.debug("AirPlay: 开始展示可用设备", category: .player)
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            Logger.debug("AirPlay: 关闭设备选择", category: .player)
        }
    }
}

/// AirPlay 按钮（自动触发选择器）
struct AirPlayButton: View {
    var body: some View {
        AirPlayView()
            .frame(width: 44, height: 44)
    }
}

#Preview {
    ZStack {
        Color.black
        AirPlayButton()
    }
}
