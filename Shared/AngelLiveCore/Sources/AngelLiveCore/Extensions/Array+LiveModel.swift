//
//  Array+LiveModel.swift
//  AngelLiveCore
//
//  Created by Claude on 2025/12/16.
//

import Foundation
import LiveParse

public extension Array where Element == LiveModel {
    /// 去除重复的直播间（基于 liveType + roomId 唯一标识）
    func removingDuplicates() -> [LiveModel] {
        var seen = Set<String>()
        return filter { room in
            let key = "\(room.liveType.rawValue)_\(room.roomId)"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    /// 追加新房间并去重（保留已有房间，只添加不重复的新房间）
    func appendingUnique(contentsOf newRooms: [LiveModel]) -> [LiveModel] {
        var result = self
        var seen = Set<String>()

        // 先标记已有房间
        for room in self {
            let key = "\(room.liveType.rawValue)_\(room.roomId)"
            seen.insert(key)
        }

        // 只添加不重复的新房间
        for room in newRooms {
            let key = "\(room.liveType.rawValue)_\(room.roomId)"
            if !seen.contains(key) {
                seen.insert(key)
                result.append(room)
            }
        }

        return result
    }
}
