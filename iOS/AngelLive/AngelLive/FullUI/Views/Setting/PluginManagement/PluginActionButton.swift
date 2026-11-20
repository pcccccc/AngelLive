import SwiftUI
import AngelLiveCore

struct PluginActionButton: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginManagementFeedback.self) private var feedback
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(\.pluginConsentButtonID) private var consentButtonID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ManagedPluginItem
    let canOperate: Bool
    var large = false
    let action: (UUID) -> Void
    @State private var buttonID = UUID()
    @State private var shakeTrigger = 0

    private var actionState: RemotePluginCatalogActionState { item.row.action.state }
    private var pending: Bool { item.row.action.pending }
    private var progress: PluginInstallationProgress? { item.row.progress }
    private var phase: PluginManagementRowPhase {
        if progress != nil { return .progress }
        let showsInstalled = large && item.namespace == .catalog && actionState == .installed
        return .resolve(actionState: actionState, isWaiting: pending, isSuccessful: succeeded || showsInstalled)
    }
    private var busy: Bool { phase == .queued || phase == .progress }
    private var succeeded: Bool { item.row.action.succeeded }
    private var failed: Bool { if case .failed = phase { true } else { false } }
    private var label: LocalizedStringResource {
        switch phase {
        case .install: "安装"
        case .update: large ? "更新到 \(item.row.action.updateVersion ?? "")" : "更新"
        case .failed: "重试"
        case .queued: "取消排队"
        case .progress: pending ? "停止" : "正在处理"
        case .success, .idle: "已安装"
        }
    }

    private var progressDescription: Text {
        if phase == .queued { return Text("等待中") }
        switch progress {
        case .downloading(let fraction):
            if let fraction { return Text("已下载 \(fraction, format: .percent.precision(.fractionLength(0)))") }
            return Text("正在下载")
        case .verifyingAndExtracting: return Text("正在校验和解压")
        case .activating: return Text("正在激活")
        case nil: return Text("")
        }
    }

    var body: some View {
        Group {
            if phase != .idle {
                consentAnchor
                    .onDisappear(perform: clearConsentAnchor)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.15), value: phase)
        .sensoryFeedback(.success, trigger: succeeded) { old, new in !old && new }
        .sensoryFeedback(.warning, trigger: failed) { old, new in !old && new }
        .onChange(of: failed) { _, value in if value { shakeTrigger += 1 } }
    }

    @ViewBuilder private var consentAnchor: some View {
        let button = visibleButton.pluginInstallConsentAlert(consent, isActive: {
            consentButtonID == buttonID && feedback.consentOrigin?.buttonID == buttonID
        })
        if #available(iOS 18, *) {
            button.onScrollVisibilityChange(threshold: 0.01) { visible in
                if !visible { clearConsentAnchor() }
            }
        } else {
            button
        }
    }

    private func clearConsentAnchor() {
        if feedback.consentOrigin?.buttonID == buttonID { feedback.consentOrigin = nil }
    }

    private var visibleButton: some View {
        let shouldReduceMotion = reduceMotion
        return Button {
            if busy { manager.cancelInstallation(pluginId: item.pluginID) }
            else { action(buttonID) }
        } label: {
            ZStack {
                if busy {
                    PluginInstallationRing(fraction: phase == .queued ? 0 : progress?.fractionCompleted, reduceMotion: reduceMotion)
                        .frame(width: large ? 40 : 28, height: large ? 40 : 28)
                    if pending {
                        RoundedRectangle(cornerRadius: 1.5).fill(PluginManagementLayout.primaryAction).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                } else {
                    Text(label).font(large ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(phase == .success ? Color.secondary : large ? .white : failed ? .red : .accentColor)
                        .padding(.horizontal, large ? 24 : phase == .success ? 8 : 16).padding(.vertical, large ? 14 : 6)
                        .fixedSize(horizontal: !large, vertical: true)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
            }
            .frame(minWidth: large ? nil : 68, minHeight: large ? 50 : 30)
            .fixedSize(horizontal: !large, vertical: false)
            .frame(maxWidth: large ? .infinity : nil)
            .background {
                if !busy && phase != .success {
                    Capsule().fill(failed ? Color.red.opacity(large ? 1 : 0.12) : PluginManagementLayout.primaryAction.opacity(large ? 1 : 0.12))
                }
            }
            .frame(minWidth: PluginManagementLayout.minimumTarget, minHeight: PluginManagementLayout.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PluginPressButtonStyle())
        .disabled(phase == .success || (busy ? !pending : !canOperate))
        .accessibilityLabel(Text("\(String(localized: label)) \(item.name)"))
        .accessibilityValue(progressDescription)
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

private struct PluginInstallationRing: View {
    let fraction: Double?
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().stroke(PluginManagementLayout.primaryAction.opacity(0.16), lineWidth: 3)
            if let fraction {
                arc(fraction).rotationEffect(.degrees(-90))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    let rotation = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    arc(0.72).rotationEffect(.degrees(reduceMotion ? -90 : rotation))
                }
            }
        }.padding(2).accessibilityHidden(true)
    }

    private func arc(_ fraction: Double) -> some View {
        Circle().trim(from: 0, to: CGFloat(fraction))
            .stroke(PluginManagementLayout.primaryAction, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
