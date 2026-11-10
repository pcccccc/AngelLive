//
//  PlaylistPlatformService.swift
//  AngelLiveCore
//
//  播放列表平台的数据提供者：拉取、缓存、分组/频道/搜索/播放地址。
//  输出与插件返回值同构的 JSON，经由 LiveParseJSPlatformManager 统一解码。
//

import CryptoKit
import Foundation

/// 平台调用请求。只携带值类型，跨隔离域安全。
enum PlaylistPlatformRequest: Sendable, Equatable {
    case categories
    case rooms(categoryId: String, page: Int)
    case search(keyword: String, page: Int)
    case playback(roomId: String)
    case roomDetail(roomId: String)
    case liveState(roomId: String)
    case unsupported(function: String)

    /// 把插件函数名与载荷映射为请求；未知函数映射为 unsupported。
    static func make(function: String, payload: [String: Any]) -> PlaylistPlatformRequest {
        func string(_ key: String) -> String {
            if let value = payload[key] as? String { return value }
            if let value = payload[key] as? NSNumber { return value.stringValue }
            return ""
        }
        func page() -> Int {
            (payload["page"] as? Int) ?? Int(string("page")) ?? 1
        }
        switch function {
        case "getCategories", "getCategoryList":
            return .categories
        case "getRooms", "getRoomList":
            return .rooms(categoryId: string("id"), page: page())
        case "search", "searchRooms":
            return .search(keyword: string("keyword"), page: page())
        case "getPlayback", "getPlayArgs":
            return .playback(roomId: string("roomId"))
        case "getRoomDetail", "getLiveLastestInfo":
            return .roomDetail(roomId: string("roomId"))
        case "getLiveState":
            return .liveState(roomId: string("roomId"))
        default:
            return .unsupported(function: function)
        }
    }
}

public struct PlaylistPreview: Sendable {
    public let channelCount: Int
    public let groupCount: Int
    public let title: String?
    let data: Data
}

public struct PlaylistRefreshStatus: Sendable, Equatable {
    public let fetchedAt: Date?
    public let channelCount: Int?
    public let lastErrorMessage: String?
}

// MARK: - 网络

struct PlaylistFetchResult: Sendable {
    let data: Data
    let finalURL: URL
    let truncated: Bool
}

protocol PlaylistFetching: Sendable {
    /// 最多读取 `limit` 字节。`allowTruncation == false` 时超限抛出 tooLarge。
    func fetch(
        url: URL,
        userAgent: String?,
        headers: [String: String],
        limit: Int,
        allowTruncation: Bool,
        timeout: TimeInterval
    ) async throws -> PlaylistFetchResult
}

public enum PlaylistFetchError: Error, Equatable, LocalizedError {
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            switch code {
            case 401, 403: "播放列表拒绝访问（\(code)），请检查地址是否有效。"
            case 404, 410: "播放列表不存在（\(code)）。"
            case 500...599: "播放列表服务器暂时不可用（\(code)）。"
            default: "无法获取播放列表（\(code)）。"
            }
        }
    }
}

struct URLSessionPlaylistFetcher: PlaylistFetching {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func fetch(
        url: URL,
        userAgent: String?,
        headers: [String: String],
        limit: Int,
        allowTruncation: Bool,
        timeout: TimeInterval
    ) async throws -> PlaylistFetchResult {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        let (bytes, response) = try await Self.session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            bytes.task.cancel()
            throw PlaylistFetchError.httpStatus(http.statusCode)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(min(response.expectedContentLength, Int64(limit))))
        }
        var truncated = false
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                truncated = true
                break
            }
            // 流媒体本体（如 FLV）不会结束，探测到文件头即可停止。
            if allowTruncation, data.count == 3, data.starts(with: Array("FLV".utf8)) {
                truncated = true
                break
            }
        }
        if truncated {
            bytes.task.cancel()
            if !allowTruncation { throw M3UPlaylistError.tooLarge }
        }
        return PlaylistFetchResult(data: data, finalURL: response.url ?? url, truncated: truncated)
    }
}

