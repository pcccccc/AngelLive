//
//  SupportDiagnosticsView.swift
//  AngelLiveCore
//
//  用户可控的问题诊断与反馈界面。诊断报告只在用户停止录制后生成，
//  分享前始终先显示本地预览。
//

import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(tvOS)
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
#endif

private struct SupportDiagnosticsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Hosts opt into showing support diagnostics entry points in their FullUI surface.
    var supportDiagnosticsEnabled: Bool {
        get { self[SupportDiagnosticsEnabledKey.self] }
        set { self[SupportDiagnosticsEnabledKey.self] = newValue }
    }
}

public extension View {
    /// Enables the user-facing support diagnostics entry points for this view tree.
    func supportDiagnosticsEnabled(_ enabled: Bool = true) -> some View {
        environment(\.supportDiagnosticsEnabled, enabled)
    }
}

private enum SupportDiagnosticsPhase {
    case start
    case recording
    case report

    var currentStep: Int {
        switch self {
        case .start: 1
        case .recording: 2
        case .report: 3
        }
    }
}

private enum SupportDiagnosticsNotice {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .success(let message), .failure(let message): message
        }
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

/// Records a user-controlled support session and presents its local report.
///
/// The view deliberately does not own a navigation container. Hosts can put it in
/// a `NavigationStack`, sheet, or full-screen cover while preserving their platform
/// presentation and dismissal behavior.
@MainActor
public struct SupportDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var service = SupportDiagnosticsService.shared
    @State private var description: String
    @State private var savedDescription: String
    @State private var notice: SupportDiagnosticsNotice?
    @State private var isPreviewPresented = false
    @State private var showRestartConfirmation = false
    @State private var showDiscardConfirmation = false

    public init() {
        let initialDescription = SupportDiagnosticsService.shared.lastReport?.userDescription ?? ""
        _description = State(initialValue: initialDescription)
        _savedDescription = State(initialValue: initialDescription)
    }

    private var phase: SupportDiagnosticsPhase {
        if service.isRecording { return .recording }
        return service.lastReport == nil ? .start : .report
    }

    private var contentMaxWidth: CGFloat {
        #if os(tvOS)
        return .infinity
        #else
        switch phase {
        case .report:
            680
        case .start, .recording:
            560
        }
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 0
        #elseif os(macOS)
        if case .report = phase { return 20 }
        return 24
        #else
        20
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
        return 60
        #elseif os(macOS)
        if case .report = phase { return 24 }
        return 20
        #else
        24
        #endif
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if !os(tvOS)
                if case .report = phase {
                    SupportDiagnosticsProgressView(phase: phase)
                }
                #endif

                if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
                    SupportDiagnosticsNoticeView(notice: .failure(errorMessage))
                } else if let notice {
                    SupportDiagnosticsNoticeView(notice: notice)
                }

                switch phase {
                case .start, .recording:
                    #if os(tvOS)
                    SupportDiagnosticsTVCapturePhase(
                        startedAt: service.startedAt,
                        onStart: startRecording,
                        onReturn: { dismiss() },
                        onStop: stopRecording
                    )
                    #else
                    SupportDiagnosticsCapturePhase(
                        startedAt: service.startedAt,
                        onStart: startRecording,
                        onReturn: { dismiss() },
                        onStop: stopRecording
                    )
                    #endif
                case .report:
                    if let report = service.lastReport {
                        #if os(tvOS)
                        SupportDiagnosticsTVReportPhase(
                            startedAt: report.startedAt,
                            endedAt: report.endedAt,
                            sessionID: report.sessionID,
                            actionCount: report.actions.count,
                            entryCount: report.entries.count,
                            failureTitle: report.failure?.title,
                            failureMessage: report.failure?.message,
                            isErrorSnapshot: isErrorSnapshot(report),
                            description: $description,
                            savedDescription: savedDescription,
                            onSaveDescription: { draft in
                                guard !service.isRecording,
                                      service.lastReport?.sessionID == report.sessionID else {
                                    return "报告已更新，请返回后重试。"
                                }
                                description = draft
                                saveDescription()
                                if service.errorMessage == nil {
                                    notice = nil
                                }
                                return service.errorMessage
                            },
                            onOpenPreview: openPreview,
                            onRestart: { showRestartConfirmation = true },
                            onClear: { showDiscardConfirmation = true }
                        )
                        .id(report.sessionID)
                        #else
                        SupportDiagnosticsReportPhase(
                            startedAt: report.startedAt,
                            endedAt: report.endedAt,
                            actionCount: report.actions.count,
                            entryCount: report.entries.count,
                            failureTitle: report.failure?.title,
                            failureMessage: report.failure?.message,
                            isErrorSnapshot: isErrorSnapshot(report),
                            description: $description,
                            savedDescription: savedDescription,
                            onSaveDescription: saveDescription,
                            onOpenPreview: openPreview,
                            onRestart: { showRestartConfirmation = true },
                            onClear: { showDiscardConfirmation = true }
                        )
                        #endif
                    }
                }
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background {
            SupportDiagnosticsSystemBackground()
                .ignoresSafeArea()
        }
        #if os(tvOS)
        .focusSection()
        .onExitCommand {
            if isPreviewPresented {
                isPreviewPresented = false
            } else {
                dismiss()
            }
        }
        #endif
        .navigationTitle("问题诊断与反馈")
        #if os(tvOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SupportDiagnosticsTVNavigationTitle()
            }
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $isPreviewPresented) {
            NavigationStack {
                SupportDiagnosticsReportPreviewView(service: service)
            }
            .preferredColorScheme(.dark)
        }
        #else
        .navigationDestination(isPresented: $isPreviewPresented) {
            SupportDiagnosticsReportPreviewView(service: service)
        }
        #endif
        .onAppear {
            syncDescriptionFromReport()
        }
        .onChange(of: service.lastReport?.sessionID) { _, _ in
            // A different report owns a different draft, including when its
            // first disk write failed but the new snapshot is available.
            description = service.lastReport?.userDescription ?? ""
            savedDescription = description
            notice = nil
        }
        .onChange(of: service.errorMessage) { _, newErrorMessage in
            guard let newErrorMessage, !newErrorMessage.isEmpty else { return }
            notice = .failure(newErrorMessage)
        }
        .alert("重新记录？", isPresented: $showRestartConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重新记录", role: .destructive) {
                startRecording()
            }
        } message: {
            Text("新的录制会替换最近一份诊断报告。")
        }
        .alert("确认清除报告？", isPresented: $showDiscardConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                clearReport()
            }
        } message: {
            Text("清除后，本机保存的诊断报告将被删除。")
        }
    }

    private func startRecording() {
        notice = nil
        service.startRecording()
        if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
            notice = .failure(errorMessage)
        }
    }

    private func stopRecording() {
        service.stopRecording()
        if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
            notice = .failure(errorMessage)
        } else {
            notice = nil
        }
    }

    private func saveDescription() {
        service.updateDescription(description)
        if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
            notice = .failure(errorMessage)
            return
        }
        savedDescription = service.lastReport?.userDescription ?? ""
        description = savedDescription
        notice = .success("补充已保存。")
    }

    private func openPreview() {
        guard service.lastReport != nil, !service.isRecording else { return }

        // The service updates its in-memory report before attempting disk I/O.
        // Only treat the edit as saved when the service cleared errorMessage.
        if description != savedDescription {
            service.updateDescription(description)
            if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
                notice = .failure(errorMessage)
                return
            }
            savedDescription = service.lastReport?.userDescription ?? ""
            description = savedDescription
        }
        isPreviewPresented = true
    }

    private func clearReport() {
        service.discardReport()
        description = ""
        savedDescription = ""
        if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
            notice = .failure(errorMessage)
        } else {
            notice = .success("诊断报告已清除。")
        }
    }

    private func syncDescriptionFromReport() {
        // A failed updateDescription mutates the in-memory snapshot before the
        // save error is known. Keep the edit visible until the user can retry.
        guard service.errorMessage == nil else { return }
        let reportDescription = service.lastReport?.userDescription ?? ""
        description = reportDescription
        savedDescription = reportDescription
    }

    private func isErrorSnapshot(_ report: SupportDiagnosticReport) -> Bool {
        report.failure != nil
            && report.actions.isEmpty
            && report.entries.isEmpty
            && report.startedAt == report.endedAt
    }

}

