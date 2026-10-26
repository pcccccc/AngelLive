//
//  FavoriteImportResultView.swift
//  AngelLiveCore
//
//  收藏导入结果页:三段式 summary 卡 + 失败明细列表。
//  用系统色和 .ultraThinMaterial,iOS/macOS 两端都能直接 sheet 出来。
//

import SwiftUI

public struct FavoriteImportResultView: View {
    @Environment(\.usesMacSettingsPresentation) private var usesSettingsPresentation
    public let report: FavoriteImportReport
    public var onDismiss: () -> Void

    public init(report: FavoriteImportReport, onDismiss: @escaping () -> Void) {
        self.report = report
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryRow

                    if report.hasFailures {
                        failureSection
                    } else {
                        successHint
                    }

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationTitle("导入结果")
            .macSettingsPage("导入结果", closeTitle: "完成")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !usesSettingsPresentation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", action: onDismiss)
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 12) {
            summaryTile(
                value: report.addedCount,
                title: "新增",
                tint: .green
            )
            summaryTile(
                value: report.skippedCount,
                title: "已存在",
                tint: .secondary
            )
            summaryTile(
                value: report.failedCount,
                title: "失败",
                tint: report.failedCount > 0 ? .red : .secondary
            )
        }
    }

    @ViewBuilder
    private func summaryTile(value: Int, title: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.title.bold())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Failure list

    private var failureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("失败明细")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(report.failed.enumerated()), id: \.element.id) { index, failure in
                    failureRow(failure)
                    if index < report.failed.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func failureRow(_ failure: FavoriteImportReport.Failure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(failure.userName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let siteId = failure.siteId, !siteId.isEmpty {
                    Text(platformDisplayName(for: siteId))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text(failure.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private func platformDisplayName(for siteId: String) -> String {
        if let liveType = LiveParseJSPlatformManager.liveType(forSiteId: siteId) {
            return LiveParseTools.getLivePlatformName(liveType)
        }
        return siteId
    }

    // MARK: - Success hint

    private var successHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(report.addedCount > 0
                 ? "导入完成,无失败条目"
                 : "未新增收藏(全部已存在或文件为空)")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
