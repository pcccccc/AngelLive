#if os(iOS) || os(tvOS)
//
//  DanmakuTextCell.swift
//  DanmakuKit_Example
//
//  Created by Q YiZhong on 2020/8/29.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import UIKit

public class DanmakuTextCell: DanmakuCell {
    required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func willDisplay() {}

    public override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard let model = model as? DanmakuTextCellModel else { return }
        
        DispatchQueue.main.async {
            self.backgroundColor = model.backgroundColor
        }
        
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        model.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let text = NSString(string: model.text)
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.saveGState()
        context.setTextDrawingMode(.stroke)

        let attributes: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: UIColor(rgb: 0x000000, alpha: alpha)]
        context.setStrokeColor(UIColor.black.cgColor)
        text.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributes)
        context.restoreGState()

        let attributes1: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: model.color]
        context.setTextDrawingMode(.fill)
        context.setStrokeColor(UIColor.white.cgColor)
        text.draw(at: CGPoint(x: 25, y: 5), withAttributes: attributes1)
    }

    public override func didDisplay(_ finished: Bool) {}
}
#endif
