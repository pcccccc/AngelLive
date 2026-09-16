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
            at: model.textDrawingOrigin,
            in: context
        )
    }

    public override func didDisplay(_ finished: Bool) {}
}

enum DanmakuTextOutlineStyle {
    /// 描边线宽为字号的 5%，在不同屏幕倍率下保持相同的逻辑宽度。
    static let strokePercentage: CGFloat = -5

    static func outlineColor(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) -> DanmakuColor {
        // 接近黑色的正文使用白边，避免字芯与黑边混在一起。
        let isNearlyBlack = max(red, green, blue) <= 0.12
        return isNearlyBlack ? DanmakuColor.white : DanmakuColor.black
    }
}
