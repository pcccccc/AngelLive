//
//  DanmakuImageCell.swift
//  AngelLiveCore
//
//  图片弹幕的绘制。引擎按 cellClass 池化分发,无需改动 DanmakuView/DanmakuTrack。
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public class DanmakuImageCell: DanmakuCell {
    required init(frame: CGRect) {
        super.init(frame: frame)
        danmakuBackgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func willDisplay() {}

    nonisolated public override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
#if os(iOS)
        let renderScale = abs(context.ctm.a)
#endif
        guard let model = model as? DanmakuImageCellModel else { return }

        let rect = model.contentRect(in: size)
        guard rect.width > 0, rect.height > 0 else { return }

#if canImport(AppKit) && !canImport(UIKit)
        // macOS: DanmakuAsyncLayer 走 NSImage.lockFocus,context 为 CG 原生未翻转坐标系,直绘方向正确
        context.draw(model.image, in: rect)
#else
        // iOS/tvOS: context 由 UIGraphicsBeginImageContextWithOptions 创建,已按 UIKit 约定翻转;
        // 此时 CGContext.draw 会上下颠倒,故走 UIImage.draw 让 UIKit 处理翻转
        // (与 DanmakuTextCell 依赖 NSString.draw 同理)
#if os(iOS)
        makeDanmakuImage(from: model.image, scale: renderScale).draw(in: rect)
#else
        makeDanmakuImage(from: model.image, scale: danmakuScreenScale()).draw(in: rect)
#endif
#endif
    }
}
