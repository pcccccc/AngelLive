//
//  DanmakuTextCellModel.swift
//  DanmakuKit_Example
//
//  Created by Q YiZhong on 2020/8/29.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import Foundation
//import SwiftyJSON
import UIKit

struct Danmu: Codable {
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

class DanmakuTextCellModel: DanmakuCellModel, Equatable {
    var identifier = ""

    var text = ""
    var color: UIColor = .white
    var font = UIFont.systemFont(ofSize: 50)
    var backgroundColor:UIColor = .clear

    var cellClass: DanmakuCell.Type {
        return DanmakuTextCell.self
    }

    var size: CGSize = .zero

    var track: UInt?

    var displayTime: Double = 5

    var type: DanmakuCellType = .floating

    var isPause = false

    func calculateSize() {
        let fontSize = NSString(string: text).boundingRect(with: CGSize(width: CGFloat(Float.infinity
        ), height: font.lineHeight), options: [.usesFontLeading, .usesLineFragmentOrigin], attributes: [.font: font], context: nil).size
        size = CGSizeMake(fontSize.width + 30, fontSize.height)
    }

    static func == (lhs: DanmakuTextCellModel, rhs: DanmakuTextCellModel) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        return identifier == cellModel.identifier
    }

    init(str: String, strFont: UIFont) {
        text = str
        font = strFont
        type = .floating
        calculateSize()
    }

    init(dm: Danmu) {
        text = dm.isUp ? "up: " + dm.text : dm.text // TODO: UP主弹幕样式
        color = UIColor(rgb: Int(dm.color), alpha: 1)

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
