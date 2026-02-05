//
//  LiveModel+Identity.swift
//  AngelLiveTVOS
//

import Foundation
import AngelLiveCore
import AngelLiveDependencies

extension LiveModel {
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
