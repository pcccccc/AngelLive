//
//  WelcomeManager.swift
//  AngelLive
//
//  Created by pangchong on 11/7/25.
//

import SwiftUI

@Observable
class WelcomeManager {
    private let hasSeenWelcomeKey = "hasSeenWelcome"

    var showWelcome: Bool

    init() {
        // 如果之前没有看过欢迎页，就显示
        self.showWelcome = !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }

    func completeWelcome() {
        // 标记为已看过
        UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
        // 隐藏欢迎页
        showWelcome = false
    }

    // 重置首次启动状态（用于测试）
    func resetWelcome() {
        UserDefaults.standard.removeObject(forKey: hasSeenWelcomeKey)
        showWelcome = true
    }
}
