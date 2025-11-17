//
//  DanmakuTextCell.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/29.
//

import Foundation
import CoreGraphics
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
        
        let text = NSString(string: model.text)
        let attributesStroke: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .foregroundColor: DanmakuColor(rgb: 0x000000, alpha: alpha)
        ]
        let attributesFill: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .foregroundColor: model.color
        ]
#if canImport(AppKit) && !canImport(UIKit)
        let attributedStroke = NSAttributedString(string: model.text, attributes: attributesStroke)
        let attributedFill = NSAttributedString(string: model.text, attributes: attributesFill)
        attributedStroke.draw(at: CGPoint(x: 25, y: 5))
        attributedFill.draw(at: CGPoint(x: 25, y: 5))
#else
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        let strokeColor = DanmakuColor.black.cgColor
        context.setStrokeColor(strokeColor)
        text.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributesStroke)
        context.restoreGState()

        context.setTextDrawingMode(.fill)
        context.setStrokeColor(DanmakuColor.white.cgColor)
        text.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributesFill)
#endif
    }

    public override func didDisplay(_ finished: Bool) {}
}