private struct SupportDiagnosticsProgressView: View {
    let phase: SupportDiagnosticsPhase

    var body: some View {
        HStack(spacing: 8) {
            SupportDiagnosticsStepView(number: "1", title: "开始", state: state(for: 1))
            SupportDiagnosticsStepConnector()
            SupportDiagnosticsStepView(number: "2", title: "复现", state: state(for: 2))
            SupportDiagnosticsStepConnector()
            SupportDiagnosticsStepView(number: "3", title: "分享", state: state(for: 3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("问题诊断步骤")
        .accessibilityValue("第 \(phase.currentStep) 步，共 3 步")
    }

    private func state(for step: Int) -> SupportDiagnosticsStepState {
        if step < phase.currentStep { return .complete }
        if step == phase.currentStep { return .current }
        return .upcoming
    }
}

private enum SupportDiagnosticsStepState {
    case complete
    case current
    case upcoming
}

private struct SupportDiagnosticsStepView: View {
    @ScaledMetric(relativeTo: .caption) private var markerSize = 24
    let number: String
    let title: LocalizedStringKey
    let state: SupportDiagnosticsStepState

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: markerSize, height: markerSize)
                if case .complete = state {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: number)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(numberColor)
                }
            }
            Text(title)
                .font(.subheadline.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(textColor)
        }
    }

    private var fillColor: Color {
        switch state {
        case .complete: .green
        case .current: Color.accentColor
        case .upcoming: Color.secondary.opacity(0.2)
        }
    }

    private var numberColor: Color {
        switch state {
        case .current, .complete: .white
        case .upcoming: .secondary
        }
    }

    private var textColor: Color {
        switch state {
        case .upcoming: .secondary
        case .current, .complete: .primary
        }
    }
}

private struct SupportDiagnosticsStepConnector: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
            .frame(maxWidth: 56)
            .accessibilityHidden(true)
    }
}

private struct SupportDiagnosticsNoticeView: View {
    let notice: SupportDiagnosticsNotice

    var body: some View {
        Label {
            Text(notice.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: notice.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        }
        .font(.callout)
        .foregroundStyle(notice.isFailure ? .red : .green)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityLabel(notice.isFailure ? "诊断操作失败：\(notice.message)" : "诊断操作成功：\(notice.message)")
    }
}

private struct SupportDiagnosticsSystemBackground: View {
    var body: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(tvOS)
        Rectangle().fill(.background)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

#if !os(tvOS)
private struct SupportDiagnosticsCapturePhase: View {
    let startedAt: Date?
    let onStart: () -> Void
    let onReturn: () -> Void
    let onStop: () -> Void

