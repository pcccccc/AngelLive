//
//  StreamBookmarkService.swift
//  AngelLiveCore
//
//  网络链接收藏的 CloudKit 同步服务。
//  使用独立的 CKRecord 类型 "stream_bookmarks"，与现有 favorite_streamers 分开。
//

import Foundation
import CloudKit
import Observation

private enum CloudStreamBookmarkFields {
    static let recordType = "stream_bookmarks"
    static let bookmarkId = "bookmark_id"
    static let title = "title"
    static let url = "url"
    static let addedAt = "added_at"
    static let lastPlayedAt = "last_played_at"
    static let containerIdentifier = "iCloud.icloud.dev.igod.simplelive"
}

@Observable
public final class StreamBookmarkService {

    public private(set) var bookmarks: [StreamBookmark] = []
    public private(set) var isLoading: Bool = false
    public private(set) var syncError: String?

    // 本地缓存 key
    @ObservationIgnored
    private let cacheKey = "AngelLive.StreamBookmarks.Cache"

    public init() {
        loadFromCache()
    }

    // MARK: - 本地缓存

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([StreamBookmark].self, from: data) else {
            return
        }
        bookmarks = decoded
    }

    private func saveToCache() {
        guard let encoded = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(encoded, forKey: cacheKey)
    }

    // MARK: - CRUD 操作

    public func add(title: String, url: String) async {
        let bookmark = StreamBookmark(title: title, url: url)
        bookmarks.insert(bookmark, at: 0)
        saveToCache()

        // 同步到 CloudKit
        do {
            try await saveToCloud(bookmark)
            syncError = nil
        } catch {
            syncError = FavoriteService.formatErrorCode(error: error)
        }
    }

    public func remove(_ bookmark: StreamBookmark) async {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveToCache()

        do {
            try await deleteFromCloud(bookmark)
            syncError = nil
        } catch {
            syncError = FavoriteService.formatErrorCode(error: error)
        }
    }

    public func update(_ bookmark: StreamBookmark) async {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
            saveToCache()

            do {
                try await updateInCloud(bookmark)
                syncError = nil
            } catch {
                syncError = FavoriteService.formatErrorCode(error: error)
            }
        }
    }

    public func updateLastPlayed(_ bookmark: StreamBookmark) async {
        var updated = bookmark
        updated.lastPlayedAt = Date()
        await update(updated)
    }

    /// 从 CloudKit 同步到本地
    public func syncFromCloud() async {
        guard let database = cloudDatabase else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let cloudBookmarks = try await fetchAllFromCloud(database: database)
            bookmarks = cloudBookmarks.sorted { $0.addedAt > $1.addedAt }
            saveToCache()
            syncError = nil
        } catch {
            syncError = FavoriteService.formatErrorCode(error: error)
        }
    }

    // MARK: - CloudKit 操作

    private var cloudDatabase: CKDatabase? {
        CloudKitContainerAccess.privateDatabase(
            containerIdentifier: CloudStreamBookmarkFields.containerIdentifier,
            purpose: "网络链接收藏 CloudKit 同步",
            category: .cloudKit
        )
    }

    private func saveToCloud(_ bookmark: StreamBookmark) async throws {
        guard let database = cloudDatabase else { return }

        let record = CKRecord(recordType: CloudStreamBookmarkFields.recordType)
        record.setValue(bookmark.id, forKey: CloudStreamBookmarkFields.bookmarkId)
        record.setValue(bookmark.title, forKey: CloudStreamBookmarkFields.title)
        record.setValue(bookmark.url, forKey: CloudStreamBookmarkFields.url)
        record.setValue(bookmark.addedAt, forKey: CloudStreamBookmarkFields.addedAt)
        if let lastPlayed = bookmark.lastPlayedAt {
            record.setValue(lastPlayed, forKey: CloudStreamBookmarkFields.lastPlayedAt)
        }
        _ = try await database.save(record)
    }

    private func deleteFromCloud(_ bookmark: StreamBookmark) async throws {
        guard let database = cloudDatabase else { return }

        let predicate = NSPredicate(format: "%K = %@", CloudStreamBookmarkFields.bookmarkId, bookmark.id)
        let query = CKQuery(recordType: CloudStreamBookmarkFields.recordType, predicate: predicate)
        let results = try await database.records(matching: query)
        for record in results.matchResults.compactMap({ try? $0.1.get() }) {
            try await database.deleteRecord(withID: record.recordID)
        }
    }

    private func updateInCloud(_ bookmark: StreamBookmark) async throws {
        // 先删除旧记录，再保存新记录
        try await deleteFromCloud(bookmark)
        try await saveToCloud(bookmark)
    }

    private func fetchAllFromCloud(database: CKDatabase) async throws -> [StreamBookmark] {
        let query = CKQuery(recordType: CloudStreamBookmarkFields.recordType, predicate: NSPredicate(value: true))
        let results = try await database.records(matching: query, resultsLimit: 99999)

        var temp: [StreamBookmark] = []
        var seenIds: Set<String> = []

        for record in results.matchResults.compactMap({ try? $0.1.get() }) {
            let bookmarkId = record.value(forKey: CloudStreamBookmarkFields.bookmarkId) as? String ?? UUID().uuidString
            guard !seenIds.contains(bookmarkId) else { continue }
            seenIds.insert(bookmarkId)

            let bookmark = StreamBookmark(
                id: bookmarkId,
                title: record.value(forKey: CloudStreamBookmarkFields.title) as? String ?? "",
                url: record.value(forKey: CloudStreamBookmarkFields.url) as? String ?? "",
                addedAt: record.value(forKey: CloudStreamBookmarkFields.addedAt) as? Date ?? Date(),
                lastPlayedAt: record.value(forKey: CloudStreamBookmarkFields.lastPlayedAt) as? Date
            )
            temp.append(bookmark)
        }

        return temp
    }
}
