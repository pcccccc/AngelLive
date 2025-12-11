//
//  SidebarTip.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/12/11.
//

import SwiftUI
import TipKit

struct SidebarTip: Tip {
    var title: Text {
        Text("呼出分类菜单")
    }

    var message: Text? {
        Text("在第一列时向左滑动可以打开分类筛选菜单")
    }

    var image: Image? {
        Image(systemName: "sidebar.left")
            .symbolRenderingMode(.hierarchical)
    }

    var options: [TipOption] {
        // 最多显示 1 次
        MaxDisplayCount(1)
    }
}
