//
//  FavoriteTabSymbolAnimator.swift
//  AngelLive
//
//  给原生 tab bar 里「收藏」tab 的图标，做带过渡动画的 SF 符号替换，
//  并在 .syncing 时不间断旋转（loading 效果）。
//
//  为什么需要它：原生 tab bar 里的图标是 SwiftUI 渲染后的一张静态图片，
//  CloudSyncTabIcon 里写的 .contentTransition / .symbolEffect 在 tab bar
//  里不会播放——切换是生硬替换。要拿到真实 UIImageView 并用 UIKit 的
//  setSymbolImage(_:contentTransition:) 才能让符号替换带动画。
//
//  仅用于 iPhone（iPad 走 sidebar，仍使用 CloudSyncTabIcon）。
//

import SwiftUI
import UIKit
import AngelLiveCore

// MARK: - CloudSyncStatus → SF 符号名（与 CloudSyncTabIcon 保持一致）

extension CloudSyncStatus {
    /// tab bar 图标使用的 SF 符号名
    var tabSymbolName: String {
        switch self {
        case .syncing:     return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .success:     return "checkmark.icloud.fill"
        case .error:       return "exclamationmark.icloud.fill"
        case .notLoggedIn: return "xmark.icloud.fill"
        }
    }
}

// MARK: - 把动画注入到 tab bar 图标上的 Representable

struct FavoriteTabSymbolAnimator: UIViewRepresentable {

    /// 当前 iCloud 同步状态（变化时 SwiftUI 会调用 updateUIView）
    var syncStatus: CloudSyncStatus
    /// 收藏 tab 的位置（从左往右数，收藏永远是第 0 个）
    var tabIndex: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        let status = syncStatus
        let index = tabIndex

        // 延一帧执行，保证 tab bar 已经布局完成
        DispatchQueue.main.async {
            guard let window = uiView.window ?? Self.activeKeyWindow(),
                  let tabBar = Self.findTabBar(in: window) else { return }

            // 收藏图标的所有副本（它的符号都含 "icloud"；其它 tab 是 grid/gear/magnifyingglass，不含）
            let icloudViews = Self.symbolImageViews(in: tabBar)
                .filter { $0.description.contains("icloud") }

            guard !icloudViews.isEmpty else {
                // 退路：极端情况匹配不到 icloud，就按位置取可见的第 index 个
                if let fallback = Self.fallbackImageView(in: tabBar, tabIndex: index) {
                    coordinator.apply(status: status, target: fallback, allIcloudViews: [fallback])
                }
                return
            }

            // 当前真正可见的那一个（iOS 26 有隐藏副本，frame 常在 (0,0)）
            let target = icloudViews.first { Self.isEffectivelyVisible($0) && $0.bounds.width > 1 }
                ?? icloudViews[0]
            coordinator.apply(status: status, target: target, allIcloudViews: icloudViews)
        }
    }

    // MARK: - Coordinator：对账式应用（对图标被重建鲁棒）

    final class Coordinator {
        private var appliedStatus: CloudSyncStatus?
        private weak var appliedTarget: UIImageView?

        func apply(status: CloudSyncStatus, target: UIImageView, allIcloudViews: [UIImageView]) {
            // 状态和目标都没变 → 保持现状，不要重启动画（否则会卡顿）
            if appliedStatus == status, appliedTarget === target { return }

            if #available(iOS 18.0, *) {
                // 关键：先把所有 icloud 图标（含隐藏副本/孤儿）的效果清掉。
                // animated: false → 瞬间硬停，否则旋转会「减速转两三圈」才停，
                // 导致换成对号后对号还带着惯性转。
                for iv in allIcloudViews { iv.removeAllSymbolEffects(animated: false) }
            }

            // 带过渡地换符号
            let image = UIImage(systemName: status.tabSymbolName) ?? UIImage()
            target.setSymbolImage(image, contentTransition: .replace)

            // 只有 syncing 才在当前可见图标上不间断旋转
            if #available(iOS 18.0, *), status == .syncing {
                target.addSymbolEffect(.rotate, options: .repeat(.continuous))
            }

            appliedStatus = status
            appliedTarget = target
        }
    }

    // MARK: - 查找逻辑

    /// 退路：没匹配到 icloud 时，在可见符号图标里按位置取第 tabIndex 个
    private static func fallbackImageView(in tabBar: UITabBar, tabIndex: Int) -> UIImageView? {
        let visible = symbolImageViews(in: tabBar)
            .filter { isEffectivelyVisible($0) && $0.bounds.width > 1 }
            .sorted { $0.convert($0.bounds, to: tabBar).minX < $1.convert($1.bounds, to: tabBar).minX }
        return visible.indices.contains(tabIndex) ? visible[tabIndex] : nil
    }

    /// 自身及所有祖先都未隐藏、alpha>0、且已在 window 上 → 视为真正可见
    private static func isEffectivelyVisible(_ v: UIView) -> Bool {
        var node: UIView? = v
        while let n = node {
            if n.isHidden || n.alpha <= 0.01 { return false }
            node = n.superview
        }
        return v.window != nil
    }

    private static func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })
    }

    /// 递归找第一个 UITabBar
    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for sub in view.subviews {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }

    /// 递归收集所有「图片是 SF 符号」的 UIImageView
    private static func symbolImageViews(in view: UIView) -> [UIImageView] {
        var result: [UIImageView] = []
        for sub in view.subviews {
            if let iv = sub as? UIImageView, iv.image?.isSymbolImage == true {
                result.append(iv)
            }
            result.append(contentsOf: symbolImageViews(in: sub))
        }
        return result
    }
}
