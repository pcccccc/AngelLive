import SwiftUI
import AngelLiveCore
import Observation

@MainActor
@Observable
private final class PluginSourceRemovalOperation {
    private(set) var isRemoving = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func remove(_ url: String, includesPlugins: Bool, manager: PluginSourceManager, availability: PluginAvailabilityService, finished: @escaping @MainActor @Sendable () -> Void) {
        guard !isRemoving, !manager.isManagementBusy, manager.commitPendingUninstall() else { return }
        isRemoving = true
        manager.errorMessage = nil
        task = Task {
            defer { isRemoving = false; task = nil }
            if includesPlugins { await manager.removeSourceAndAssociatedPlugins(url) }
            else { manager.removeSource(url) }
            // Removal is already persisted; reconcile availability even if the page closes.
            await availability.refresh()
            guard !Task.isCancelled else { return }
            let removalError = manager.errorMessage
            await manager.fetchAllSourceIndexes()
            await manager.refreshAvailableUpdates()
            if let removalError { manager.errorMessage = removalError }
            guard !Task.isCancelled else { return }
            if manager.errorMessage == nil, !manager.sourceURLs.contains(url) { finished() }
        }
    }

    func cancel() { task?.cancel() }
}

struct PluginSourceListView: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var playlists = PlaylistInstanceStore.shared.all()
    @State private var statuses: [UUID: PlaylistRefreshStatus] = [:]
    @State private var removalURL: String?
    @State private var addedURLs: [String]?
    @State private var removalOperation = PluginSourceRemovalOperation()
    private var hasAnySource: Bool { !manager.sourceURLs.isEmpty || !playlists.isEmpty }

    var body: some View {
        let separatorTrailingInset = PluginManagementLayout.contentInset
        return List {
            if !hasAnySource {
                PluginManagementEmptyState(title: "暂无来源", message: "添加插件来源或 m3u 播放列表。")
                    .listRowInsets(PluginManagementLayout.zeroInsets)
            }
            if hasAnySource {
                Section {
                    if manager.sourceURLs.isEmpty {
                        PluginManagementEmptyState(title: "暂无插件来源", message: "添加插件来源后，可以浏览和安装其中的插件。")
                            .listRowInsets(PluginManagementLayout.zeroInsets)
                    }
                    ForEach(manager.sourceURLs, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink {
                                PluginSourceDetailView(sourceURL: url)
                            } label: {
                                PluginSourceRow(sourceURL: url, health: manager.health(for: url))
                            }
                            if removalURL == url {
                                PluginSourceRemovalPanel(sourceURL: url, operation: removalOperation, cancel: { removalURL = nil }, removed: { removalURL = nil })
                            }
                        }
                        .listRowInsets(EdgeInsets(top: PluginManagementLayout.itemSpacing, leading: PluginManagementLayout.contentInset, bottom: PluginManagementLayout.itemSpacing, trailing: PluginManagementLayout.contentInset))
                        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width + separatorTrailingInset }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { removalURL = url } label: { Label("删除", systemImage: "trash") }
                                .tint(.red).disabled(manager.isManagementBusy)
                        }
                        .accessibilityAction(named: Text("删除来源")) { removalURL = url }
                    }
                } header: { PluginManagementSectionHeading(title: "插件来源") }
                .listRowInsets(PluginManagementLayout.zeroInsets)
                Section {
                    if playlists.isEmpty {
                        PluginManagementEmptyState(title: "暂无 m3u 播放列表", message: "添加 m3u 播放列表地址后，这里会显示播放列表。")
                            .listRowInsets(PluginManagementLayout.zeroInsets)
                    }
                    ForEach(playlists) { instance in
                        NavigationLink { PlaylistEditorView(mode: .edit(instance)) } label: {
                            HStack(spacing: 12) {
                                PluginManagementToolIcon(symbol: "list.bullet", color: .orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(instance.name).foregroundStyle(.primary)
                                    Text(pluginSourceHost(instance.sourceURL)).font(.footnote).foregroundStyle(.secondary)
                                    if let status = statuses[instance.id] {
                                        if let error = status.lastErrorMessage {
                                            Text(SupportDiagnosticSanitizer.text(error)).font(.footnote).foregroundStyle(.orange)
                                        } else if let count = status.channelCount {
                                            Text("\(count) 个频道").font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: PluginManagementLayout.itemSpacing, leading: PluginManagementLayout.contentInset, bottom: PluginManagementLayout.itemSpacing, trailing: PluginManagementLayout.contentInset))
                        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width + separatorTrailingInset }
                    }
                } header: { PluginManagementSectionHeading(title: "m3u 播放列表") }
                .listRowInsets(PluginManagementLayout.zeroInsets)
            }
            if let error = manager.errorMessage {
                Section { FullUIPluginSourceErrorCard(title: "操作未完成", message: error) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(PluginManagementLayout.sectionSpacing)
        .contentMargins(.horizontal, PluginManagementLayout.pageInset, for: .scrollContent)
        .contentMargins(.top, PluginManagementLayout.itemSpacing, for: .scrollContent)
        .tint(PluginManagementLayout.primaryAction)
        .navigationTitle("来源").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加来源", systemImage: "plus") { showAdd = true }.disabled(manager.isManagementBusy)
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack { PluginSourceAddView { urls in addedURLs = urls } }
        }
        .navigationDestination(item: $addedURLs) { urls in PluginManagementView(entry: .sources(urls)) }
        .task(id: playlists.map(\.id)) {
            var result: [UUID: PlaylistRefreshStatus] = [:]
            for instance in playlists {
                guard !Task.isCancelled else { return }
                result[instance.id] = await PlaylistPlatformService.shared.status(instanceID: instance.id)
            }
            guard !Task.isCancelled else { return }
            statuses = result
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in playlists = PlaylistInstanceStore.shared.all() }
        .onDisappear { removalOperation.cancel() }
    }
}

