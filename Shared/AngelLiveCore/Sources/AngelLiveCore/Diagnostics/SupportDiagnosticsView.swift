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
    /// Hosts opt into showing support diagnostics in their FullUI surface.
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

/// Records a user-controlled support session and presents its local report.
///
/// The view deliberately does not own a navigation container. Hosts can put it in
/// a `NavigationStack`, sheet, or full-screen cover while preserving their platform
/// presentation and dismissal behavior.
@MainActor
public struct SupportDiagnosticsView: View {
    @State private var service = SupportDiagnosticsService.shared
    @State private var description: String
    @State private var exportedFileURL: URL?
    @State private var exportErrorMessage: String?
    @State private var showDiscardConfirmation = false
    #if os(tvOS)
    @State private var reportSharingService = SupportReportSharingService()
    #endif

    public init() {
        _description = State(initialValue: SupportDiagnosticsService.shared.lastReport?.userDescription ?? "")
    }

    private var hasReport: Bool {
        service.lastReport != nil
    }

    private var canUseReport: Bool {
        hasReport && !service.isRecording
    }

    public var body: some View {
        platformContent
            .navigationTitle("问题诊断与反馈")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                syncDescriptionFromReport()
            }
            .onChange(of: service.reportText) { _, _ in
                // A newly generated report or an edited supplement invalidates a
                // previously exported file. The tvOS LAN share is tied to the
                // same snapshot and must be closed as well.
                exportedFileURL = nil
                exportErrorMessage = nil
                syncDescriptionFromReport()
                #if os(tvOS)
                reportSharingService.stop()
                #endif
            }
            .alert("确认清除报告？", isPresented: $showDiscardConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    service.discardReport()
                    description = ""
                    exportedFileURL = nil
                    exportErrorMessage = nil
                }
            } message: {
                Text("清除后，本机保存的诊断报告将被删除。")
            }
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(tvOS)
        tvOSContent
        #elseif os(macOS)
        Form {
            diagnosticSections
        }
        .formStyle(.grouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        #else
        List {
            diagnosticSections
        }
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private var diagnosticSections: some View {
        recordingOverviewSection
        recordingActionsSection
        reproductionSection
        userDescriptionSection
        reportPreviewSection
        sharingSection
    }

    private var recordingOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("问题诊断", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("录制期间会收集应用内操作、插件原始错误，以及请求与响应（脱敏后），每次最长 5 分钟，服务会自动停止。停止后在本机生成报告。报告不会自动上传；分享前请先检查下方预览。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if service.isRecording {
                    recordingStatus
                    if hasReport {
                        Text("上次报告会在本次录制完成后替换；录制期间暂不显示或分享。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if hasReport {
                    Label("已生成诊断报告", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("已生成诊断报告")
                } else {
                    Text("先开始记录，再返回出现问题的页面操作，完成后回来停止并预览。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = service.errorMessage, !errorMessage.isEmpty {
                    Label {
                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("诊断错误：\(errorMessage)")
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("报告会隐藏常见凭证。分享前请检查是否包含个人信息。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("正在录制", systemImage: "record.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("正在录制诊断信息")

            if let startedAt = service.startedAt {
                Text("开始于 \(startedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recordingActionsSection: some View {
        Section("录制") {
            if service.isRecording {
                Button {
                    exportedFileURL = nil
                    exportErrorMessage = nil
                    #if os(tvOS)
                    reportSharingService.stop()
                    #endif
                    service.stopRecording()
                } label: {
                    Label("停止并生成报告", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .tint(.red)
                .accessibilityLabel("停止录制并生成报告")
            } else {
                Button {
                    exportedFileURL = nil
                    exportErrorMessage = nil
                    #if os(tvOS)
                    reportSharingService.stop()
                    #endif
                    service.startRecording()
                } label: {
                    Label("开始记录", systemImage: "record.circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("开始记录诊断信息")
            }
        }
    }

    private var reproductionSection: some View {
        Section("复现步骤") {
            VStack(alignment: .leading, spacing: 8) {
                reproductionStep("1", "点按“开始记录”。")
                reproductionStep("2", "返回出现问题的页面，按平时的路径操作并复现问题。")
                reproductionStep("3", "回到这里点按“停止并生成报告”，检查报告预览。")
            }
        }
    }

    private func reproductionStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var userDescriptionSection: some View {
        Section("用户补充") {
            if canUseReport {
                #if os(tvOS)
                TextField("补充出现问题的时间、操作和现象", text: $description)
                    .frame(minHeight: 44)
                    .accessibilityLabel("用户补充")
                #else
                TextEditor(text: $description)
                    .frame(minHeight: 100)
                    .accessibilityLabel("用户补充")
                #endif

                Button {
                    service.updateDescription(description)
                    exportedFileURL = nil
                    exportErrorMessage = nil
                } label: {
                    Label("保存补充", systemImage: "square.and.arrow.down")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("保存用户补充")
            } else if service.isRecording {
                Text("本次录制完成后可以补充复现时间、操作路径和看到的现象。上次报告在录制期间暂不编辑。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("生成报告后可以补充复现时间、操作路径和看到的现象。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reportPreviewSection: some View {
        Section("报告预览") {
            if canUseReport {
                ScrollView([.horizontal, .vertical]) {
                    Text(service.reportText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.primary)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .fixedSize()
                        .padding(12)
                        #if os(tvOS)
                        .focusable()
                        #endif
                }
                #if os(tvOS)
                .focusSection()
                #endif
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("诊断报告预览")
            } else if service.isRecording {
                Text("正在记录新的诊断信息。上次报告在本次录制期间暂不显示；停止后会显示新报告。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("停止录制后，完整报告会显示在这里。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sharingSection: some View {
        Section("复制、分享与清除") {
            if canUseReport {
                #if os(iOS)
                Button {
                    copyReportToPasteboard()
                } label: {
                    Label("复制报告", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                ShareLink(item: service.reportText) {
                    Label("分享文本", systemImage: "text.quote")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                Button {
                    prepareExport()
                } label: {
                    Label("导出文件并准备分享", systemImage: "doc.badge.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                if let exportedFileURL {
                    ShareLink(item: exportedFileURL) {
                        Label("分享报告文件", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                #elseif os(macOS)
                Button {
                    copyReportToPasteboard()
                } label: {
                    Label("复制报告", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                Button {
                    prepareExport()
                } label: {
                    Label("导出文件并准备分享", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                ShareLink(item: service.reportText) {
                    Label("分享文本", systemImage: "text.quote")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                if let exportedFileURL {
                    ShareLink(item: exportedFileURL) {
                        Label("分享报告文件", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                #else
                tvOSReportSharing
                #endif

                if let exportErrorMessage, !exportErrorMessage.isEmpty {
                    Label(exportErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("清除报告", role: .destructive) {
                    showDiscardConfirmation = true
                }
                .accessibilityLabel("清除本机诊断报告")
            } else if service.isRecording {
                Text("停止录制后可以复制、分享或清除新报告。上次报告在本次录制期间不可分享。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("生成报告后可以复制、分享或清除本机报告。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if os(tvOS)
    private var tvOSContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                diagnosticSections
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 48)
            .frame(maxWidth: 1_200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .focusSection()
        .scrollClipDisabled()
        .onChange(of: service.reportText) { _, _ in
            reportSharingService.stop()
        }
        .onDisappear {
            reportSharingService.stop()
        }
    }

    private var tvOSReportSharing: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                reportSharingService.start(reportText: service.reportText)
            } label: {
                Label("用手机下载报告", systemImage: "qrcode")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityLabel("用手机下载完整诊断报告")
            .accessibilityHint("在同一局域网内扫码下载，链接五分钟后失效")

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

                Text("手机与电视连接同一局域网，扫码下载；链接5分钟后失效")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = reportSharingService.errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            reportSharingService.stop()
        }
    }

    private func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return UIImage(ciImage: scaledImage)
    }
    #endif

    private func syncDescriptionFromReport() {
        description = service.lastReport?.userDescription ?? ""
    }

    private func prepareExport() {
        do {
            exportedFileURL = try service.exportReport()
            exportErrorMessage = nil
        } catch {
            exportedFileURL = nil
            exportErrorMessage = "无法导出报告：\(error.localizedDescription)"
        }
    }

    #if os(iOS)
    private func copyReportToPasteboard() {
        UIPasteboard.general.string = service.reportText
    }
    #elseif os(macOS)
    private func copyReportToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.reportText, forType: .string)
    }
    #endif
}
