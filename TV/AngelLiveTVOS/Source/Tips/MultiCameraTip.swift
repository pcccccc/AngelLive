//
//  MultiCameraTip.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/12/23.
//

import SwiftUI
import TipKit

struct MultiCameraTip: Tip {
    var title: Text {
        Text("多机位可用")
    }

    var message: Text? {
        Text("点击清晰度按钮可切换不同机位视角")
    }

    var image: Image? {
        Image(systemName: "video.badge.ellipsis")
            .symbolRenderingMode(.hierarchical)
    }

    var options: [TipOption] {
        // 最多显示 3 次
        MaxDisplayCount(3)
    }
}
