// TVShellFavoriteView.swift
// AngelLiveTVOS
//
// 壳 UI 收藏页 - 卡片网格布局，适配 tvOS 大屏设计语言

import SwiftUI
import SharedAssets
import AngelLiveCore
import AngelLiveDependencies

struct TVShellFavoriteView: View {
    @Environment(AppState.self) private var appViewModel
    @State private var editingBookmark: StreamBookmark?
    @State private var showDeleteDialog = false
    @State private var bookmarkToDelete: StreamBookmark?
    @State private var playingBookmark: StreamBookmark?
    @State private var playingHistoryURL: URL?
    @State private var playingHistoryTitle: String = ""

    private let gridColumns = Array(repeating: GridItem(.fixed(380), spacing: 50), count: 4)

    var isEmpty: Bool {
        appViewModel.bookmarkService.bookmarks.isEmpty &&
        appViewModel.shellHistoryService.items.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                emptyView
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 50) {
                        // 最近播放（水平滚动）
                        if !appViewModel.shellHistoryService.items.isEmpty {
                            historySection
                        }
                        // 收藏（4 列网格）
                        if !appViewModel.bookmarkService.bookmarks.isEmpty {
                            bookmarksSection
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 60)
                }
            }
        }
        .task {
            await appViewModel.bookmarkService.syncFromCloud()
        }
        .confirmationDialog("删除收藏", isPresented: $showDeleteDialog) {
            Button("删除", role: .destructive) {
                guard let bookmark = bookmarkToDelete else { return }
                Task { await appViewModel.bookmarkService.remove(bookmark) }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $editingBookmark) { bookmark in
            TVEditBookmarkSheet(bookmark: bookmark, bookmarkService: appViewModel.bookmarkService)
        }
        .fullScreenCover(item: $playingBookmark) { bookmark in
            if let url = URL(string: bookmark.url) {
                TVDirectURLPlayerView(url: url, title: bookmark.title)
                    .fullUIArcLoadingStyle(isEnabled: false)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { playingHistoryURL != nil },
            set: { if !$0 { playingHistoryURL = nil } }
        )) {
            if let url = playingHistoryURL {
                TVDirectURLPlayerView(url: url, title: playingHistoryTitle)
                    .fullUIArcLoadingStyle(isEnabled: false)
            }
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂无收藏", systemImage: "bookmark")
        } description: {
            Text("在「配置」页添加网络视频链接后，将在此处显示")
        }
    }

    // MARK: - 最近播放 Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "最近播放",
                count: appViewModel.shellHistoryService.items.count,
                color: .blue
            )
            .padding(.leading, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(180), spacing: 30)], spacing: 30) {
                    ForEach(appViewModel.shellHistoryService.items) { item in
                        historyCard(item)
                    }
                }
                .safeAreaPadding([.leading, .trailing], 50)
                .padding(.vertical, 30)
            }
            .padding(.top, -30)
        }
        .focusSection()
    }

    private func historyCard(_ item: ShellHistoryItem) -> some View {
        Button {
            playHistoryItem(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(item.url)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)

                    Text(item.playedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(20)
            .frame(width: 280, height: 170)
            .adaptiveGlassEffectRoundedRect(cornerRadius: 12)
        }
        .buttonStyle(.card)
        .contextMenu {
            Button("删除", role: .destructive) {
                appViewModel.shellHistoryService.removeHistory(item)
            }
            Button("清空全部历史", role: .destructive) {
                appViewModel.shellHistoryService.clearAll()
            }
        }
    }

    // MARK: - 收藏 Section

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "收藏",
                count: appViewModel.bookmarkService.bookmarks.count,
                color: .green
            )
            .padding(.leading, 50)

            LazyVGrid(columns: gridColumns, alignment: .center, spacing: 50) {
                ForEach(appViewModel.bookmarkService.bookmarks) { bookmark in
                    bookmarkCard(bookmark)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .focusSection()
    }

    private func bookmarkCard(_ bookmark: StreamBookmark) -> some View {
        Button {
            playBookmark(bookmark)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Text(bookmark.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(bookmark.url)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)

                    if let lastPlayed = bookmark.lastPlayedAt {
                        Text("上次播放: \(lastPlayed.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(24)
            .frame(width: 370, height: 220)
            .adaptiveGlassEffectRoundedRect(cornerRadius: 16)
        }
        .buttonStyle(.card)
        .contextMenu {
            Button("编辑") {
                editingBookmark = bookmark
            }
            Button("删除", role: .destructive) {
                bookmarkToDelete = bookmark
                showDeleteDialog = true
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 6, height: 28)

            Text(title)
                .font(.title2.bold())

            Text("\(count)")
                .font(.system(size: 22, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.gray.opacity(0.3)))

            Spacer()
        }
    }

    // MARK: - 播放操作

    private func playBookmark(_ bookmark: StreamBookmark) {
        guard URL(string: bookmark.url) != nil else { return }
        Task { await appViewModel.bookmarkService.updateLastPlayed(bookmark) }
        appViewModel.shellHistoryService.addHistory(title: bookmark.title, url: bookmark.url)
        playingBookmark = bookmark
    }

    private func playHistoryItem(_ item: ShellHistoryItem) {
        guard URL(string: item.url) != nil else { return }
        appViewModel.shellHistoryService.addHistory(title: item.title, url: item.url)
        playingHistoryTitle = item.title
        playingHistoryURL = URL(string: item.url)
    }
}

// MARK: - 编辑书签 Sheet

private struct TVEditBookmarkSheet: View {
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
