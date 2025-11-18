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

    public var displayTime: Double = 5

    public var type: DanmakuCellType = .floating

    public var isPause = false

    public func calculateSize() {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let bounding = NSString(string: text).boundingRect(
            with: CGSize(width: CGFloat.infinity, height: font.danmakuLineHeight * 1.2),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        ).size

        let horizontalPadding = font.pointSize * 0.8 + 40
        let verticalPadding = font.pointSize * 0.45 + 24
        let minWidth = font.danmakuLineHeight * 3.0
        let minHeight = font.danmakuLineHeight + 36
        size = CGSize(
            width: max(bounding.width + horizontalPadding, minWidth),
            height: max(bounding.height + verticalPadding, minHeight)
        )
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
