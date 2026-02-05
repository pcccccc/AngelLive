//
//  UserDefaults+Extension.swift
//  AngelLiveCore
//
//  Created by pangchong
//

import Foundation

public extension UserDefaults {
    nonisolated(unsafe) static let shared = UserDefaults(suiteName: "group.dev.idog.simplelivetvos")!

    func synchronized() -> UserDefaults {
        return UserDefaults(suiteName: "group.dev.idog.simplelivetvos")!
    }

    func set(_ value: (some Sendable)?, forKey key: String, synchronize: Bool) {
        self.set(value, forKey: key)
        if synchronize {
            self.synchronize()
        }
    }

    func value(forKey key: String, synchronize: Bool) -> Any? {
        return self.value(forKey: key)
    }
}
