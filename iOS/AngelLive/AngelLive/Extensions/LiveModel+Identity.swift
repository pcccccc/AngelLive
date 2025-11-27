//
//  LiveModel+Identity.swift
//  AngelLive
//
//  提供稳定的唯一标识，避免收藏列表中因 roomId 为空或重复导致的视图复用问题。
//

import Foundation
import AngelLiveCore
import AngelLiveDependencies

extension LiveModel {
    /// 用于 SwiftUI 列表/网格的稳定标识
    var stableIdentity: String {
        let liveTypeKey = liveType.rawValue

        if !roomId.isEmpty {
            return "\(liveTypeKey)-\(roomId)"
        }

        if !userId.isEmpty {
            return "\(liveTypeKey)-user-\(userId)"
        }

        let namePart = userName.isEmpty ? "unknown" : userName
        let titleHash = roomTitle.hashValue
        return "\(liveTypeKey)-fallback-\(namePart)-\(titleHash)"
    }
}

