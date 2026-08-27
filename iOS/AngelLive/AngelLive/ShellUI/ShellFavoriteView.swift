//
//  ShellFavoriteView.swift
//  AngelLive
//
//  壳 UI - 收藏页：显示用户通过配置页添加的网络视频链接列表。
//

import SwiftUI
import AngelLiveCore

struct ShellFavoriteView: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(ShellHistoryService.self) private var historyService

    @State private var editingBookmark: StreamBookmark?
    @State private var showDeleteAlert = false
    @State private var bookmarkToDelete: StreamBookmark?
    @State private var playingBookmark: StreamBookmark?

    var body: some View {
        NavigationStack {
            Group {
                if bookmarkService.bookmarks.isEmpty {
                    emptyView
                } else {
                    bookmarkListView
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await bookmarkService.syncFromCloud()
            }
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        ErrorView.empty(
            title: "暂无收藏",
            message: "在“配置”页添加网络视频链接后，会显示在这里。",
            symbolName: "bookmark.circle",
            tint: .mint
        )
    }

    // MARK: - 列表

    private var bookmarkListView: some View {
        List {
            ForEach(bookmarkService.bookmarks) { bookmark in
                Button {
                    playBookmark(bookmark)
                } label: {
                    bookmarkRow(bookmark)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        bookmarkToDelete = bookmark
                        showDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingBookmark = bookmark
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .alert("删除收藏", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let bookmark = bookmarkToDelete {
                    Task {
                        await bookmarkService.remove(bookmark)
                    }
                }
            }
        } message: {
            Text("确定要删除这条收藏吗？")
        }
        .sheet(item: $editingBookmark) { bookmark in
            EditBookmarkSheet(bookmark: bookmark, bookmarkService: bookmarkService)
        }
        .fullScreenCover(item: $playingBookmark) { bookmark in
            if let url = URL(string: bookmark.url) {
                DirectURLPlayerView(url: url, title: bookmark.title)
            }
        }
    }

    // MARK: - 行视图

    private func bookmarkRow(_ bookmark: StreamBookmark) -> some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            Text(bookmark.title)
                .font(.body)
                .foregroundStyle(AppConstants.Colors.primaryText)
                .lineLimit(1)

            Text(bookmark.url)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .lineLimit(1)

            if let lastPlayed = bookmark.lastPlayedAt {
                Text("上次播放: \(lastPlayed.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(AppConstants.Colors.tertiaryText)
            }
        }
        .padding(.vertical, AppConstants.Spacing.xs)
    }

    // MARK: - 播放

    private func playBookmark(_ bookmark: StreamBookmark) {
        Task {
            await bookmarkService.updateLastPlayed(bookmark)
        }
        guard URL(string: bookmark.url) != nil else { return }
        // 记录壳 UI 独立历史
        historyService.addHistory(title: bookmark.title, url: bookmark.url)
        playingBookmark = bookmark
    }
}

// MARK: - 编辑书签 Sheet

struct EditBookmarkSheet: View {
    let bookmark: StreamBookmark
    let bookmarkService: StreamBookmarkService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var url: String

    init(bookmark: StreamBookmark, bookmarkService: StreamBookmarkService) {
        self.bookmark = bookmark
        self.bookmarkService = bookmarkService
        self._title = State(initialValue: bookmark.title)
        self._url = State(initialValue: bookmark.url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("视频标题", text: $title)
                }
                Section("链接") {
                    TextField("视频地址", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("编辑收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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
    }
}
