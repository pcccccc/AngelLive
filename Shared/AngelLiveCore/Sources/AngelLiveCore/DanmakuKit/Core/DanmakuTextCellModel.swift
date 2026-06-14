//
//  DanmakuTextCellModel.swift
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

public struct Danmu: Codable {
    var text: String
//    var time: TimeInterval
    var mode: Int32 = 1
    var fontSize: Int32 = 25
    var color: UInt32 = 16_777_215
    var isUp: Bool = false
    var aiLevel: Int32 = 0

//    init(dm: DanmakuElem) {
//        text = dm.content
//        time = TimeInterval(dm.progress / 1000)
//        mode = dm.mode
//        fontSize = dm.fontsize
//        color = dm.color
//        aiLevel = dm.weight
//    }
//
//    init(upDm dm: CommandDm) {
//        text = dm.content
//        time = TimeInterval(dm.progress / 1000)
//        isUp = true
//    }
}

public class DanmakuTextCellModel: DanmakuCellModel, Equatable {
    public var identifier = ""

    public var text = ""
    public var color: DanmakuColor = .white
    public var font = DanmakuFont.systemFont(ofSize: 50)
    public var backgroundColor: DanmakuColor = .clear

    public var cellClass: DanmakuCell.Type {
        return DanmakuTextCell.self
    }

    public var size: CGSize = .zero

    public var track: UInt?

    public var displayTime: Double = 10

    public var type: DanmakuCellType = .floating

    public var isPause = false

    public func calculateSize() {
        // 验证文本不为空
        guard !text.isEmpty else {
            size = CGSize(width: 100, height: 60)
            return
        }

#if canImport(AppKit) && !canImport(UIKit)
        // macOS: 使用 CoreText 计算，和渲染时完全一致
        let ctFont = font as CTFont
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let attributes: [NSAttributedString.Key: Any] = [fontKey: ctFont]

        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [])

        // 直接使用 bounds，只加固定的左右 padding（渲染时 x=25）
        let horizontalPadding: CGFloat = 50  // 左右各 25
        let verticalPadding: CGFloat = 12  // 上下固定留一点空间，减半

        size = CGSize(
            width: bounds.width + horizontalPadding,
            height: bounds.height + verticalPadding
        )

        // 调试输出(尺寸计算)
        Logger.debug("弹幕尺寸: 文本=\(text) 字号=\(font.pointSize) CTLine=\(bounds.width)x\(bounds.height) 最终=\(size.width)x\(size.height)", category: .danmu)
#else
        // iOS/tvOS: 使用 NSString.size
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nsText = NSString(string: text)
        let textSize = nsText.size(withAttributes: attributes)

        let horizontalPadding = font.pointSize + 25
        let verticalPadding = font.pointSize * 0.5 + 12

        size = CGSize(
            width: textSize.width + horizontalPadding,
            height: textSize.height + verticalPadding
        )
#endif
    }

    public static func == (lhs: DanmakuTextCellModel, rhs: DanmakuTextCellModel) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    public func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        return identifier == cellModel.identifier
    }

    public init(str: String, strFont: DanmakuFont) {
        text = str
        font = strFont
        type = .floating
        calculateSize()
    }

    public init(dm: Danmu) {
        text = dm.isUp ? "up: " + dm.text : dm.text // TODO: UP主弹幕样式
        color = DanmakuColor(rgb: Int(dm.color), alpha: 1)

        switch dm.mode {
        case 4:
            type = .bottom
        case 5:
            type = .top
        default:
            type = .floating
        }

        calculateSize()
    }
}
