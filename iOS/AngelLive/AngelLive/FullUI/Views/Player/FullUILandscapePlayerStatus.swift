import Combine
import SwiftUI
import UIKit

struct FullUILandscapePlayerStatus: View {
    private nonisolated static let topPadding: CGFloat = 5
    private nonisolated static let rowHeight: CGFloat = 15
    nonisolated static let bottomEdge = topPadding + rowHeight
    nonisolated static let halfWidthWithClearance: CGFloat = 32

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isVisible: Bool

    private let battery = LandscapePlayerBattery.shared

    var body: some View {
        let visible = isVisible && scenePhase == .active

        ZStack {
            if visible {
                let reading = battery.reading
                TimelineView(.everyMinute) { context in
                    statusRow(at: context.date, battery: reading)
                }
                .onAppear { battery.beginMonitoring() }
                .onDisappear { battery.endMonitoring() }
                .onReceive(battery.changes) { _ in battery.refresh() }
                .transition(.opacity)
            }
        }
        .accessibilityHidden(!visible)
        .animation(FullUIPlayerChrome.visibilityAnimation(visible, reduceMotion: reduceMotion), value: visible)
        .padding(.top, Self.topPadding)
        .allowsHitTesting(false)
    }

    private func statusRow(at date: Date, battery: LandscapePlayerBattery.Reading?) -> some View {
        let time = date.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: .autoupdatingCurrent,
            timeZone: .autoupdatingCurrent,
            calendar: .autoupdatingCurrent
        ))
        return HStack(spacing: 4) {
            Text(verbatim: time)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)

            if let battery {
                Image(systemName: battery.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(battery.level <= 0.2 ? .red : .white)
            }
        }
        .fixedSize()
        .frame(height: Self.rowHeight)
        .fullUIPlayerMediaText()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: time, battery: battery))
    }

    private func accessibilityLabel(for time: String, battery: LandscapePlayerBattery.Reading?) -> Text {
        guard let battery else { return Text("时间 \(time)") }
        let percentage = Int((battery.level * 100).rounded())
        return Text("时间 \(time)，电量 \(percentage)%")
    }
}

@MainActor
@Observable
private final class LandscapePlayerBattery {
    static let shared = LandscapePlayerBattery()

    struct Reading {
        let level: Float
        let state: UIDevice.BatteryState

        var iconName: String {
            if state == .charging || state == .full {
                return "battery.100.bolt"
            }
            switch level {
            case ..<0.1: return "battery.0"
            case ..<0.25: return "battery.25"
            case ..<0.5: return "battery.50"
            case ..<0.75: return "battery.75"
            default: return "battery.100"
            }
        }
    }

    private(set) var reading: Reading?
    @ObservationIgnored private var visiblePlayers = 0
    @ObservationIgnored private var wasMonitoringEnabled = false

    let changes = Publishers.Merge(
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification),
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
    ).receive(on: RunLoop.main)

    func beginMonitoring() {
        // UIDevice monitoring is shared across every player window.
        if visiblePlayers == 0 {
            let device = UIDevice.current
            wasMonitoringEnabled = device.isBatteryMonitoringEnabled
            device.isBatteryMonitoringEnabled = true
        }
        visiblePlayers += 1
        refresh()
    }

    func endMonitoring() {
        visiblePlayers -= 1
        if visiblePlayers == 0 {
            UIDevice.current.isBatteryMonitoringEnabled = wasMonitoringEnabled
        }
    }

    func refresh() {
        guard visiblePlayers > 0 else { return }
        let device = UIDevice.current
        let level = device.batteryLevel
        reading = level >= 0 ? Reading(level: level, state: device.batteryState) : nil
    }
}
