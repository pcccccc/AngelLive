import SwiftUI
import AngelLiveCore

struct PluginActionButton: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginManagementFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ManagedPluginItem
    let canOperate: Bool
    let canStop: Bool
    var large = false
    let action: () -> Void
    @State private var shakeTrigger = 0

    private var actionState: RemotePluginCatalogActionState { manager.managementActionState(for: item.pluginID, remote: item.remote) }
    private var waiting: Bool {
        manager.isWaitingForUpdate(for: item.pluginID)
        || (manager.installBatch.isRunning && manager.installBatch.pluginIds.contains(item.pluginID)
            && manager.installBatch.currentPluginId != item.pluginID && manager.installBatch.outcomes[item.pluginID] == nil)
    }
    private var phase: PluginManagementRowPhase { .resolve(actionState: actionState, isWaiting: waiting, isSuccessful: feedback.recentSuccessIDs.contains(item.pluginID)) }
    private var busy: Bool { phase == .queued || phase == .progress }
    private var succeeded: Bool { feedback.recentSuccessIDs.contains(item.pluginID) }
    private var failed: Bool { if case .failed = phase { true } else { false } }
    private var compact: Bool { busy || phase == .success }
    private var hidden: Bool { phase == .idle }
    private var label: LocalizedStringResource {
        switch phase {
        case .install: "安装"
        case .update: large ? "更新到 \(manager.latestVersion(for: item.pluginID) ?? "")" : "更新"
        case .failed: "重试"
        case .queued: "取消排队"
        case .progress: "停止"
        case .success: "已完成"
        case .idle: "已安装"
        }
    }
    var body: some View {
        Group {
            if !hidden { visibleButton }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.15), value: phase)
        .sensoryFeedback(.success, trigger: succeeded) { old, new in !old && new }
        .sensoryFeedback(.warning, trigger: failed) { old, new in !old && new }
        .onChange(of: failed) { _, value in if value { shakeTrigger += 1 } }
    }

    private var visibleButton: some View {
        let shouldReduceMotion = reduceMotion
        return Button(action: action) {
            ZStack {
                if busy {
                    ZStack {
                        if phase == .queued {
                            ProgressView().controlSize(large ? .regular : .small)
                        } else {
                            PluginIndeterminateRing(reduceMotion: reduceMotion)
                                .frame(width: large ? 40 : 28, height: large ? 40 : 28)
                        }
                        if phase == .progress && canStop {
                            RoundedRectangle(cornerRadius: 1.5).fill(PluginManagementLayout.primaryAction).frame(width: 7, height: 7)
                        }
                    }
                } else if phase == .success {
                    Image(systemName: "checkmark").font(large ? .title2.bold() : .body.bold()).foregroundStyle(.green)
                        .transition(.opacity)
                } else {
                    Text(label).font(large ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(large ? Color.white : failed ? .red : .accentColor)
                        .padding(.horizontal, large ? 24 : 16).padding(.vertical, large ? 14 : 6)
                        .fixedSize(horizontal: !large, vertical: true)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
            }
            .frame(minWidth: compact ? (large ? 50 : 30) : (large ? nil : 68), minHeight: large ? 50 : 30)
            .fixedSize(horizontal: !large || compact, vertical: false)
            .frame(maxWidth: large && !compact ? .infinity : nil)
            .background {
                if !compact {
                    Capsule().fill(failed ? Color.red.opacity(large ? 1 : 0.12) : PluginManagementLayout.primaryAction.opacity(large ? 1 : 0.12))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PluginPressButtonStyle())
        .disabled(phase == .success || (busy ? !canStop : !canOperate))
        .accessibilityLabel(Text("\(String(localized: label)) \(item.name)"))
        .accessibilityHint(busy ? "停止本次安装或更新批次" : "")
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeTrigger) { content, x in
            content.offset(x: shouldReduceMotion ? 0 : x)
        } keyframes: { _ in
            LinearKeyframe(-4, duration: 0.08)
            LinearKeyframe(4, duration: 0.08)
            LinearKeyframe(-3, duration: 0.08)
            LinearKeyframe(2, duration: 0.08)
            LinearKeyframe(0, duration: 0.08)
        }
    }
}

private struct PluginIndeterminateRing: View {
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            ZStack {
                Circle().stroke(PluginManagementLayout.primaryAction.opacity(0.16), lineWidth: 3)
                Circle().trim(from: 0, to: 0.72).stroke(PluginManagementLayout.primaryAction, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? -90 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }.padding(2)
        }.accessibilityHidden(true)
    }
}

struct PluginPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.2), value: configuration.isPressed)
    }
}