    private var isRecording: Bool {
        startedAt != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SupportDiagnosticsCaptureIntroView(isRecording: isRecording)

            SupportDiagnosticsRecordingPanel(
                startedAt: startedAt,
                onStart: onStart,
                onStop: onStop
            )

            if isRecording {
                SupportDiagnosticsReturnButton(onReturn: onReturn)
            } else {
                SupportDiagnosticsReproductionGuidanceView()
                SupportDiagnosticsWhatIsRecordedView()
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

private struct SupportDiagnosticsCaptureIntroView: View {
    let isRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记录一次问题")
                .font(.title2.weight(.semibold))

            Text(
                isRecording
                    ? "返回出现问题的页面，按平时的方式重现一次，完成后回来结束记录。离开此页不会停止记录。"
                    : "开始后，回到出现问题的页面，按平时的方式重现一次。完成后回来结束记录并检查报告。"
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif

private struct SupportDiagnosticsRecordingPanel: View {
    let startedAt: Date?
    let onStart: () -> Void
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isRecording: Bool {
        startedAt != nil
    }

    private var actionTitle: LocalizedStringKey {
        isRecording ? "结束记录" : "开始记录"
    }

    #if os(tvOS)
    let focusedAction: FocusState<SupportDiagnosticsTVFocus?>.Binding?

    init(
        startedAt: Date?,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        focusedAction: FocusState<SupportDiagnosticsTVFocus?>.Binding? = nil
    ) {
        self.startedAt = startedAt
        self.onStart = onStart
        self.onStop = onStop
        self.focusedAction = focusedAction
    }
    #else
    init(
        startedAt: Date?,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.startedAt = startedAt
        self.onStart = onStart
        self.onStop = onStop
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startedAt ?? context.date))
                VStack(alignment: .leading, spacing: 12) {
                    controlLayout {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                isRecording ? "正在记录" : "准备记录",
                                systemImage: isRecording ? "record.circle.fill" : "doc.text.magnifyingglass"
                            )
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isRecording ? .red : .primary)
                            .accessibilityLabel(isRecording ? "正在记录诊断信息" : "准备记录诊断信息")

                            durationText(elapsed)
                                .font(.system(.largeTitle, design: .monospaced).weight(.medium))
                                .monospacedDigit()
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.16),
                                    value: SupportDiagnosticsDuration.text(elapsed)
                                )
                                .accessibilityLabel(
                                    "已记录时长 \(SupportDiagnosticsDuration.accessibilityText(elapsed))"
                                )
                        }

                        Spacer(minLength: 12)

                        recordingControl
                    }

                    ProgressView(value: min(elapsed, 300), total: 300)
                        .progressViewStyle(.linear)
                        .tint(isRecording ? .red : .accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .accessibilityLabel("五分钟记录上限进度")
                }
            }

            Text("最长 5 分钟 · 结束后生成报告")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(panelPadding)
        .frame(maxWidth: .infinity, minHeight: panelMinHeight, alignment: .leading)
        .background {
            SupportDiagnosticsRecordingPanelBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var panelPadding: CGFloat {
        #if os(tvOS)
        20
        #elseif os(macOS)
        12
        #else
        16
        #endif
    }

    private var panelMinHeight: CGFloat {
        #if os(tvOS)
        168
        #elseif os(macOS)
        128
        #else
        136
        #endif
    }

    private var controlWidth: CGFloat {
        #if os(tvOS)
        180
        #else
        96
        #endif
    }

    private var controlMinHeight: CGFloat {
        #if os(tvOS)
        72
        #elseif os(macOS)
        56
        #else
        64
        #endif
    }

    private var controlLayout: AnyLayout {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        }
        #endif
        return AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    @ViewBuilder
    private func durationText(_ elapsed: TimeInterval) -> some View {
        let text = Text(verbatim: SupportDiagnosticsDuration.text(elapsed))
        if reduceMotion {
            text
        } else {
            text.contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var recordingControl: some View {
        #if os(tvOS)
        if let focusedAction {
            recordingControlButton
                .focused(focusedAction, equals: isRecording ? .stop : .start)
        } else {
            recordingControlButton
        }
        #else
        recordingControlButton
        #endif
    }

    private var recordingControlButton: some View {
        Button(action: isRecording ? onStop : onStart) {
            VStack(spacing: 4) {
                recordingSymbol
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)

                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    #if !os(tvOS)
                    .foregroundStyle(Color.primary)
                    #endif
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        #if os(tvOS)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        #else
        .buttonStyle(.bordered)
        #endif
        .frame(width: controlWidth)
        .frame(minHeight: controlMinHeight)
        .accessibilityLabel(isRecording ? "结束记录" : "开始记录")
        .accessibilityHint(isRecording ? "结束诊断记录并生成报告" : "开始诊断记录")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isRecording)
    }

    @ViewBuilder
    private var recordingSymbol: some View {
        let image = Image(systemName: isRecording ? "stop.fill" : "record.circle")
        if reduceMotion {
            image
        } else {
            image.contentTransition(.symbolEffect(.replace))
        }
    }
}

private struct SupportDiagnosticsRecordingPanelBackground: View {
    var body: some View {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(tvOS)
        Rectangle().fill(.background)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

#if !os(tvOS)
private struct SupportDiagnosticsReturnButton: View {
    let onReturn: () -> Void

    var body: some View {
        Button(action: onReturn) {
            Label("返回并复现", systemImage: "arrow.uturn.backward")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.black)
                .frame(minHeight: 44)
                #if !os(macOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("返回刚才的页面，诊断记录会继续")
        #if os(macOS)
        .frame(minWidth: 160, alignment: .leading)
        #endif
    }
}

private struct SupportDiagnosticsReproductionGuidanceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SupportDiagnosticsGuidanceRow(
                icon: "arrow.uturn.backward",
                title: "返回原页面",
                detail: "按平时的方式重现问题。"
            )
            SupportDiagnosticsGuidanceRow(
                icon: "stop.fill",
                title: "回来结束记录",
                detail: "检查报告后，自行选择分享。"
            )
        }
    }
}

private struct SupportDiagnosticsGuidanceRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SupportDiagnosticsWhatIsRecordedView: View {
    var body: some View {
        DisclosureGroup("会记录哪些信息") {
            Text("会记录页面操作、插件调用和脱敏后的请求结果。报告会标记没有采集到的内容；分享前请检查自由文本中是否包含个人信息。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .font(.body)
        .tint(Color.primary)
    }
}
#endif

private struct SupportDiagnosticsSummaryView: View {
    let startedAt: Date
    let endedAt: Date
    let actionCount: Int
    let entryCount: Int
    let failureTitle: String?
    let failureMessage: String?
    let isErrorSnapshot: Bool
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("诊断报告已就绪")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    metadata
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16, alignment: .leading),
                        GridItem(.flexible(), spacing: nil, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 16
                ) {
                    metadata
                }
            }
            #else
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    metadata
                }
                VStack(alignment: .leading, spacing: 12) {
                    metadata
                }
            }
            #endif

