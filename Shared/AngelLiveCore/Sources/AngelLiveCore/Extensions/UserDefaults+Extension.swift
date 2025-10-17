//
//  UserDefaults+Extension.swift
//  AngelLiveCore
//
//  Created by pangchong
//

import Foundation

public extension UserDefaults {
    nonisolated(unsafe) static let shared = UserDefaults(suiteName: "group.com.lision.simplelivetvos")!
    private static let queue = DispatchQueue(label: "com.lision.simplelivetvos.userdefaults.queue")

    func synchronized() -> UserDefaults {
        return UserDefaults(suiteName: "group.com.lision.simplelivetvos")!
    }

    func set(_ value: Any?, forKey key: String, synchronize: Bool) {
        UserDefaults.queue.async { [weak self] in
            guard let self = self else { return }
            self.set(value, forKey: key)
            if synchronize {
                self.synchronize()
            }
        }
    }

    func value(forKey key: String, synchronize: Bool) -> Any? {
        var result: Any?
        UserDefaults.queue.sync { [weak self] in
            guard let self = self else { return }
            result = self.value(forKey: key)
        }
        return result
    }
}
