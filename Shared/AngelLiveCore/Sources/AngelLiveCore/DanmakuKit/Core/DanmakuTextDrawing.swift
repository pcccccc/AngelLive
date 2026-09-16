import Foundation
import CoreGraphics

enum DanmakuTextDrawing {
    nonisolated static func draw(
        _ text: String,
        font: DanmakuFont,
        color: DanmakuColor,
        at point: CGPoint,
        in context: CGContext
    ) {
        guard !text.isEmpty else { return }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        if !color.danmakuGetRGBA(&red, &green, &blue, &alpha) {
            red = 1
            green = 1
            blue = 1
            alpha = 1
        }

        let outlineColor = DanmakuTextOutlineStyle.outlineColor(
            red: red,
            green: green,
            blue: blue
        )
        let foregroundColor = color.withAlphaComponent(1)
        let outline = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: outlineColor,
                .strokeColor: outlineColor,
                .strokeWidth: DanmakuTextOutlineStyle.strokePercentage
            ]
        )
        let foreground = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: foregroundColor
            ]
        )

        context.saveGState()
        if alpha < 1 {
            context.setAlpha(alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        outline.draw(at: point)
        foreground.draw(at: point)
        if alpha < 1 {
            context.endTransparencyLayer()
        }
        context.restoreGState()
    }
}
