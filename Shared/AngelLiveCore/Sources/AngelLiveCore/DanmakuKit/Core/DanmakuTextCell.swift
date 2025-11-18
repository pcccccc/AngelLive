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
        DispatchQueue.main.async {
            self.danmakuBackgroundColor = .clear
        }

#if canImport(AppKit) && !canImport(UIKit)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
#endif
        
        let text = model.text
#if canImport(AppKit) && !canImport(UIKit)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let ctFont = CTFontCreateCopyWithSymbolicTraits(model.font as CTFont, model.font.pointSize, nil, [.traitBold], .traitBold) ?? CTFontCreateWithName(model.font.fontName as CFString, model.font.pointSize, nil)
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let baselineY = model.font.ascender + 12

        let strokeAttributes: [NSAttributedString.Key: Any] = [
            fontKey: ctFont,
            colorKey: DanmakuColor.black.cgColor
        ]
        let fillAttributes: [NSAttributedString.Key: Any] = [
            fontKey: ctFont,
            colorKey: model.color.cgColor
        ]

        let strokeLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: strokeAttributes))
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.setTextDrawingMode(.stroke)
        context.textPosition = CGPoint(x: 25, y: baselineY)
        CTLineDraw(strokeLine, context)

        let fillLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: fillAttributes))
        context.setTextDrawingMode(.fill)
        context.textPosition = CGPoint(x: 25, y: baselineY)
        CTLineDraw(fillLine, context)
        context.restoreGState()
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
