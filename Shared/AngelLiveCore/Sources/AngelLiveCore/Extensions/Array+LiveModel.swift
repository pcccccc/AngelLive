//
//  Array+LiveModel.swift
//  AngelLiveCore
//
//  Created by Claude on 2025/12/16.
//

import Foundation
import LiveParse

// MARK: - 直播状态显示名称常量

/// 直播状态显示名称常量，避免硬编码字符串
public enum LiveStateDisplayName {
    public static let live = "正在直播"
    public static let replay = "回放/轮播"
    public static let offline = "已下播"
    public static let unknown = "未知状态"
    
    /// 排序顺序
    public static let sortOrder = [live, replay, offline, unknown]
}

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
    
    // MARK: - 排序方法
    
    /// 按直播状态排序（正在直播 > 回放/轮播 > 已下播 > 未知）
    func sortedByLiveState() -> [LiveModel] {
        sorted { firstModel, secondModel in
            switch (firstModel.liveState, secondModel.liveState) {
            case ("1", "1"):
                return true // 两个都是直播中，保持原有顺序
            case ("1", _):
                return true // 第一个是直播中，排在前面
            case (_, "1"):
                return false // 第二个是直播中，排在前面
            case ("2", "2"):
                return true // 两个都是回放，保持原有顺序
            case ("2", _):
                return true // 第一个是回放，排在非直播的前面
            case (_, "2"):
                return false // 第二个是回放，排在非直播的前面
            default:
                return true // 其他情况保持原有顺序
            }
        }
    }
    
    // MARK: - 分组方法
    
    /// 按平台分组
    func groupedByPlatform() -> [FavoriteLiveSectionModel] {
        let types = Set(map { $0.liveType })
        var sections: [FavoriteLiveSectionModel] = []
        
        for type in types {
            let roomsForType = filter { $0.liveType == type }
            guard !roomsForType.isEmpty else { continue }
            
            var section = FavoriteLiveSectionModel()
            section.roomList = roomsForType
            section.title = LiveParseTools.getLivePlatformName(type)
            section.type = type
            sections.append(section)
        }
        
        return sections.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    /// 按直播状态分组
    func groupedByLiveState() -> [FavoriteLiveSectionModel] {
        let states = Set(map { $0.liveState })
        var sections: [FavoriteLiveSectionModel] = []
        
        for state in states {
            let roomsForState = filter { $0.liveState == state }
            guard !roomsForState.isEmpty else { continue }
            
            var section = FavoriteLiveSectionModel()
            section.roomList = roomsForState
            section.title = roomsForState.first?.liveStateFormat() ?? LiveStateDisplayName.unknown
            section.type = roomsForState.first?.liveType ?? .bilibili
            sections.append(section)
        }
        
        // 按预定义顺序排序
        return sections.sorted { model1, model2 in
            let order = LiveStateDisplayName.sortOrder
            if let index1 = order.firstIndex(of: model1.title),
               let index2 = order.firstIndex(of: model2.title) {
                return index1 < index2
            }
            return model1.title < model2.title
        }
    }
    
    /// 根据设置的分组样式进行分组
    /// - Parameter style: 分组样式
    /// - Returns: 分组后的列表
    func groupedBySections(style: AngelLiveFavoriteStyle) -> [FavoriteLiveSectionModel] {
        switch style {
        case .section:
            return groupedByPlatform()
        case .liveState, .normal:
            return groupedByLiveState()
        }
    }
}
