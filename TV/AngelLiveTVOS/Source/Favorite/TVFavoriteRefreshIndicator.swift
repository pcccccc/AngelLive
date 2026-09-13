import SwiftUI
import AngelLiveCore

/// FullUI 的悬浮刷新反馈：参考 iOS 的小圆环，不参与列表布局或遥控器焦点。
struct TVFavoriteRefreshIndicator: View {
    let model: AppFavoriteModel
    let isManualRefreshRunning: Bool
    let refreshCycle: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsActivity = false
    @State private var startedAt: Date?
    @State private var observedGenerationID: UUID?
    @State private var observedCycle = 0
    @State private var result: FavoriteRefreshSummary?

    private struct RefreshInput: Equatable {
        let active: Bool
        let generationID: UUID?
        let hasPending: Bool
        let summary: FavoriteRefreshSummary?
        let cycle: Int
    }

    private var input: RefreshInput {
        RefreshInput(
            active: isManualRefreshRunning || model.isFavoriteStatusRefreshing,
            generationID: model.currentFavoriteGenerationID,
            hasPending: !model.pendingPluginIds.isEmpty,
            summary: model.lastFavoriteRefreshSummary,
            cycle: refreshCycle
        )
    }

    private var message: String? {
        if showsActivity { return nil }
        if input.hasPending { return "部分收藏仍在更新" }
        guard let result else { return nil }
        let retained = result.failed + result.skipped
        if retained > 0 { return "\(retained) 项未更新，保留上次状态" }
        return "已刷新 \(result.succeeded) 项收藏"
    }

    private var symbol: String {
        if input.hasPending { return "clock.arrow.circlepath" }
        if let result, result.failed + result.skipped > 0 { return "exclamationmark.circle" }
        return "checkmark"
    }

    private var isVisible: Bool { showsActivity || input.hasPending || result != nil }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if showsActivity {
                    if reduceMotion || scenePhase != .active {
                        Image(systemName: "arrow.clockwise")
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                } else {
                    Image(systemName: symbol)
                }
            }
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 32, height: 32)

            if let message {
                Text(message)
                    .font(.caption)
                    .fixedSize()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, message == nil ? 12 : 20)
        .frame(height: 56)
        .background(.black, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion ? 0 : -12)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: message)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message ?? "正在刷新收藏")
        .accessibilityHidden(!isVisible)
        .task(id: input) {
            let current = input
            let newManualCycle = observedCycle != current.cycle
            observedCycle = current.cycle
            if current.active || current.hasPending || newManualCycle {
                observedGenerationID = current.generationID
            }

            if current.active {
                if startedAt == nil { startedAt = .now }
                result = nil
                showsActivity = true
                return
            }

            // 和 iOS 一样，极快的请求也保留一次可见的按键响应。
            if let startedAt {
                let remaining = max(0, 0.2 - Date.now.timeIntervalSince(startedAt))
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
            showsActivity = false
            startedAt = nil

            if current.hasPending {
                result = nil
                return
            }

            // 只展示本页实际观察到的刷新结果，返回页面时不重播旧的成功提示。
            guard let summary = current.summary,
                  summary.generationID == observedGenerationID else {
                result = nil
                return
            }
            result = summary
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            result = nil
        }
        .onDisappear {
            showsActivity = false
            startedAt = nil
            observedGenerationID = nil
            result = nil
        }
    }
}
