import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 将一条有序图文内容一次性光栅化，后续运动仍交给 CALayer 合成。
public final class DanmakuMixedCell: DanmakuCell {
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
        guard let model = model as? DanmakuMixedCellModel else { return }

        for item in model.layoutItems {
            guard !isCancelled else { return }
            switch item.segment {
            case .text(let text):
                DanmakuTextDrawing.draw(
                    text,
                    font: model.font,
                    color: model.color,
                    at: item.rect.origin,
                    in: context
                )
            case .image(let image, _):
#if canImport(AppKit) && !canImport(UIKit)
                context.draw(image, in: item.rect)
#else
                makeDanmakuImage(from: image, scale: danmakuScreenScale()).draw(in: item.rect)
#endif
            }
        }
    }
}
