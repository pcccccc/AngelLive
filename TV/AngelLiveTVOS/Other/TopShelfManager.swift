//
//  TopShelfManager.swift
//  AngelLiveTVOS
//
//  通知 Top Shelf Extension 刷新内容
//

import Foundation
import TVServices
import AngelLiveCore

@MainActor
enum TopShelfManager {
    /// 仅由 FullUI 发布。先落盘再通知，扩展无需等待 iCloud 或插件网络请求。
    static func publish(favorites: [LiveModel]) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TopShelfSnapshotStore.appGroupIdentifier
        ) else {
            Logger.warning("[TopShelf] Shared container unavailable; snapshot was not published.", category: .app)
            return
        }

        do {
            let store = TopShelfSnapshotStore(containerURL: container)
            if try store.save(TopShelfSnapshot(favorites: favorites)) {
                notifyContentChanged()
            }
        } catch {
            Logger.warning("[TopShelf] Failed to publish favorite snapshot.", category: .app)
        }
    }

    /// 通知 Top Shelf Extension 内容已更新，需要刷新
    /// 在收藏列表变化时调用此方法
    static func notifyContentChanged() {
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
