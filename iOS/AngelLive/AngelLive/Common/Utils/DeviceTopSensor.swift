//
//  DeviceTopSensor.swift
//  AngelLive
//
//  依据当前窗口的顶部安全区高度判断屏幕顶部形态(灵动岛 / 刘海 / 无),
//  用来让顶部提示条贴合灵动岛「伪扩展」。用安全区而非机型表——全设备(含未来新机)通吃。
//

import UIKit

@MainActor
enum DeviceTopSensor {
    case dynamicIsland   // 灵动岛,顶部安全区约 59pt
    case notch           // 刘海,顶部安全区约 44–47pt
    case none            // 无刘海(Home 键机型 / iPad),约 20pt 或 0

    static var current: DeviceTopSensor {
        let top = topSafeInset
        if top >= 55 { return .dynamicIsland }
        if top >= 40 { return .notch }
        return .none
    }

    /// 当前 key window 的顶部安全区高度。
    static var topSafeInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = (scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)
            ?? scenes.first as? UIWindowScene
        let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }

    /// 提示条相对安全区顶部的微调间距。overlay(.top) 已按安全区排布(约落在岛/刘海下缘),
    /// 这里只做「贴合」微调:灵动岛用负值上移贴住岛底,营造从岛「长出」的连体感。
    var bannerTopOffset: CGFloat {
        switch self {
        case .dynamicIsland: return -6
        case .notch:         return -2
        case .none:          return 8
        }
    }

    /// 灵动岛/刘海机型用深色胶囊(呼应岛体);无刘海机型用普通浅色胶囊。
    var usesIslandStyle: Bool { self != .none }
}
