import SwiftUI

/// FullUI 的悬浮圆环与 iOS 一样只跟随前台刷新，后台回写不延长提示。
struct TVFavoriteRefreshIndicator: View {
    let isRefreshing: Bool
    let refreshCycle: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsActivity = false
    @State private var startedAt: Date?
    @State private var observedCycle: Int?

    private struct RefreshTrigger: Equatable {
        let active: Bool
        let cycle: Int
    }

    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active || !showsActivity {
                Image(systemName: "arrow.clockwise")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 56, height: 56)
        .background(.black, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .opacity(showsActivity ? 1 : 0)
        .offset(y: showsActivity || reduceMotion ? 0 : -12)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: showsActivity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在刷新收藏")
        .accessibilityHidden(!showsActivity)
        .task(id: RefreshTrigger(active: isRefreshing, cycle: refreshCycle)) {
            let newManualCycle = observedCycle != nil && observedCycle != refreshCycle
            observedCycle = refreshCycle
            if isRefreshing || newManualCycle {
                startedAt = .now
                showsActivity = true
            }

            // 和 iOS 一样，极快的请求也保留一次可见的按键响应。
            guard !isRefreshing, let startedAt else { return }
            let remaining = max(0, 0.2 - Date.now.timeIntervalSince(startedAt))
            do { try await Task.sleep(for: .seconds(remaining)) }
            catch { return }
            showsActivity = false
            self.startedAt = nil
        }
        .onDisappear {
            showsActivity = false
            startedAt = nil
            observedCycle = nil
        }
    }
}
