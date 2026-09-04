//
//  DanmakuTextCell.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/29.
//

import Foundation
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public class DanmakuTextCell: DanmakuCell {
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
        guard let model = model as? DanmakuTextCellModel else { return }
        DanmakuTextDrawing.draw(
            model.text,
            font: model.font,
            color: model.color,
            at: CGPoint(x: 25, y: 5)
        )
    }

    public override func didDisplay(_ finished: Bool) {}
}

enum DanmakuTextOutlineStyle {
    /// 使用固定物理像素描边，避免不同屏幕缩放比例下视觉粗细漂移。
    static let physicalStrokeWidth: CGFloat = 3

    static func strokePercentage(fontSize: CGFloat, screenScale: CGFloat) -> CGFloat {
        let safeFontSize = max(fontSize, 1)
        let safeScale = max(screenScale, 1)
        let strokeWidthInPoints = physicalStrokeWidth / safeScale
        return -(strokeWidthInPoints / safeFontSize * 100)
    }

    static func outlineColor(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) -> DanmakuColor {
        // 官方解析器仅对纯黑文字切白边。这里把接近黑色也纳入,避免深色插件弹幕
        // 与黑边糊成一团,其余文字仍使用官方默认的黑色描边。
        let isNearlyBlack = max(red, green, blue) <= 0.12
        return (isNearlyBlack ? DanmakuColor.white : DanmakuColor.black)
            .withAlphaComponent(alpha)
    }
}
