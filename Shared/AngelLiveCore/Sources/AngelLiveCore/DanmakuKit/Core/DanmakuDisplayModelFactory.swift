import Foundation
import CoreGraphics

/// 把展示协议转换成可发射 CellModel。图片并发加载，输出顺序始终与 segments 一致。
@MainActor
public enum DanmakuDisplayModelFactory {
    public static func makeImmediateModelIfAvailable(
        for message: DanmakuDisplayMessage,
        showColorDanmu: Bool,
        alpha: CGFloat,
        fontSize: CGFloat
    ) -> (any DanmakuCellModel)? {
        var text = ""
        for segment in message.segments {
            guard case .text(let fragment) = segment else { return nil }
            text += fragment
        }
        return makeModel(
            segments: text.isEmpty ? [] : [.text(text)], for: message,
            showColorDanmu: showColorDanmu, alpha: alpha, fontSize: fontSize
        )
    }

    public static func makeModel(
        for message: DanmakuDisplayMessage,
        showColorDanmu: Bool,
        alpha: CGFloat,
        fontSize: CGFloat
    ) async -> any DanmakuCellModel {
        let resolved = await DanmakuContentResolver.resolve(message.segments)
        let renderSegments = resolved.map { segment in
            switch segment {
            case .text(let text):
                DanmakuMixedCellSegment.text(text)
            case .image(let image, let pixelSize):
                DanmakuMixedCellSegment.image(image, pixelSize: pixelSize)
            }
        }
        return makeModel(
            segments: renderSegments, for: message,
            showColorDanmu: showColorDanmu, alpha: alpha, fontSize: fontSize
        )
    }

    private static func makeModel(
        segments: [DanmakuMixedCellSegment],
        for message: DanmakuDisplayMessage,
        showColorDanmu: Bool,
        alpha: CGFloat,
        fontSize: CGFloat
    ) -> any DanmakuCellModel {
        let content = segments.isEmpty && !message.text.isEmpty ? [.text(message.text)] : segments
        let font = DanmakuFont.systemFont(ofSize: fontSize)

        let model: any DanmakuCellModel
        if content.count == 1, case .text(let text) = content[0] {
            model = DanmakuTextCellModel(str: text, strFont: font)
        } else if content.count == 1, case .image(let image, let pixelSize) = content[0] {
            model = DanmakuImageCellModel(image: image, pixelSize: pixelSize, font: font)
        } else {
            model = DanmakuMixedCellModel(segments: content, font: font)
        }

        applyTextStyle(
            to: model,
            message: message,
            showColorDanmu: showColorDanmu,
            alpha: alpha
        )
        applySpeedVariation(to: model)
        return model
    }

    private static func applyTextStyle(
        to model: any DanmakuCellModel,
        message: DanmakuDisplayMessage,
        showColorDanmu: Bool,
        alpha: CGFloat
    ) {
        let color: DanmakuColor
        if message.text.contains("醒目留言") || message.text.contains("SC") {
            color = .white
        } else if showColorDanmu && message.color != DanmakuDisplayMessage.defaultColor {
            color = DanmakuColor(rgb: Int(message.color), alpha: alpha)
        } else {
            color = DanmakuColor.white.withAlphaComponent(alpha)
        }

        if let text = model as? DanmakuTextCellModel {
            text.color = color
            if message.text.contains("醒目留言") || message.text.contains("SC") {
                text.backgroundColor = .orange
            }
        } else if let mixed = model as? DanmakuMixedCellModel {
            mixed.color = color
            if message.text.contains("醒目留言") || message.text.contains("SC") {
                mixed.backgroundColor = .orange
            }
        }
    }

    private static func applySpeedVariation(to model: any DanmakuCellModel) {
        let multiplier = Double.random(in: 0.85...1.15)
        if let text = model as? DanmakuTextCellModel {
            text.displayTime *= multiplier
        } else if let image = model as? DanmakuImageCellModel {
            image.displayTime *= multiplier
        } else if let mixed = model as? DanmakuMixedCellModel {
            mixed.displayTime *= multiplier
        }
    }
}