            if isErrorSnapshot, let failureTitle, let failureMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前错误快照")
                        .font(.headline)
                    Text(failureTitle)
                        .font(.body.weight(.semibold))
                    Text(failureMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("这是未启动录制时保存的当前错误摘要；重新记录可以收集复现过程。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            if actionCount == 0 && entryCount == 0 {
                Text("未记录到复现过程。你可以重新记录，回到出现问题的页面操作一次。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if actionCount == 0 {
                Text("未记录到业务操作。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if entryCount == 0 {
                Text("未记录到插件调用或 HTTP 请求。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        Group {
            SupportDiagnosticsMetadataItem(title: "生成时间") {
                Text(endedAt, format: .dateTime.month().day().hour().minute())
            }
            SupportDiagnosticsMetadataItem(title: "记录时长") {
                Text(verbatim: SupportDiagnosticsDuration.text(endedAt.timeIntervalSince(startedAt)))
                    .monospacedDigit()
            }
            SupportDiagnosticsMetadataItem(title: "操作记录") {
                Text(actionCount, format: .number)
            }
            SupportDiagnosticsMetadataItem(title: "调用记录") {
                Text(entryCount, format: .number)
            }
        }
    }
}

private struct SupportDiagnosticsMetadataItem<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .font(.callout.weight(.medium))
                #if os(iOS)
                .fixedSize(horizontal: false, vertical: true)
                #endif
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        .frame(minWidth: 96, alignment: .leading)
        #endif
    }
}

private struct SupportDiagnosticsDescriptionEditor: View {
    @Binding var text: String
    let savedText: String
    let onSave: () -> Void

    private var isDirty: Bool { text != savedText }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("问题描述（选填）")
                .font(.headline)

            #if os(tvOS)
            TextField("补充发生时间、操作路径和实际现象", text: $text)
                .frame(minHeight: 56)
                .padding(.horizontal, 12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("问题描述")
            #else
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112, maxHeight: 160)
                    .padding(8)
                    .accessibilityLabel("问题描述")
                    .accessibilityHint("补充发生时间、操作路径和实际现象")

                if text.isEmpty {
                    Text("例如：进入直播后一直加载，重新打开后仍然如此。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            #endif

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: onSave) {
                    Label("保存补充", systemImage: "checkmark")
                        #if os(iOS)
                        .font(.subheadline)
                        #endif
                        .frame(minHeight: 44)
                        #if os(iOS)
                        .contentShape(Rectangle())
                        #endif
                }
                #if os(iOS)
                .buttonStyle(.plain)
                #else
                .buttonStyle(.bordered)
                #endif
                .disabled(!isDirty)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: LocalizedStringKey {
        if isDirty { return "有未保存的补充" }
        return text.isEmpty ? "可选补充" : "已保存"
    }
}

private struct SupportDiagnosticsReportPhase: View {
    let startedAt: Date
    let endedAt: Date
    let actionCount: Int
    let entryCount: Int
    let failureTitle: String?
    let failureMessage: String?
    let isErrorSnapshot: Bool
    @Binding var description: String
    let savedDescription: String
    let onSaveDescription: () -> Void
    let onOpenPreview: () -> Void
    let onRestart: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SupportDiagnosticsSummaryView(
                startedAt: startedAt,
                endedAt: endedAt,
                actionCount: actionCount,
                entryCount: entryCount,
                failureTitle: failureTitle,
                failureMessage: failureMessage,
                isErrorSnapshot: isErrorSnapshot
            )

            SupportDiagnosticsDescriptionEditor(
                text: $description,
                savedText: savedDescription,
                onSave: onSaveDescription
            )

