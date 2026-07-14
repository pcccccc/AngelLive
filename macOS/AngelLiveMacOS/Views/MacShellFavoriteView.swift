import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct MacShellFavoriteView: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @State private var editingBookmark: StreamBookmark?
    @State private var showDeleteAlert = false
    @State private var bookmarkToDelete: StreamBookmark?
    @State private var playingBookmark: StreamBookmark?

    private let featureRowInsets = EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12)
    private let emptyRowInsets = EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PanelHintCard(
                        title: "管理常用直链",
                        message: "点按条目即可直接播放；长按或右键可以继续编辑标题、地址和删除内容。",
                        systemImage: "bookmark.circle.fill",
                        tint: .accentColor
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(featureRowInsets)
                }

                Section {
                    if bookmarkService.bookmarks.isEmpty {
                        ErrorView.empty(
                            title: "暂无收藏",
                            message: "在“配置”页添加网络视频链接后，将在此处显示。",
                            symbolName: "bookmark",
                            tint: .secondary,
                            layout: .compact(minHeight: 220)
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(emptyRowInsets)
                    } else {
                        ForEach(bookmarkService.bookmarks) { bookmark in
                            bookmarkRow(bookmark)
                        }
                    }
                } header: {
                    Text("已保存内容")
                } footer: {
                    if !bookmarkService.bookmarks.isEmpty {
                        Text("共 \(bookmarkService.bookmarks.count) 条收藏")
                    }
                }
            }
            .navigationTitle("收藏")
            .task {
                await bookmarkService.syncFromCloud()
            }
            .alert("删除收藏", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    guard let bookmark = bookmarkToDelete else { return }
                    Task {
                        await bookmarkService.remove(bookmark)
                    }
                }
            } message: {
                Text("确定要删除这条收藏吗？")
            }
            .sheet(item: $editingBookmark) { bookmark in
                MacEditBookmarkSheet(bookmark: bookmark, bookmarkService: bookmarkService)
            }
            .sheet(item: $playingBookmark) { bookmark in
                if let url = URL(string: bookmark.url) {
                    MacDirectURLPlayerView(url: url, title: bookmark.title)
                        .frame(minWidth: 900, minHeight: 560)
                }
            }
        }
    }

    private func bookmarkRow(_ bookmark: StreamBookmark) -> some View {
        Button {
            playBookmark(bookmark)
        } label: {
            PanelNavigationRow(
                title: bookmark.title,
                subtitle: bookmark.url,
                showsChevron: false
            ) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor.gradient)
            } trailing: {
                HStack(spacing: 10) {
                    if let lastPlayed = bookmark.lastPlayedAt {
                        PanelStatusBadge(lastPlayed.formatted(.relative(presentation: .named)), tint: .accentColor)
                    }

                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑") {
                editingBookmark = bookmark
            }
            Button("删除", role: .destructive) {
                bookmarkToDelete = bookmark
                showDeleteAlert = true
            }
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                bookmarkToDelete = bookmark
                showDeleteAlert = true
            }
        }
        .swipeActions(edge: .leading) {
            Button("编辑") {
                editingBookmark = bookmark
            }
            .tint(.blue)
        }
    }

    private func playBookmark(_ bookmark: StreamBookmark) {
        guard URL(string: bookmark.url) != nil else { return }
        Task { await bookmarkService.updateLastPlayed(bookmark) }
        playingBookmark = bookmark
    }
}

private struct MacEditBookmarkSheet: View {
    let bookmark: StreamBookmark
    let bookmarkService: StreamBookmarkService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var url: String

    init(bookmark: StreamBookmark, bookmarkService: StreamBookmarkService) {
        self.bookmark = bookmark
        self.bookmarkService = bookmarkService
        _title = State(initialValue: bookmark.title)
        _url = State(initialValue: bookmark.url)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                TextField("链接", text: $url)
            }
            .navigationTitle("编辑收藏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = bookmark
                        updated.title = title
                        updated.url = url
                        Task {
                            await bookmarkService.update(updated)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty || url.isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 220)
    }
}

private struct MacDirectURLPlayerView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerCoordinator: KSVideoPlayer.Coordinator
    private let playerOptions: KSOptions

    init(url: URL, title: String) {
        self.url = url
        self.title = title

        let options = KSOptions()
        options.userAgent = "libmpv"
        options.playerTypes = url.absoluteString.lowercased().contains(".m3u8")
            ? [KSAVPlayer.self, KSMEPlayer.self]
            : [KSMEPlayer.self]
        self.playerOptions = options
        _playerCoordinator = StateObject(wrappedValue: KSVideoPlayer.Coordinator())
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            KSVideoPlayer(coordinator: playerCoordinator, url: url, options: playerOptions)
                .ignoresSafeArea()

            HStack {
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(16)
        }
    }
}
