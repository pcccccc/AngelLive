import SwiftUI
import AngelLiveCore

// MARK: - m3u playlists

/// 播放列表增删改后刷新平台目录（平台标签与网格依赖 catalogRevision）。
@MainActor
private func refreshPlatformCatalog(_ availability: PluginAvailabilityService) async {
    await availability.checkAvailability()
}

/// 已安装插件平台的名称，播放列表不得与之重名。
private func reservedPlatformNames() -> Set<String> {
    Set(LiveParseJSPlatformManager.availablePlatforms
        .filter { !PlaylistPlatformIdentity.isPlaylist($0.pluginId) }
        .map(\.displayName))
}

private struct PlaylistIconView: View {
    let name: String
    let fileURL: URL?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let fileURL, let image = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text(PlaylistIconCache.monogram(for: name))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct PlaylistListRow: View {
    let instance: PlaylistInstance
    let status: PlaylistRefreshStatus?

    /// 结构与插件订阅源行一致：标题 / 地址 / 状态三行。
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(instance.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("m3u 播放列表 · " + pluginSourceHost(instance.sourceURL))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 5) {
                // 图标与颜色沿用插件订阅源的健康状态标签。
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        if status?.lastErrorMessage != nil { return "exclamationmark.triangle" }
        return status?.channelCount == nil ? "questionmark.circle" : "checkmark.circle"
    }

    private var statusColor: Color {
        if status?.lastErrorMessage != nil { return .orange }
        return status?.channelCount == nil ? .secondary : .green
    }

    private var summary: String {
        if let error = status?.lastErrorMessage {
            return status?.fetchedAt == nil ? error : "刷新失败，正在使用上次的数据"
        }
        var parts: [String] = []
        if let count = status?.channelCount { parts.append("\(count) 个频道") }
        if let fetchedAt = status?.fetchedAt {
            parts.append(PlaylistIconCache.updatedText(fetchedAt))
        }
        return parts.isEmpty ? "尚未加载" : parts.joined(separator: " · ")
    }
}

/// 添加或编辑播放列表。添加前必须解析成功；名称必填，图标可选。
struct PlaylistEditorView: View {
    enum Mode {
        case add(sourceURL: String)
        case edit(PlaylistInstance)
    }

    enum IconState: Equatable {
        case none, loading, loaded, failed
    }

    let mode: Mode
    var onFinished: () -> Void = {}

    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(\.dismiss) private var dismiss

    @State private var sourceURL: String
    @State private var name: String
    @State private var iconURL: String
    @State private var preview: PlaylistPreview?
    @State private var previewError: String?
    @State private var isLoadingPreview = false
    @State private var iconState: IconState = .none
    @State private var isSaving = false
    @State private var isRefreshing = false
    @State private var saveError: String?
    @State private var status: PlaylistRefreshStatus?
    @State private var actionTask: Task<Void, Never>?

    init(mode: Mode, onFinished: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinished = onFinished
        switch mode {
        case .add(let sourceURL):
            _sourceURL = State(initialValue: sourceURL)
            _name = State(initialValue: "")
            _iconURL = State(initialValue: "")
        case .edit(let instance):
            _sourceURL = State(initialValue: instance.sourceURL)
            _name = State(initialValue: instance.name)
            _iconURL = State(initialValue: instance.iconURL ?? "")
        }
    }

