import AppKit
import SwiftUI
import AngelLiveCore

struct MacPluginSourcesView: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    let reloadCatalog: () async -> Void
    let commitPending: () -> Bool
    @State private var playlists = PlaylistInstanceStore.shared.all()
    @State private var statuses: [UUID: PlaylistRefreshStatus] = [:]
    @State private var editingPlaylist: PlaylistInstance?
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("来源").font(.headline)
            if let localError { MacPluginFailureCard(title: "操作未完成", message: localError) }
            if manager.sourceURLs.isEmpty && playlists.isEmpty {
                MacPluginEmptyState(title: "还没有来源", message: "关闭此气泡后，点加号添加插件来源或播放列表。", systemImage: "link")
                    .frame(height: 180)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: MacPluginLayout.sectionSpacing) {
                        if !manager.sourceURLs.isEmpty {
                            VStack(alignment: .leading, spacing: MacPluginLayout.titleGap) {
                                Text("插件订阅源").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(manager.sourceURLs, id: \.self) { url in
                                    MacPluginSourceRow(
                                        url: url, health: manager.health(for: url),
                                        disabled: manager.isManagementBusy,
                                        refresh: { Task { _ = await manager.refreshSource(url) } },
                                        remove: { removeSource(url, associatedPlugins: $0) }
                                    )
                                }
                            }
                        }
                        if !playlists.isEmpty {
                            VStack(alignment: .leading, spacing: MacPluginLayout.titleGap) {
                                Text("播放列表").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(playlists) { instance in
                                    MacPlaylistSourceRow(
                                        instance: instance, status: statuses[instance.id],
                                        edit: { editingPlaylist = instance },
                                        refresh: { refreshPlaylist(instance) },
                                        remove: { deletePlaylist(instance) }
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
                Text("右键来源可以刷新、编辑或删除。删除订阅源时可以选择是否卸载关联插件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .task(id: playlists.map(\.id)) {
            for instance in playlists {
                statuses[instance.id] = await PlaylistPlatformService.shared.status(instanceID: instance.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in
            playlists = PlaylistInstanceStore.shared.all()
        }
        .sheet(item: $editingPlaylist) { instance in
            NavigationStack { MacPlaylistEditorView(mode: .edit(instance)) }
                .macSettingsSheetPresentation()
                .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 440)
        }
    }

    private func removeSource(_ url: String, associatedPlugins: Bool) {
        guard !manager.isManagementBusy, commitPending() else { return }
        Task {
            if associatedPlugins { await manager.removeSourceAndAssociatedPlugins(url) }
            else { manager.removeSource(url) }
            await availability.refresh()
            await reloadCatalog()
        }
    }

    private func refreshPlaylist(_ instance: PlaylistInstance) {
        localError = nil
        Task {
            do { _ = try await PlaylistPlatformService.shared.refresh(instanceID: instance.id) }
            catch { localError = PlaylistPlatformService.userMessage(for: error) }
            statuses[instance.id] = await PlaylistPlatformService.shared.status(instanceID: instance.id)
        }
    }

    private func deletePlaylist(_ instance: PlaylistInstance) {
        guard commitPending() else { return }
        localError = nil
        Task {
            do {
                try PlaylistInstanceStore.shared.remove(id: instance.id)
                await PlaylistPlatformService.shared.removeCache(instanceID: instance.id)
                await availability.checkAvailability()
            } catch { localError = (error as? LocalizedError)?.errorDescription ?? "无法删除播放列表。" }
        }
    }
}

private struct MacPluginSourceRow: View {
    let url: String
    let health: PluginSourceHealth
    let disabled: Bool
    let refresh: () -> Void
    let remove: (Bool) -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(string: url)?.host() ?? url).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                MacPluginSourceHealthText(health: health)
            }
            Spacer(minLength: 0)
            if health.isFailed {
                Button("重试", action: refresh).buttonStyle(.borderless).foregroundStyle(.red)
            }
            Menu {
                Button("刷新", action: refresh)
                Button("拷贝来源地址") { copyAddress() }
                Divider()
                Button("删除…", role: .destructive) { confirmingRemoval = true }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("来源操作")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .help(url)
        .contextMenu {
            Button("刷新来源", action: refresh)
            Button("拷贝来源地址") { copyAddress() }
            Divider()
            Button("删除来源…", role: .destructive) { confirmingRemoval = true }
        }
        .disabled(disabled)
        .confirmationDialog("删除这个来源？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("仅删除来源", role: .destructive) { remove(false) }
            Button("删除来源并卸载关联插件", role: .destructive) { remove(true) }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后停止检查这个来源。你可以选择保留已经安装的插件。") }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}

private struct MacPlaylistSourceRow: View {
    let instance: PlaylistInstance
    let status: PlaylistRefreshStatus?
    let edit: () -> Void
    let refresh: () -> Void
    let remove: () -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: 10) {
            MacPlaylistIcon(instance: instance, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name).fontWeight(.medium).lineLimit(1)
                Text(URL(string: instance.sourceURL)?.host() ?? instance.sourceURL)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let error = status?.lastErrorMessage {
                    Label(SupportDiagnosticSanitizer.text(error), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if let count = status?.channelCount {
                    Text("正常 · \(count) 个频道").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("编辑…", action: edit)
                Button("刷新", action: refresh)
                Divider()
                Button("删除…", role: .destructive) { confirmingRemoval = true }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("播放列表操作")
        }
        .padding(.vertical, 7).contentShape(Rectangle())
        .contextMenu {
            Button("编辑播放列表…", action: edit)
            Button("刷新播放列表", action: refresh)
            Divider()
            Button("删除播放列表…", role: .destructive) { confirmingRemoval = true }
        }
        .confirmationDialog("删除播放列表？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("删除“\(instance.name)”", role: .destructive, action: remove)
            Button("取消", role: .cancel) {}
        } message: { Text("删除后，这个播放列表的收藏和观看历史将无法播放。") }
    }
}

private struct MacPluginSourceHealthText: View {
    let health: PluginSourceHealth
    var body: some View {
        HStack(spacing: 5) {
            switch health {
            case .unknown: Text("尚未检查").foregroundStyle(.secondary)
            case .checking:
                ProgressView().controlSize(.mini)
                Text("检查中").foregroundStyle(.secondary)
            case .healthy(let count): Text("正常 · \(count) 个插件").foregroundStyle(.secondary)
            case .failed(let reason):
                Label(SupportDiagnosticSanitizer.text(reason), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).help(SupportDiagnosticSanitizer.text(reason))
            }
        }
        .font(.caption).lineLimit(1).truncationMode(.middle)
    }
}

struct MacPluginAddSourceView: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    let reloadCatalog: () async -> Void
    @State private var input = ""
    @State private var isAdding = false
    @State private var localError: String?
    @State private var playlistURL: String?
    @State private var showPlaylistEditor = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加来源").font(.headline)
            Text("输入插件订阅源地址、兑换码或 m3u 播放列表。添加后只读取列表，不会自动安装插件。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("https:// 或兑换码", text: $input)
                .textFieldStyle(.roundedBorder).focused($inputFocused).onSubmit(add)
                .disabled(isAdding)
            if let localError {
                Label(SupportDiagnosticSanitizer.text(localError), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isAdding { ProgressView().controlSize(.small); Text("正在读取来源…").foregroundStyle(.secondary) }
                Spacer()
                Button("取消") { dismiss() }.disabled(isAdding)
                Button("添加", action: add).buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding || manager.isManagementBusy)
            }
            .controlSize(.large)
        }
        .padding(16)
        .onAppear { inputFocused = true }
        .onExitCommand { if !isAdding { dismiss() } }
        .sheet(isPresented: $showPlaylistEditor, onDismiss: { dismiss() }) {
            if let playlistURL {
                NavigationStack { MacPlaylistEditorView(mode: .add(sourceURL: playlistURL)) }
                    .macSettingsSheetPresentation()
                    .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 440)
            }
        }
    }

    private func add() {
        guard !isAdding, !manager.isManagementBusy else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { localError = "请先输入来源地址或兑换码。"; return }
        localError = nil
        isAdding = true
        Task {
            defer { isAdding = false }
            switch await manager.addSourceOrDetectPlaylist(value) {
            case .playlist(let url):
                playlistURL = url
                showPlaylistEditor = true
            case .sources(let urls):
                if urls.isEmpty { localError = manager.errorMessage ?? "无法添加来源，请检查地址或兑换码。" }
                else { await reloadCatalog(); dismiss() }
            }
        }
    }
}

struct MacPlaylistIcon: View {
    let instance: PlaylistInstance?
    var name: String? = nil
    var iconFileURL: URL? = nil
    let size: CGFloat
    private var fileURL: URL? { iconFileURL ?? instance.flatMap(PlaylistIconCache.cachedFileURL(for:)) }
    var body: some View {
        if let fileURL, let image = NSImage(contentsOf: fileURL) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(PlaylistIconCache.monogram(for: name ?? instance?.name ?? ""))
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: size, height: size)
        }
    }
}