// MARK: - Service

public actor PlaylistPlatformService {
    public static let shared = PlaylistPlatformService(
        store: .shared,
        fetcher: URLSessionPlaylistFetcher(),
        cacheDirectory: PlaylistPlatformService.defaultCacheDirectory()
    )

    static let pageSize = 60
    static let cacheTTL: TimeInterval = 600
    static let allCategoryId = "__all__"
    static let mainCategoryId = "channels"
    private static let probeLimit = 256 * 1024
    private static let playlistTimeout: TimeInterval = 20
    private static let probeTimeout: TimeInterval = 6

    private struct CacheEntry {
        let playlist: M3UPlaylist
        let fetchedAt: Date
        let sourceURL: String
    }

    private let store: PlaylistInstanceStore
    private let fetcher: any PlaylistFetching
    private let cacheDirectory: URL?
    private let now: @Sendable () -> Date

    private var memory: [UUID: CacheEntry] = [:]
    private var inflight: [UUID: Task<M3UPlaylist, Error>] = [:]
    private var lastErrors: [UUID: String] = [:]

    init(
        store: PlaylistInstanceStore,
        fetcher: any PlaylistFetching,
        cacheDirectory: URL?,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.fetcher = fetcher
        self.cacheDirectory = cacheDirectory
        self.now = now
    }

    // MARK: 添加前预检

    /// 拉取并解析地址。用于添加/修改地址前的校验与预览。
    public func preview(sourceURL: String) async throws -> PlaylistPreview {
        let validated = try PlaylistInstanceStore.validatedSourceURL(sourceURL)
        guard let url = URL(string: validated) else { throw PlaylistInstanceError.invalidSourceURL }
        let result = try await fetcher.fetch(
            url: url,
            userAgent: nil,
            headers: [:],
            limit: M3UPlaylistParser.maxByteCount,
            allowTruncation: false,
            timeout: Self.playlistTimeout
        )
        let playlist = try M3UPlaylistParser.parse(result.data)
        return PlaylistPreview(
            channelCount: playlist.channels.count,
            groupCount: playlist.groups.count,
            title: playlist.title,
            data: result.data
        )
    }

    /// 用预检结果作为新实例的首份缓存，避免保存后再拉一次。
    public func seed(_ preview: PlaylistPreview, for instance: PlaylistInstance) {
        guard let playlist = try? M3UPlaylistParser.parse(preview.data) else { return }
        let fetchedAt = now()
        memory[instance.id] = CacheEntry(playlist: playlist, fetchedAt: fetchedAt, sourceURL: instance.sourceURL)
        lastErrors[instance.id] = nil
        writeDisk(preview.data, id: instance.id, sourceURL: instance.sourceURL)
    }

    // MARK: 刷新与状态

    @discardableResult
    public func refresh(instanceID: UUID) async throws -> Int {
        guard let instance = store.instance(id: instanceID) else { throw PlaylistInstanceError.notFound }
        return try await fetchAndCache(instance).channels.count
    }

    public func status(instanceID: UUID) -> PlaylistRefreshStatus {
        if memory[instanceID] == nil, let instance = store.instance(id: instanceID), let disk = readDisk(for: instance) {
            memory[instanceID] = disk
        }
        let entry = memory[instanceID]
        return PlaylistRefreshStatus(
            fetchedAt: entry?.fetchedAt ?? diskFetchedAt(id: instanceID),
            channelCount: entry?.playlist.channels.count,
            lastErrorMessage: lastErrors[instanceID]
        )
    }

    public func removeCache(instanceID: UUID) {
        memory[instanceID] = nil
        inflight[instanceID]?.cancel()
        inflight[instanceID] = nil
        lastErrors[instanceID] = nil
        if let fileURL = diskURL(id: instanceID) {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.appendingPathExtension("source"))
        }
    }

    // MARK: 平台调用

    /// 返回与插件同构的 JSON 数据。
    func handle(_ request: PlaylistPlatformRequest, instanceID: UUID) async throws -> Data {
        guard let instance = store.instance(id: instanceID) else {
            throw LiveParseError.liveParseError("播放列表不可用", "该播放列表已被删除或尚未同步到此设备。")
        }
        let liveType = instance.liveType.rawValue

        switch request {
        case .categories:
            let playlist = try await playlist(for: instance)
            return try json(Self.categoriesPayload(for: playlist))

        case .rooms(let categoryId, let page):
            let playlist = try await playlist(for: instance)
            let channels: [M3UPlaylistChannel]
            if categoryId == Self.allCategoryId || categoryId.isEmpty {
                channels = playlist.channels
            } else {
                channels = playlist.channels.filter { Self.groupId($0.group) == categoryId }
            }
            return try json(Self.page(channels, page: page).map(Self.roomPayload))

        case .search(let keyword, let page):
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return try json([[String: Any]]()) }
            let playlist = try await playlist(for: instance)
            let matches = playlist.channels.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            return try json(Self.page(matches, page: page).map(Self.roomPayload))

        case .roomDetail(let roomId):
            let channel = try await channel(roomId: roomId, in: instance)
            return try json(Self.roomPayload(channel))

        case .liveState(let roomId):
            let exists = (try? await channel(roomId: roomId, in: instance)) != nil
            return try json(["liveState": exists ? "1" : "0"])

        case .playback(let roomId):
            let channel = try await channel(roomId: roomId, in: instance)
            let cdns = await playbackPayload(for: channel, roomId: roomId, liveType: liveType)
            return try json(cdns)

        case .unsupported(let function):
            throw LiveParseError.liveParseError("不支持的操作", "播放列表平台不支持 \(function)。")
        }
    }

    // MARK: - 缓存

    private func playlist(for instance: PlaylistInstance) async throws -> M3UPlaylist {
        if let entry = memory[instance.id], entry.sourceURL == instance.sourceURL {
            if now().timeIntervalSince(entry.fetchedAt) >= Self.cacheTTL {
                refreshInBackground(instance)
            }
            return entry.playlist
        }
        if let disk = readDisk(for: instance) {
            memory[instance.id] = disk
            if now().timeIntervalSince(disk.fetchedAt) >= Self.cacheTTL {
                refreshInBackground(instance)
            }
            return disk.playlist
        }
        return try await fetchAndCache(instance)
    }

    /// 过期后先返回旧数据，后台刷新成功再替换（stale-while-revalidate）。
    private func refreshInBackground(_ instance: PlaylistInstance) {
        guard inflight[instance.id] == nil else { return }
        Task { _ = try? await self.fetchAndCache(instance) }
    }

    private func fetchAndCache(_ instance: PlaylistInstance) async throws -> M3UPlaylist {
        if let task = inflight[instance.id] {
            return try await task.value
        }
        let fetcher = self.fetcher
        let sourceURL = instance.sourceURL
        let task = Task<(M3UPlaylist, Data), Error> {
            guard let url = URL(string: sourceURL) else { throw PlaylistInstanceError.invalidSourceURL }
            let result = try await fetcher.fetch(
                url: url,
                userAgent: nil,
                headers: [:],
                limit: M3UPlaylistParser.maxByteCount,
                allowTruncation: false,
                timeout: Self.playlistTimeout
            )
            return (try M3UPlaylistParser.parse(result.data), result.data)
        }
        let playlistTask = Task<M3UPlaylist, Error> { try await task.value.0 }
        inflight[instance.id] = playlistTask
        defer { inflight[instance.id] = nil }

        do {
            let (playlist, data) = try await task.value
            // 等待期间实例可能已被删除或改了地址，旧请求不回写。
            guard let current = store.instance(id: instance.id), current.sourceURL == sourceURL else {
                return playlist
            }
            memory[instance.id] = CacheEntry(playlist: playlist, fetchedAt: now(), sourceURL: sourceURL)
            lastErrors[instance.id] = nil
            writeDisk(data, id: instance.id, sourceURL: sourceURL)
            return playlist
        } catch {
            lastErrors[instance.id] = Self.userMessage(for: error)
            throw Self.presentable(error)
        }
    }

    private func channel(roomId: String, in instance: PlaylistInstance) async throws -> M3UPlaylistChannel {
        if let found = try await playlist(for: instance).channels.first(where: { Self.roomId(for: $0) == roomId }) {
            return found
        }
        // 索引未命中时强制刷新一次（频道可能刚加入列表）。
        if let found = try? await fetchAndCache(instance).channels.first(where: { Self.roomId(for: $0) == roomId }) {
            return found
        }
        throw LiveParseError.liveParseError("频道不可用", "该频道已不在播放列表中。")
    }

    // MARK: - 播放地址

    private func playbackPayload(for channel: M3UPlaylistChannel, roomId: String, liveType: String) async -> [[String: Any]] {
        let fetcher = self.fetcher
        let expanded = await withTaskGroup(of: (Int, [PlaybackQuality]).self) { group in
            for (index, line) in channel.lines.enumerated() {
                group.addTask {
                    (index, await Self.qualities(for: line, fetcher: fetcher))
                }
            }
            var result: [Int: [PlaybackQuality]] = [:]
            for await (index, qualities) in group {
                result[index] = qualities
            }
            return result
        }

        return channel.lines.indices.map { index in
            let line = channel.lines[index]
            let qualities = expanded[index] ?? [PlaybackQuality(title: "默认", url: line.url, qn: 0, codeType: Self.codeType(forURL: line.url))]
            return [
                "cdn": "线路 \(index + 1)",
                "qualitys": qualities.map { quality in
                    var detail: [String: Any] = [
                        "roomId": roomId,
                        "title": quality.title,
                        "qn": quality.qn,
                        "url": quality.url,
                        "liveCodeType": quality.codeType.rawValue,
                        "liveType": liveType
                    ]
                    if let userAgent = line.userAgent { detail["userAgent"] = userAgent }
                    if !line.headers.isEmpty { detail["headers"] = line.headers }
                    return detail
                }
            ]
        }
    }

    struct PlaybackQuality: Sendable, Equatable {
        let title: String
        let url: String
        let qn: Int
        let codeType: LiveCodeType
    }

    /// 内容嗅探：master m3u8 展开为「自动」+ 各清晰度；FLV 文件头标记为 flv；其余原样透传。
    static func qualities(for line: M3UPlaylistLine, fetcher: any PlaylistFetching) async -> [PlaybackQuality] {
        let fallback = [PlaybackQuality(title: "默认", url: line.url, qn: 0, codeType: codeType(forURL: line.url))]
        guard let url = URL(string: line.url),
              let result = try? await fetcher.fetch(
                url: url,
                userAgent: line.userAgent,
                headers: line.headers,
                limit: probeLimit,
                allowTruncation: true,
                timeout: probeTimeout
              ) else {
            return fallback
        }
        if result.data.starts(with: Array("FLV".utf8)) {
            return [PlaybackQuality(title: "默认", url: line.url, qn: 0, codeType: .flv)]
        }
        guard let text = String(data: result.data, encoding: .utf8),
              let variants = HLSMasterPlaylistParser.variants(in: text, baseURL: result.finalURL) else {
            return fallback
        }
        guard variants.count > 1 else {
            // 只有一档时保留原地址，交给播放器按 master 处理。
            return [PlaybackQuality(title: variants.first?.title ?? "默认", url: line.url, qn: 0, codeType: .hls)]
        }
        let count = variants.count
        return [PlaybackQuality(title: "自动", url: line.url, qn: count + 1, codeType: .hls)]
            + variants.enumerated().map { offset, variant in
                PlaybackQuality(title: variant.title, url: variant.url, qn: count - offset, codeType: .hls)
            }
    }

    static func codeType(forURL url: String) -> LiveCodeType {
        let path = URL(string: url)?.path.lowercased() ?? ""
        return path.hasSuffix(".flv") ? .flv : .hls
    }

    // MARK: - 载荷构造

    static func categoriesPayload(for playlist: M3UPlaylist) -> [[String: Any]] {
        let groups = playlist.groups
        var subList: [[String: Any]] = []
        if groups.count > 1 {
            subList.append(category(id: allCategoryId, title: "全部"))
        }
        subList += groups.map { category(id: groupId($0), title: $0) }
        return [[
            "id": mainCategoryId,
            "title": "频道",
            "icon": "",
            "biz": "",
            "subList": subList
        ]]
    }

    private static func category(id: String, title: String) -> [String: Any] {
        ["id": id, "parentId": mainCategoryId, "title": title, "icon": "", "biz": ""]
    }

    static func roomPayload(_ channel: M3UPlaylistChannel) -> [String: Any] {
        let roomId = roomId(for: channel)
        return [
            // 频道没有「主播」，副标题位展示分组。
            "userName": channel.group,
            "roomTitle": channel.name,
            "roomCover": channel.logo ?? "",
            "userHeadImg": channel.logo ?? "",
            "liveState": "1",
            "userId": roomId,
            "roomId": roomId
        ]
    }

    static func page<T>(_ items: [T], page: Int) -> [T] {
        let start = (max(page, 1) - 1) * pageSize
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + pageSize, items.count)])
    }

    /// 不含 URL：线路变化、列表刷新后收藏仍可命中；同名多行已合并为同一频道。
    static func roomId(for channel: M3UPlaylistChannel) -> String {
        stableHash("\(channel.group)|\(channel.name)")
    }

    static func groupId(_ group: String) -> String {
        "g" + stableHash(group)
    }

    private static func stableHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
    }

    // MARK: - 错误

    public static func userMessage(for error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "连接播放列表超时。"
            case .notConnectedToInternet, .networkConnectionLost: return "网络不可用。"
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost: return "无法连接到播放列表服务器。"
            case .appTransportSecurityRequiresSecureConnection: return "该地址需要使用 https。"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "播放列表服务器的安全连接失败。"
            default: return "无法访问播放列表。"
            }
        }
        return "无法加载播放列表。"
    }

    static func presentable(_ error: Error) -> Error {
        if error is CancellationError || error is LiveParseError { return error }
        return LiveParseError.liveParseError("播放列表加载失败", userMessage(for: error))
    }

    // MARK: - 磁盘缓存

    static func defaultCacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AngelLivePlaylists", isDirectory: true)
    }

    private func diskURL(id: UUID) -> URL? {
        cacheDirectory?.appendingPathComponent(id.uuidString.lowercased(), isDirectory: false)
    }

    private func writeDisk(_ data: Data, id: UUID, sourceURL: String) {
        guard let cacheDirectory, let fileURL = diskURL(id: id) else { return }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // 记录来源地址的摘要而非地址本身，地址变化后旧缓存作废。
            try Data(Self.stableHash(sourceURL).utf8).write(
                to: fileURL.appendingPathExtension("source"),
                options: [.atomic]
            )
        } catch {
            Logger.warning("Playlist cache write failed: \(type(of: error))", category: .general)
        }
    }

    private func readDisk(for instance: PlaylistInstance) -> CacheEntry? {
        guard let fileURL = diskURL(id: instance.id),
              let marker = try? Data(contentsOf: fileURL.appendingPathExtension("source")),
              String(data: marker, encoding: .utf8) == Self.stableHash(instance.sourceURL),
              let data = try? Data(contentsOf: fileURL),
              let playlist = try? M3UPlaylistParser.parse(data),
              let fetchedAt = diskFetchedAt(id: instance.id) else {
            return nil
        }
        return CacheEntry(playlist: playlist, fetchedAt: fetchedAt, sourceURL: instance.sourceURL)
    }

    private func diskFetchedAt(id: UUID) -> Date? {
        guard let fileURL = diskURL(id: id) else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}