    private var editingInstance: PlaylistInstance? {
        if case .edit(let instance) = mode { return instance }
        return nil
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedIcon: String { iconURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSource: String { sourceURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 编辑时只有地址变化才需要重新解析。
    private var sourceChanged: Bool {
        guard let editingInstance else { return true }
        return trimmedSource != editingInstance.sourceURL
    }

    private var hasChanges: Bool {
        guard let editingInstance else { return true }
        return trimmedName != editingInstance.name
            || trimmedIcon != (editingInstance.iconURL ?? "")
            || sourceChanged
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges && !isSaving && !isRefreshing && !isLoadingPreview
            && (!sourceChanged || preview != nil)
    }

    private var iconFileURL: URL? {
        guard !trimmedIcon.isEmpty, iconState == .loaded else { return nil }
        let probe = PlaylistInstance(name: trimmedName, iconURL: trimmedIcon, sourceURL: trimmedSource)
        return PlaylistIconCache.cachedFileURL(for: probe)
    }

    var body: some View {
        Form {
            Section {
                PlaylistIconHeader(
                    name: trimmedName.isEmpty ? (preview?.title ?? "播放列表") : trimmedName,
                    iconFileURL: iconFileURL,
                    summary: previewSummary,
                    isLoading: isLoadingPreview
                )
            }

            Section {
                TextField("https://", text: $sourceURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await loadPreview() } }
                if let previewError {
                    FullUIPluginSourceErrorCard(title: "无法读取播放列表", message: previewError)
                    Button("重试", systemImage: "arrow.clockwise") {
                        Task { await loadPreview() }
                    }
                    .disabled(isLoadingPreview)
                }
            } header: {
                Text("地址")
            }

            Section {
                TextField("例如:我的电视", text: $name)
                    .submitLabel(.next)
            } header: {
                Text("平台名称")
            } footer: {
                if trimmedName.isEmpty {
                    Text("必填,将显示在平台列表中。")
                }
            }

            Section {
                TextField("https://", text: $iconURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("图标地址(可选)")
            } footer: {
                Text(iconFooter)
            }

            if let saveError {
                Section {
                    FullUIPluginSourceErrorCard(title: "无法保存", message: saveError)
                }
            }

            if let editingInstance {
                Section {
                    Button {
                        refresh(editingInstance)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(isRefreshing ? "正在刷新…" : "刷新播放列表")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            if isRefreshing {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing || isSaving)
                }

                Section {
                    PluginInlineRemoval(title: "删除播放列表", message: "将删除「\(editingInstance.name)」，相关收藏和观看历史将无法播放。", confirmationTitle: "删除", disabled: isSaving, remove: delete)
                } footer: {
                    Text("删除后，该平台下的收藏和观看历史将无法播放。")
                }
            } else {
                Section {
                } footer: {
                    Text("内容由你添加的播放列表提供。")
                }
            }
        }
        .navigationTitle(editingInstance == nil ? "添加播放列表" : "播放列表详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editingInstance == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editingInstance == nil ? "添加" : "保存") { save() }
                    .disabled(!canSave)
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task {
            if editingInstance == nil {
                await loadPreview()
            } else if let editingInstance {
                status = await PlaylistPlatformService.shared.status(instanceID: editingInstance.id)
            }
        }
        .task(id: trimmedIcon) { await loadIcon() }
        .onChange(of: sourceURL) { _, _ in
            preview = nil
            previewError = nil
        }
        .onDisappear { actionTask?.cancel() }
    }

    private var previewSummary: String {
        if isLoadingPreview { return "正在读取播放列表…" }
        if let preview { return "\(preview.channelCount) 个频道 · \(preview.groupCount) 个分组" }
        if let status, let count = status.channelCount {
            var text = "\(count) 个频道"
            if let fetchedAt = status.fetchedAt {
                text += " · " + PlaylistIconCache.updatedText(fetchedAt)
            }
            return text
        }
        if previewError != nil { return "未能读取播放列表" }
        return pluginSourceHost(trimmedSource)
    }

    private var iconFooter: String {
        switch iconState {
        case .failed: "图标无法加载，将使用默认图标。"
        case .loading: "正在加载图标…"
        default: "留空时使用名称首字作为图标。"
        }
    }

    // MARK: Actions

    private func loadPreview() async {
        guard !trimmedSource.isEmpty else { return }
        let requestedSource = trimmedSource
        isLoadingPreview = true
        previewError = nil
        defer { isLoadingPreview = false }
        do {
            let loaded = try await PlaylistPlatformService.shared.preview(sourceURL: requestedSource)
            guard !Task.isCancelled, requestedSource == trimmedSource else { return }
            preview = loaded
        } catch {
            guard !Task.isCancelled, requestedSource == trimmedSource else { return }
            preview = nil
            previewError = PlaylistPlatformService.userMessage(for: error)
        }
    }

    private func loadIcon() async {
        guard !trimmedIcon.isEmpty else {
            iconState = .none
            return
        }
        iconState = .loading
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let requestedIcon = trimmedIcon
        let fetched = await PlaylistIconCache.fetch(iconURL: requestedIcon)
        guard !Task.isCancelled, requestedIcon == trimmedIcon else { return }
        iconState = fetched ? .loaded : .failed
    }

    private func save() {
        guard canSave, pluginSourceManager.commitPendingUninstall() else { return }
        saveError = nil
        isSaving = true
        actionTask = Task {
            defer { isSaving = false }
            if sourceChanged, preview == nil {
                await loadPreview()
                guard preview != nil else { return }
            }
            guard !Task.isCancelled else { return }
            do {
                let store = PlaylistInstanceStore.shared
                let instance: PlaylistInstance
                if let editingInstance {
                    instance = try store.update(
                        id: editingInstance.id,
                        name: trimmedName,
                        iconURL: trimmedIcon,
                        sourceURL: trimmedSource,
                        reservedNames: reservedPlatformNames()
                    )
                } else {
                    instance = try store.add(
                        name: trimmedName,
                        iconURL: trimmedIcon,
                        sourceURL: trimmedSource,
                        reservedNames: reservedPlatformNames()
                    )
                }
                if sourceChanged, let preview {
                    await PlaylistPlatformService.shared.seed(preview, for: instance)
                }
                await refreshPlatformCatalog(pluginAvailability)
                guard !Task.isCancelled else { return }
                onFinished()
                dismiss()
            } catch {
                saveError = (error as? LocalizedError)?.errorDescription ?? "无法保存播放列表。"
            }
        }
    }

    private func refresh(_ instance: PlaylistInstance) {
        guard !isRefreshing, !isSaving, pluginSourceManager.commitPendingUninstall() else { return }
        isRefreshing = true
        actionTask = Task {
            defer { isRefreshing = false }
            do {
                _ = try await PlaylistPlatformService.shared.refresh(instanceID: instance.id)
                guard !Task.isCancelled else { return }
                saveError = nil
            } catch {
                guard !Task.isCancelled else { return }
                saveError = PlaylistPlatformService.userMessage(for: error)
            }
            let loaded = await PlaylistPlatformService.shared.status(instanceID: instance.id)
            guard !Task.isCancelled else { return }
            status = loaded
        }
    }

    private func delete() {
        guard let editingInstance, pluginSourceManager.commitPendingUninstall() else { return }
        actionTask = Task {
            do {
                try PlaylistInstanceStore.shared.remove(id: editingInstance.id)
                await PlaylistPlatformService.shared.removeCache(instanceID: editingInstance.id)
                await refreshPlatformCatalog(pluginAvailability)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch {
                saveError = (error as? LocalizedError)?.errorDescription ?? "无法删除播放列表。"
            }
        }
    }
}

private struct PlaylistIconHeader: View {
    let name: String
    let iconFileURL: URL?
    let summary: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlaylistIconView(name: name, fileURL: iconFileURL, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