            Button(action: onOpenPreview) {
                Label("检查并分享报告", systemImage: "doc.text.magnifyingglass")
                    #if os(iOS)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    #else
                    .frame(maxWidth: .infinity, minHeight: 44)
                    #endif
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                #if os(iOS)
                Button(action: onRestart) {
                    Text("重新记录")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onClear) {
                    Text("清除报告")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #else
                Button("重新记录", action: onRestart)
                    .frame(minHeight: 44)
                    .buttonStyle(.bordered)

                Button("清除报告", role: .destructive, action: onClear)
                    .frame(minHeight: 44)
                    .buttonStyle(.bordered)
                #endif
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

private struct SupportDiagnosticsReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let service: SupportDiagnosticsService

    @State private var exportedFileURL: URL?
    @State private var exportErrorMessage: String?
    @State private var notice: SupportDiagnosticsNotice?
    #if os(tvOS)
    @State private var reportSharingService = SupportReportSharingService()
    @State private var showLANShare = false
    @State private var previewSessionID: UUID?
    @FocusState private var focusedAction: SupportDiagnosticsTVFocus?

    init(service: SupportDiagnosticsService) {
        self.service = service
        _previewSessionID = State(initialValue: service.lastReport?.sessionID)
    }
    #endif

    private var canUseReport: Bool {
        #if os(tvOS)
        guard let reportSessionID = service.lastReport?.sessionID else { return false }
        return !service.isRecording && previewSessionID == reportSessionID
        #else
        service.lastReport != nil && !service.isRecording
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(tvOS)
                HStack(alignment: .top, spacing: 0) {
                    SupportDiagnosticsReportTextView(reportText: service.reportText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 90)
                        .containerRelativeFrame(
                            .horizontal,
                            count: 2,
                            span: 1,
                            spacing: 0
                        )
                    SupportDiagnosticsTVPreviewActionPanel(
                        reportSharingService: reportSharingService,
                        showLANShare: $showLANShare,
                        onStart: startLANShare,
                        onClose: closeLANShare,
                        onReturn: { dismiss() },
                        focusedAction: $focusedAction
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 50)
                    .containerRelativeFrame(
                        .horizontal,
                        count: 2,
                        span: 1,
                        spacing: 0
                    )
                }
                #else
                Text("报告会保存在本机。请检查脱敏后的完整内容，再选择复制、系统分享或导出文件。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SupportDiagnosticsReportTextView(reportText: service.reportText)

                #endif
            }
            #if os(tvOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 0)
            .padding(.vertical, 60)
            #else
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            #endif
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background {
            SupportDiagnosticsSystemBackground()
                .ignoresSafeArea()
        }
        #if !os(tvOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let notice {
                    SupportDiagnosticsNoticeView(notice: notice)
                }
                SupportDiagnosticsPreviewActions(
                    reportText: service.reportText,
                    exportedFileURL: exportedFileURL,
                    exportErrorMessage: exportErrorMessage,
                    onCopy: copyReport,
                    onRetryExport: prepareExport
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                SupportDiagnosticsSystemBackground()
                    .overlay(alignment: .top) { Divider() }
            }
        }
        #endif
        #if os(tvOS)
        .focusSection()
        .defaultFocus($focusedAction, .previewDownload)
        .onExitCommand {
            if showLANShare {
                closeLANShare()
            } else {
                dismiss()
            }
        }
        .onDisappear {
            showLANShare = false
            reportSharingService.stop()
        }
        #endif
        .disabled(!canUseReport)
        .navigationTitle("报告预览")
        #if os(tvOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SupportDiagnosticsTVNavigationTitle("报告预览")
            }
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard canUseReport else {
                dismissFromInvalidatedReport()
                return
            }
            #if os(tvOS)
            focusedAction = .previewDownload
            #endif
            #if !os(tvOS)
            if exportedFileURL == nil {
                prepareExport()
            }
            #endif
        }
        .onChange(of: service.reportText) { _, _ in
            exportedFileURL = nil
            exportErrorMessage = nil
            notice = nil
            #if os(tvOS)
            showLANShare = false
            reportSharingService.stop()
            #else
            if canUseReport { prepareExport() }
            #endif
        }
        .onChange(of: service.isRecording) { _, isRecording in
            guard isRecording else { return }
            dismissFromInvalidatedReport()
        }
        .onChange(of: service.lastReport?.sessionID) { _, newSessionID in
            #if os(tvOS)
            guard newSessionID == previewSessionID else {
                dismissFromInvalidatedReport()
                return
            }
            #else
            guard newSessionID != nil else {
                dismissFromInvalidatedReport()
                return
            }
            #endif
        }
    }

    private func copyReport() {
        guard canUseReport else { return }
        #if os(iOS)
        UIPasteboard.general.string = service.reportText
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(service.reportText, forType: .string) else {
            notice = .failure("无法复制报告，请重试。")
            return
        }
        #endif
        notice = .success("报告已复制。")
    }

    private func prepareExport() {
        guard canUseReport else { return }
        do {
            exportedFileURL = try service.exportReport()
            exportErrorMessage = nil
        } catch {
            exportedFileURL = nil
            exportErrorMessage = "无法导出报告：\(error.localizedDescription)"
        }
    }

    private func dismissFromInvalidatedReport() {
        #if os(tvOS)
        showLANShare = false
        reportSharingService.stop()
        #endif
        dismiss()
    }

    #if os(tvOS)
    private func startLANShare() {
        guard canUseReport else { return }
        showLANShare = true
        reportSharingService.start(reportText: service.reportText)
    }

    private func closeLANShare() {
        showLANShare = false
        reportSharingService.stop()
    }
    #endif
}

private struct SupportDiagnosticsReportTextView: View {
    let reportText: String

    var body: some View {
        #if os(tvOS)
        SupportDiagnosticsTVReportTextView(reportText: reportText)
            .frame(maxWidth: .infinity)
            .frame(height: 520, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("完整诊断报告文本")
        #else
        ScrollView(.vertical) {
            Text(verbatim: reportText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 520, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("完整诊断报告文本")
        #endif
    }
}

#if os(tvOS)
private struct SupportDiagnosticsTVReportTextView: UIViewRepresentable {
    let reportText: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = true
        textView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.indirect.rawValue)
        ]
        textView.backgroundColor = .clear
        textView.textColor = .label

        let baseFootnotePointSize = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        let footnoteFont = UIFont.monospacedSystemFont(
            ofSize: baseFootnotePointSize,
            weight: .regular
        )
        textView.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: footnoteFont)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.text = reportText
        textView.accessibilityLabel = "完整诊断报告文本"
        textView.accessibilityHint = "使用上下方向浏览文本，使用左右方向切换焦点"
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != reportText else { return }
        uiView.text = reportText
        uiView.setContentOffset(.zero, animated: false)
    }
}
#endif

private struct SupportDiagnosticsPreviewActions: View {
    let reportText: String
    let exportedFileURL: URL?
    let exportErrorMessage: String?
    let onCopy: () -> Void
    let onRetryExport: () -> Void

    var body: some View {
        #if os(iOS) || os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    shareTextButton
                    copyButton
                    if let exportedFileURL {
                        shareFileButton(exportedFileURL)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    shareTextButton
                    copyButton
                    if let exportedFileURL {
                        shareFileButton(exportedFileURL)
                    }
                }
            }

