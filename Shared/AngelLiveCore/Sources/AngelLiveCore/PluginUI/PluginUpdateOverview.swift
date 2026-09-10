import SwiftUI

/// Shared information hierarchy for FullUI plugin management. Platform hosts
/// own navigation, source editing, and tvOS App Group synchronization.
public struct PluginUpdateOverview: View {
    let manager: PluginSourceManager
    let installedPluginIds: [String]
    let update: ([String]) -> Void
    let check: () -> Void

    public init(
        manager: PluginSourceManager,
        installedPluginIds: [String],
        update: @escaping ([String]) -> Void,
        check: @escaping () -> Void
    ) {
        self.manager = manager
        self.installedPluginIds = installedPluginIds
        self.update = update
        self.check = check
    }

    public var body: some View {
        let batch = manager.updateBatch
        let candidates = installedPluginIds.filter { manager.hasUpdate(for: $0) }
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: batch.isRunning ? "arrow.down.circle" : "puzzlepiece.extension.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    PluginUpdateHeadline(batch: batch, candidateCount: candidates.count,
                                         installedCount: installedPluginIds.count,
                                         isChecking: manager.isFetchingIndex || manager.isCheckingUpdates,
                                         hasFailedSources: manager.sourceHealth.values.contains { $0.isFailed },
                                         hasSources: !manager.sourceURLs.isEmpty)
                        .font(.headline)
                    Text("已安装 \(installedPluginIds.count) 个 · \(manager.sourceURLs.count) 个订阅源", bundle: Bundle.main)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if batch.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(batch.completedCount), total: Double(max(1, batch.pluginIds.count)))
                    HStack {
                        if let id = batch.currentPluginId {
                            Text("正在更新 \(manager.managementDisplayName(for: id))", bundle: Bundle.main)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(batch.completedCount) / \(batch.pluginIds.count)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons(candidates: candidates) }
                VStack(alignment: .leading, spacing: 12) { buttons(candidates: candidates) }
            }
            #if os(tvOS)
            .focusSection()
            #endif

            if !batch.isRunning, !batch.failedPluginIds.isEmpty {
                PluginUpdateFailures(batch: batch, manager: manager)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func buttons(candidates: [String]) -> some View {
        Button {
            update(candidates)
        } label: {
            Label {
                if manager.updateBatch.isRunning {
                    Text("正在更新", bundle: Bundle.main)
                } else {
                    Text("全部更新", bundle: Bundle.main)
                }
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            #if os(iOS)
            .frame(minHeight: 28)
            #endif
        }
        .buttonStyle(.borderedProminent)
        #if os(tvOS)
        // Retain remote focus on the same button throughout the operation.
        .disabled(!manager.updateBatch.isRunning && (candidates.isEmpty || manager.isManagementBusy))
        #else
        .disabled(candidates.isEmpty || manager.isManagementBusy)
        #endif
        .accessibilityIdentifier("plugins.updateAll")

        if !manager.updateBatch.failedPluginIds.isEmpty && !manager.updateBatch.isRunning {
            Button { update(manager.updateBatch.failedPluginIds) } label: {
                Text("重试失败项", bundle: Bundle.main)
            }
            .buttonStyle(.bordered)
            .disabled(manager.isManagementBusy)
        }

        Button(action: check) {
            Label("检查更新", systemImage: "arrow.clockwise")
                #if os(iOS)
                .frame(minHeight: 28)
                #endif
        }
        .buttonStyle(.bordered)
        .disabled(manager.sourceURLs.isEmpty || manager.isManagementBusy)
        .accessibilityIdentifier("plugins.checkUpdates")
    }
}

public struct PluginManagementOperationError: View {
    let manager: PluginSourceManager

    public init(manager: PluginSourceManager) { self.manager = manager }

    public var body: some View {
        if let message = manager.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                PluginSourceErrorCard(title: "操作未完成", message: message)
                Button { manager.errorMessage = nil } label: {
                    Text("关闭提示", bundle: .main)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct PluginUpdateHeadline: View {
    let batch: PluginUpdateBatch
    let candidateCount: Int
    let installedCount: Int
    let isChecking: Bool
    let hasFailedSources: Bool
    let hasSources: Bool

    var body: some View {
        if batch.isRunning {
            Text("正在更新插件", bundle: Bundle.main)
        } else if !batch.pluginIds.isEmpty {
            if !batch.failedPluginIds.isEmpty {
                Text("\(batch.successCount) 个已更新，\(batch.failedPluginIds.count) 个失败", bundle: Bundle.main)
            } else if batch.outcomes.values.contains(.cancelled) {
                Text("更新已停止，\(batch.successCount) 个已完成", bundle: Bundle.main)
            } else {
                Text("已更新 \(batch.successCount) 个插件", bundle: Bundle.main)
            }
        } else if isChecking {
            Text("正在检查更新…", bundle: Bundle.main)
        } else if candidateCount > 0 {
            Text("\(candidateCount) 个插件可更新", bundle: Bundle.main)
        } else if installedCount == 0 {
            Text("添加你需要的插件", bundle: Bundle.main)
        } else if hasFailedSources {
            Text("部分订阅源未能检查", bundle: Bundle.main)
        } else if !hasSources {
            Text("添加订阅源以获取更新", bundle: Bundle.main)
        } else {
            Text("插件均为最新版本", bundle: Bundle.main)
        }
    }
}

private struct PluginUpdateFailures: View {
    let batch: PluginUpdateBatch
    let manager: PluginSourceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(batch.failedPluginIds, id: \.self) { id in
                if case .failed(let reason) = batch.outcomes[id] {
                    Label {
                        Text("\(manager.managementDisplayName(for: id))：\(reason)", bundle: Bundle.main)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension PluginSourceManager {
    @MainActor public func isWaitingForUpdate(for pluginId: String) -> Bool {
        updateBatch.isRunning && updateBatch.pluginIds.contains(pluginId) &&
        updateBatch.currentPluginId != pluginId && updateBatch.outcomes[pluginId] == nil
    }

    @MainActor public func managementActionState(
        for pluginId: String, remote: RemotePluginDisplayItem?
    ) -> RemotePluginCatalogActionState {
        if updateBatch.isRunning, let result = updateBatch.outcomes[pluginId] {
            switch result {
            case .updated: return .installed
            case .failed(let reason): return .failed(reason)
            case .cancelled: break
            }
        }
        if updatingPluginIds.contains(pluginId) { return .updating }
        if hasUpdate(for: pluginId), case .failed(let reason) = updateBatch.outcomes[pluginId] {
            return .failed(reason)
        }
        if let remote { return catalogActionState(for: remote) }
        return hasUpdate(for: pluginId) ? .update : .installed
    }

    public func managementDisplayName(for pluginId: String) -> String {
        let remoteName = latestRemoteItemsByPluginId[pluginId]?.platformName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !remoteName.isEmpty { return remoteName }
        return LiveParseJSPlatformManager.availablePlatforms.first(where: { $0.pluginId == pluginId })?.displayName ?? pluginId
    }
}
