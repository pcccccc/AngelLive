//
//  StatusBarViewModel.swift
//  AngelLive
//
//  Created by pangchong on 1/9/26.
//

import SwiftUI
import Combine

@Observable
final class StatusBarViewModel {
    var currentTime = Date()
    var batteryLevel: Float = UIDevice.current.batteryLevel
    var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState

    private var cancellables = Set<AnyCancellable>()

    // 时间格式化器
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var formattedTime: String {
        timeFormatter.string(from: currentTime)
    }

    var batteryIconName: String {
        if batteryState == .charging || batteryState == .full {
            return "battery.100.bolt"
        }
        switch batteryLevel {
        case 0..<0.1: return "battery.0"
        case 0.1..<0.25: return "battery.25"
        case 0.25..<0.5: return "battery.50"
        case 0.5..<0.75: return "battery.75"
        default: return "battery.100"
        }
    }

    var batteryColor: Color {
        if batteryState == .charging || batteryState == .full {
            return .green
        }
        return batteryLevel < 0.2 ? .red : .white
    }

    var batteryPercentage: Int {
        Int(batteryLevel * 100)
    }

    init() {
        setupMonitoring()
    }

    private func setupMonitoring() {
        // 启用电池监控
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState

        // 时间更新
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.currentTime = Date()
            }
            .store(in: &cancellables)

        // 电池电量变化
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.batteryLevel = UIDevice.current.batteryLevel
            }
            .store(in: &cancellables)

        // 电池状态变化
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.batteryState = UIDevice.current.batteryState
            }
            .store(in: &cancellables)
    }
}