            exportError
        }
        #else
        EmptyView()
        #endif
    }

    #if os(iOS) || os(macOS)
    private var shareTextButton: some View {
        ShareLink(item: reportText) {
            Label("分享报告", systemImage: "square.and.arrow.up")
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            Label("复制", systemImage: "doc.on.doc")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func shareFileButton(_ url: URL) -> some View {
        ShareLink(item: url) {
            Label("分享文件", systemImage: "doc.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var exportError: some View {
        if let exportErrorMessage, !exportErrorMessage.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(exportErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                Button("重试导出", action: onRetryExport)
                    .frame(minHeight: 44)
                    .buttonStyle(.bordered)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif
}

private struct SupportDiagnosticsDuration {
    static func text(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let secondsText = seconds < 10 ? "0\(seconds)" : String(seconds)
        return "\(minutes):\(secondsText)"
    }

    static func accessibilityText(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        return "\(totalSeconds / 60) 分 \(totalSeconds % 60) 秒"
    }
}

#if os(tvOS)
private enum SupportDiagnosticsTVFocus: Hashable {
    case start
    case recordReturn
    case stop
    case reportPreview
    case reportDescription
    case reportRestart
    case reportClear
    case descriptionInput
    case descriptionSave
    case descriptionCancel
    case previewDownload
    case previewReturn
    case previewRetry
}

private struct SupportDiagnosticsTVCapturePhase: View {
    let startedAt: Date?
    let onStart: () -> Void
    let onReturn: () -> Void
    let onStop: () -> Void

    @FocusState private var focusedAction: SupportDiagnosticsTVFocus?

    private var isRecording: Bool {
        startedAt != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("记录一次问题")
                        .font(.largeTitle.weight(.semibold))

                    Text(
                        isRecording
                            ? "返回出现问题的页面，按平时的方式重现一次，完成后回来结束记录。离开此页不会停止记录。"
                            : "开始后，回到出现问题的页面，按平时的方式重现一次。完成后回来结束记录并检查报告。"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                SupportDiagnosticsTVRecordingStatus(startedAt: startedAt)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 90)
            .containerRelativeFrame(
                .horizontal,
                count: 2,
                span: 1,
                spacing: 0
            )

            VStack(alignment: .leading, spacing: 15) {
                SupportDiagnosticsTVOperationRow(
                    title: isRecording ? "结束记录" : "开始记录",
                    systemImage: isRecording ? "stop.fill" : "record.circle",
                    action: isRecording ? onStop : onStart,
                    focusedAction: $focusedAction,
                    focusTarget: isRecording ? .stop : .start,
                    accessibilityHint: isRecording ? "结束诊断记录并生成报告" : "开始诊断记录"
                )

                if isRecording {
                    SupportDiagnosticsTVOperationRow(
                        title: "返回并复现",
                        systemImage: "arrow.uturn.backward",
                        action: onReturn,
                        focusedAction: $focusedAction,
                        focusTarget: .recordReturn,
                        accessibilityHint: "返回刚才的页面，诊断记录会继续"
                    )
                }

                SupportDiagnosticsTVGuidanceView()
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 50)
            .containerRelativeFrame(
                .horizontal,
                count: 2,
                span: 1,
                spacing: 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus($focusedAction, isRecording ? .recordReturn : .start)
        .onAppear {
            focusedAction = isRecording ? .recordReturn : .start
        }
        .onChange(of: isRecording) { _, newValue in
            focusedAction = newValue ? .recordReturn : .start
        }
    }
}

private struct SupportDiagnosticsTVRecordingStatus: View {
    let startedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool {
        startedAt != nil
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt ?? context.date))

            VStack(alignment: .leading, spacing: 15) {
                Label(
                    isRecording ? "正在记录" : "准备记录",
                    systemImage: isRecording ? "record.circle.fill" : "doc.text.magnifyingglass"
                )
                .font(.headline)
                .foregroundStyle(isRecording ? .red : .primary)
                .accessibilityLabel(isRecording ? "正在记录诊断信息" : "准备记录诊断信息")

                durationText(elapsed)
                    .font(.system(.largeTitle, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.16),
                        value: SupportDiagnosticsDuration.text(elapsed)
                    )
                    .accessibilityLabel(
                        "已记录时长 \(SupportDiagnosticsDuration.accessibilityText(elapsed))"
                    )

                ProgressView(value: min(elapsed, 300), total: 300)
                    .progressViewStyle(.linear)
                    .tint(isRecording ? .red : .accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    .accessibilityLabel("五分钟记录上限进度")

                Text("最长 5 分钟 · 结束后生成报告")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func durationText(_ elapsed: TimeInterval) -> some View {
        let text = Text(verbatim: SupportDiagnosticsDuration.text(elapsed))
        if reduceMotion {
            text
        } else {
            text.contentTransition(.numericText())
        }
    }
}

private struct SupportDiagnosticsTVOperationRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    let focusedAction: FocusState<SupportDiagnosticsTVFocus?>.Binding
    let focusTarget: SupportDiagnosticsTVFocus
    let accessibilityHint: LocalizedStringKey

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Text(title)
                    .font(.body)
                Spacer(minLength: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
        }
        .focused(focusedAction, equals: focusTarget)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

private struct SupportDiagnosticsTVNavigationTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey = "问题诊断与反馈") {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.primary)
            .environment(\.colorScheme, .dark)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SupportDiagnosticsTVGuidanceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("接下来")
                .font(.headline)

            Text("返回出现问题的页面，按平时的方式重现；回来结束并查看报告。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("仅在本机保存")
                    .font(.headline)
                Text("页面操作 · 插件调用\n脱敏后的请求结果")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SupportDiagnosticsTVReportPhase: View {
    let startedAt: Date
    let endedAt: Date
    let sessionID: UUID
    let actionCount: Int
    let entryCount: Int
    let failureTitle: String?
    let failureMessage: String?
    let isErrorSnapshot: Bool
    @Binding var description: String
    let savedDescription: String
    let onSaveDescription: (String) -> String?
    let onOpenPreview: () -> Void
    let onRestart: () -> Void
    let onClear: () -> Void

    @FocusState private var focusedAction: SupportDiagnosticsTVFocus?
    @State private var isDescriptionEditorPresented = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                SupportDiagnosticsTVReportSummary(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    actionCount: actionCount,
                    entryCount: entryCount,
                    failureTitle: failureTitle,
                    failureMessage: failureMessage,
                    isErrorSnapshot: isErrorSnapshot
                )

                SupportDiagnosticsTVDescriptionSummary(
                    description: description,
                    savedDescription: savedDescription
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 90)
            .containerRelativeFrame(
                .horizontal,
                count: 2,
                span: 1,
                spacing: 0
            )

            VStack(alignment: .leading, spacing: 15) {
                SupportDiagnosticsTVOperationRow(
                    title: "检查并分享报告",
                    systemImage: "doc.text.magnifyingglass",
                    action: onOpenPreview,
                    focusedAction: $focusedAction,
                    focusTarget: .reportPreview,
                    accessibilityHint: "打开完整报告预览"
                )
                SupportDiagnosticsTVOperationRow(
                    title: description.isEmpty ? "补充问题描述" : "编辑问题描述",
                    systemImage: "pencil",
                    action: { isDescriptionEditorPresented = true },
                    focusedAction: $focusedAction,
                    focusTarget: .reportDescription,
                    accessibilityHint: "补充发生时间、操作路径和实际现象"
                )
                SupportDiagnosticsTVOperationRow(
                    title: "重新记录",
                    systemImage: "arrow.clockwise",
                    action: onRestart,
                    focusedAction: $focusedAction,
                    focusTarget: .reportRestart,
                    accessibilityHint: "重新开始一次诊断记录"
                )
                SupportDiagnosticsTVOperationRow(
                    title: "清除报告",
                    systemImage: "trash",
                    action: onClear,
                    focusedAction: $focusedAction,
                    focusTarget: .reportClear,
                    accessibilityHint: "清除本机保存的诊断报告"
                )

                Text("先检查内容，再自行分享。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 50)
            .containerRelativeFrame(
                .horizontal,
                count: 2,
                span: 1,
                spacing: 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus($focusedAction, .reportPreview)
        .onAppear {
            focusedAction = .reportPreview
        }
        .onChange(of: isDescriptionEditorPresented) { _, isPresented in
            if !isPresented {
                focusedAction = .reportDescription
            }
        }
        .fullScreenCover(isPresented: $isDescriptionEditorPresented) {
            SupportDiagnosticsTVDescriptionEditor(
                initialText: description,
                onSave: onSaveDescription
            )
            .id(sessionID)
        }
    }
}

private struct SupportDiagnosticsTVReportSummary: View {
    let startedAt: Date
    let endedAt: Date
    let actionCount: Int
    let entryCount: Int
    let failureTitle: String?
    let failureMessage: String?
    let isErrorSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("报告已生成")
                .font(.largeTitle.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 16) {
                GridRow {
                    SupportDiagnosticsTVMetadataItem(
                        title: "生成时间",
                        value: endedAt.formatted(.dateTime.month().day().hour().minute())
                    )
                    SupportDiagnosticsTVMetadataItem(
                        title: "记录时长",
                        value: SupportDiagnosticsDuration.text(endedAt.timeIntervalSince(startedAt))
                    )
                }
                GridRow {
                    SupportDiagnosticsTVMetadataItem(
                        title: "操作记录",
                        value: actionCount.formatted(.number)
                    )
                    SupportDiagnosticsTVMetadataItem(
                        title: "调用记录",
                        value: entryCount.formatted(.number)
                    )
                }
            }

            if isErrorSnapshot, let failureTitle, let failureMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前错误快照")
                        .font(.headline)
                    Text(failureTitle)
                        .font(.body.weight(.semibold))
                    Text(failureMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text("这是未启动录制时保存的当前错误摘要；重新记录可以收集复现过程。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if actionCount == 0 && entryCount == 0 {
                Text("未记录到复现过程。你可以重新记录，回到出现问题的页面操作一次。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if actionCount == 0 {
                Text("未记录到业务操作。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if entryCount == 0 {
                Text("未记录到插件调用或 HTTP 请求。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SupportDiagnosticsTVMetadataItem: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SupportDiagnosticsTVDescriptionSummary: View {
    let description: String
    let savedDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("问题描述")
                .font(.headline)
            Text(description.isEmpty ? "尚未补充" : description)
                .font(.body)
                .foregroundStyle(description.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if description != savedDescription {
                Text("有未保存的补充")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SupportDiagnosticsTVDescriptionEditor: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String) -> String?
    @State private var draft: String
    @State private var errorMessage: String?
    @FocusState private var focusedAction: SupportDiagnosticsTVFocus?

    init(initialText: String, onSave: @escaping (String) -> String?) {
        self.onSave = onSave
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("问题描述")
                            .font(.largeTitle.weight(.semibold))
                        Text("补充发生时间、操作路径和实际现象，帮助定位这次问题。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 90)
                    .containerRelativeFrame(
                        .horizontal,
                        count: 2,
                        span: 1,
                        spacing: 0
                    )

                    VStack(alignment: .leading, spacing: 15) {
                        TextField("补充发生时间、操作路径和实际现象", text: $draft)
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .focused($focusedAction, equals: .descriptionInput)
                            .accessibilityLabel("问题描述")

                        if let errorMessage, !errorMessage.isEmpty {
                            Label {
                                Text(errorMessage)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.red)
                        }

                        SupportDiagnosticsTVOperationRow(
                            title: "保存并返回",
                            systemImage: "checkmark",
                            action: saveDraft,
                            focusedAction: $focusedAction,
                            focusTarget: .descriptionSave,
                            accessibilityHint: "保存问题描述并返回报告"
                        )
                        SupportDiagnosticsTVOperationRow(
                            title: "取消",
                            systemImage: "xmark",
                            action: { dismiss() },
                            focusedAction: $focusedAction,
                            focusTarget: .descriptionCancel,
                            accessibilityHint: "放弃未保存的修改并返回报告"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 50)
                    .containerRelativeFrame(
                        .horizontal,
                        count: 2,
                        span: 1,
                        spacing: 0
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 60)
            }
            .background {
                SupportDiagnosticsSystemBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("问题描述")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SupportDiagnosticsTVNavigationTitle("问题描述")
                }
            }
        }
        .preferredColorScheme(.dark)
        .focusSection()
        .defaultFocus($focusedAction, .descriptionInput)
        .onAppear {
            focusedAction = .descriptionInput
        }
    }

    private func saveDraft() {
        if let errorMessage = onSave(draft), !errorMessage.isEmpty {
            self.errorMessage = errorMessage
            focusedAction = .descriptionSave
        } else {
            dismiss()
        }
    }
}

private struct SupportDiagnosticsTVPreviewActionPanel: View {
    let reportSharingService: SupportReportSharingService
    @Binding var showLANShare: Bool
    let onStart: () -> Void
    let onClose: () -> Void
    let onReturn: () -> Void
    let focusedAction: FocusState<SupportDiagnosticsTVFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if showLANShare {
                SupportDiagnosticsTVOperationRow(
                    title: "关闭手机下载",
                    systemImage: "xmark",
                    action: onClose,
                    focusedAction: focusedAction,
                    focusTarget: .previewDownload,
                    accessibilityHint: "关闭局域网手机下载"
                )
            } else {
                SupportDiagnosticsTVOperationRow(
                    title: "用手机下载报告",
                    systemImage: "qrcode",
                    action: onStart,
                    focusedAction: focusedAction,
                    focusTarget: .previewDownload,
                    accessibilityHint: "在同一局域网内扫码下载，链接五分钟后失效"
                )
            }

            SupportDiagnosticsTVOperationRow(
                title: "返回报告",
                systemImage: "arrow.uturn.backward",
                action: onReturn,
                focusedAction: focusedAction,
                focusTarget: .previewReturn,
                accessibilityHint: "返回诊断报告"
            )

            if showLANShare {
                SupportDiagnosticsTVLANShareDetail(reportSharingService: reportSharingService)
            }

            if showLANShare,
               let errorMessage = reportSharingService.errorMessage,
               !errorMessage.isEmpty,
               reportSharingService.downloadURL == nil {
                SupportDiagnosticsTVOperationRow(
                    title: "重试开启下载",
                    systemImage: "arrow.clockwise",
                    action: onStart,
                    focusedAction: focusedAction,
                    focusTarget: .previewRetry,
                    accessibilityHint: "重新开启局域网手机下载"
                )
            }
        }
    }
}

private struct SupportDiagnosticsTVLANShareDetail: View {
    let reportSharingService: SupportReportSharingService

    var body: some View {
        Group {
            if let downloadURL = reportSharingService.downloadURL {
                if let image = qrImage(for: downloadURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 280)
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("诊断报告下载二维码")
                }

                Text("手机与电视连接同一局域网，扫码下载；链接 5 分钟后失效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let errorMessage = reportSharingService.errorMessage, !errorMessage.isEmpty {
                Label {
                    Text(errorMessage)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            } else {
                ProgressView("正在准备局域网下载…")
                    .font(.callout)
                    .accessibilityLabel("正在准备局域网下载")
            }
        }
    }

    private func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return UIImage(ciImage: scaledImage)
    }
}
#endif

private struct SupportDiagnosticsCapturePreview: View {
    let startedAt: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    #if os(tvOS)
                    SupportDiagnosticsTVCapturePhase(
                        startedAt: startedAt,
                        onStart: {}, onReturn: {}, onStop: {}
                    )
                    .padding(.horizontal, 0)
                    .padding(.vertical, 60)
                    #else
                    SupportDiagnosticsCapturePhase(
                        startedAt: startedAt,
                        onStart: {}, onReturn: {}, onStop: {}
                    )
                    #if os(macOS)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    #else
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    #endif
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background { SupportDiagnosticsSystemBackground() }
            .navigationTitle("问题诊断与反馈")
            #if os(tvOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SupportDiagnosticsTVNavigationTitle()
                }
            }
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #endif
        #if os(macOS)
        .frame(width: 640, height: 560)
        #elseif os(tvOS)
        .frame(width: 1_920, height: 1_080)
        #endif
    }
}

#Preview("诊断待开始") {
    SupportDiagnosticsCapturePreview(startedAt: nil)
}

#Preview("诊断记录中") {
    SupportDiagnosticsCapturePreview(startedAt: Date(timeIntervalSinceNow: -37))
}

#if os(tvOS)
private struct SupportDiagnosticsTVReportPreview: View {
    @State private var description = "进入直播间后一直加载，重新打开后仍然如此。"

    var body: some View {
        NavigationStack {
            ScrollView {
                SupportDiagnosticsTVReportPhase(
                    startedAt: Date(timeIntervalSince1970: 1_758_200_000),
                    endedAt: Date(timeIntervalSince1970: 1_758_200_201),
                    sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    actionCount: 3,
                    entryCount: 5,
                    failureTitle: nil,
                    failureMessage: nil,
                    isErrorSnapshot: false,
                    description: $description,
                    savedDescription: description,
                    onSaveDescription: { _ in nil },
                    onOpenPreview: {},
                    onRestart: {},
                    onClear: {}
                )
                .padding(.vertical, 60)
            }
            .background {
                SupportDiagnosticsSystemBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("问题诊断与反馈")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SupportDiagnosticsTVNavigationTitle()
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(width: 1_920, height: 1_080)
    }
}

private struct SupportDiagnosticsTVDescriptionPreview: View {
    var body: some View {
        SupportDiagnosticsTVDescriptionEditor(
            initialText: "进入直播间后一直加载，重新打开后仍然如此。",
            onSave: { _ in nil }
        )
        .frame(width: 1_920, height: 1_080)
    }
}

#Preview("诊断报告") {
    SupportDiagnosticsTVReportPreview()
}

#Preview("问题描述编辑") {
    SupportDiagnosticsTVDescriptionPreview()
}
#endif
