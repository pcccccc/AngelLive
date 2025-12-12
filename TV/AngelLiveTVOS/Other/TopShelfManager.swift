//
//  TopShelfManager.swift
//  AngelLiveTVOS
//
//  通知 Top Shelf Extension 刷新内容
//

import Foundation
import TVServices

enum TopShelfManager {
    /// 通知 Top Shelf Extension 内容已更新，需要刷新
    /// 在收藏列表变化时调用此方法
    static func notifyContentChanged() {
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
