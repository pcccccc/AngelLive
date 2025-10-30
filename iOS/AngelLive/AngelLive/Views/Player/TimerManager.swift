//
//  TimerManager.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI
import Combine

/// 定时关闭管理器
@Observable
class TimerManager {
    /// 是否已设置定时器
    var isTimerActive: Bool = false

    /// 剩余秒数
    var remainingSeconds: Int = 0

    /// 格式化的剩余时间
    var formattedTime: String {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var timer: Timer?
    private var onTimerEnd: (() -> Void)?

    /// 启动定时器
    /// - Parameters:
    ///   - minutes: 定时分钟数
    ///   - onEnd: 定时结束回调
    func startTimer(minutes: Int, onEnd: @escaping () -> Void) {
        cancelTimer()

        remainingSeconds = minutes * 60
        isTimerActive = true
        onTimerEnd = onEnd

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            } else {
                self.timerCompleted()
            }
        }

        print("定时关闭已启动: \(minutes) 分钟")
    }

    /// 取消定时器
    func cancelTimer() {
        timer?.invalidate()
        timer = nil
        isTimerActive = false
        remainingSeconds = 0
        onTimerEnd = nil
        print("定时关闭已取消")
    }

    /// 定时器完成
    private func timerCompleted() {
        print("定时关闭时间到")
        let callback = onTimerEnd
        cancelTimer()
        callback?()
    }

    deinit {
        cancelTimer()
    }
}

/// 预设的定时选项
enum TimerPreset: Int, CaseIterable {
    case minutes10 = 10
    case minutes30 = 30
    case hour1 = 60
    case hour2 = 120
    case hour5 = 300
    case custom = -1

    var title: String {
        switch self {
        case .minutes10:
            return "10 分钟"
        case .minutes30:
            return "30 分钟"
        case .hour1:
            return "1 小时"
        case .hour2:
            return "2 小时"
        case .hour5:
            return "5 小时"
        case .custom:
            return "自定义"
        }
    }

    var minutes: Int {
        return rawValue
    }
}
