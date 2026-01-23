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

    public override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard let model = model as? DanmakuTextCellModel else { return }

        let text = model.text
        guard !text.isEmpty else { return }

#if canImport(AppKit) && !canImport(UIKit)
        // macOS: 描边 + 填充
        let nsText = NSString(string: text)
        let drawPoint = CGPoint(x: 25, y: 5)

        // 获取填充色的 alpha 值，用于描边
        var alpha: CGFloat = 1.0
        if let colorSpace = model.color.usingColorSpace(.sRGB) {
            alpha = colorSpace.alphaComponent
        }

        // 描边（使用与填充相同的透明度，但颜色更淡）
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        context.setLineWidth(2)
        context.setLineJoin(.round)
        let strokeAttrs: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: NSColor.black.withAlphaComponent(alpha * 0.5)]
        nsText.draw(at: drawPoint, withAttributes: strokeAttrs)
        context.restoreGState()

        // 填充
        let fillAttrs: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: model.color]
        nsText.draw(at: drawPoint, withAttributes: fillAttrs)
#else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !model.color.danmakuGetRGBA(&red, &green, &blue, &alpha) {
            red = 1
            green = 1
            blue = 1
            alpha = 1
        }
        let nsText = NSString(string: text)
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.saveGState()
        context.setTextDrawingMode(.stroke)

        let attributesStroke: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: DanmakuColor(rgb: 0x000000, alpha: alpha)]
        context.setStrokeColor(DanmakuColor.black.cgColor)
        nsText.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributesStroke)
        context.restoreGState()

        let attributesFill: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: model.color]
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        let strokeColor = DanmakuColor.black.cgColor
        context.setStrokeColor(strokeColor)
        nsText.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributesStroke)
        context.restoreGState()

        let attributes1: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: model.color]
        context.setTextDrawingMode(.fill)
        context.setStrokeColor(DanmakuColor.white.cgColor)
        nsText.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributes1)
#endif
    }

    public override func didDisplay(_ finished: Bool) {}
}