private struct PluginSourceRow: View {
    let sourceURL: String
    let health: PluginSourceHealth
    var body: some View {
        HStack(spacing: PluginManagementLayout.iconTextSpacing) {
            PluginManagementToolIcon(symbol: "link", color: .blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(pluginSourceHost(sourceURL)).font(.body).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceURL).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                PluginSourceHealthLabel(health: health)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}

private struct PluginSourceDetailView: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    let sourceURL: String
    @State private var refreshing = false
    @State private var confirmingRemoval = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var removalOperation = PluginSourceRemovalOperation()
    var body: some View {
        List {
            Section {
                PluginSourceRow(sourceURL: sourceURL, health: manager.health(for: sourceURL))
                Text(sourceURL).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let reason) = manager.health(for: sourceURL) {
                    FullUIPluginSourceErrorCard(title: "来源异常", message: reason)
                }
                Button { refresh() } label: {
                    HStack {
                        Label(refreshing ? "正在刷新…" : "刷新来源", systemImage: "arrow.clockwise")
                        Spacer()
                        if refreshing { ProgressView() }
                    }.frame(minHeight: 44)
                }.disabled(manager.isManagementBusy || refreshing)
            }
            Section {
                if confirmingRemoval {
                    PluginSourceRemovalPanel(sourceURL: sourceURL, operation: removalOperation, cancel: { confirmingRemoval = false }, removed: { dismiss() })
                } else {
                    Button("删除来源", role: .destructive) { confirmingRemoval = true }.disabled(manager.isManagementBusy)
                }
            }
            if let error = manager.errorMessage {
                Section { FullUIPluginSourceErrorCard(title: "操作未完成", message: error) }
            }
        }.listStyle(.insetGrouped)
            .listSectionSpacing(PluginManagementLayout.sectionSpacing)
            .contentMargins(.horizontal, PluginManagementLayout.pageInset, for: .scrollContent)
            .tint(PluginManagementLayout.primaryAction)
            .navigationTitle("来源详情").navigationBarTitleDisplayMode(.inline)
            .onDisappear { refreshTask?.cancel(); refreshTask = nil; removalOperation.cancel() }
    }
    private func refresh() {
        guard !manager.isManagementBusy, !refreshing else { return }
        guard manager.commitPendingUninstall() else { return }
        refreshing = true
        refreshTask = Task {
            defer { refreshing = false }
            _ = await manager.refreshSource(sourceURL)
            guard !Task.isCancelled else { return }
            await manager.fetchAllSourceIndexes(); await manager.refreshAvailableUpdates()
        }
    }
}

private struct PluginSourceRemovalPanel: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    let sourceURL: String
    let operation: PluginSourceRemovalOperation
    let cancel: () -> Void
    let removed: @MainActor @Sendable () -> Void
    @State private var removePlugins = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("删除「\(pluginSourceHost(sourceURL))」？").font(.headline)
            Text(sourceURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Toggle("同时卸载仅由此来源提供的插件", isOn: $removePlugins).font(.subheadline)
            Text("其他来源也提供的插件会保留。").font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("取消", action: cancel).buttonStyle(.bordered)
                Button(operation.isRemoving ? "正在删除…" : "删除", role: .destructive) {
                    operation.remove(sourceURL, includesPlugins: removePlugins, manager: manager, availability: availability, finished: removed)
                }
                    .buttonStyle(.borderedProminent).tint(.red)
            }.controlSize(.large).buttonBorderShape(.capsule)
            if let error = manager.errorMessage { FullUIPluginSourceErrorCard(title: "删除未完成", message: error) }
        }.padding(.vertical, 8).disabled(manager.isManagementBusy || operation.isRemoving)
    }
}
