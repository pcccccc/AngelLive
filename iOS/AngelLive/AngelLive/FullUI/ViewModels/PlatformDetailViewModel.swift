//
//  PlatformDetailViewModel.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import Foundation
import SwiftUI
import Observation
internal import AVFoundation
internal import CoreImage
internal import QuartzCore
import UIKit
import AngelLiveCore
import AngelLiveDependencies
import Alamofire

enum SOOPAdultRoomFilter: Int, CaseIterable {
    case all
    case adultOnly
    case nonAdultOnly

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .adultOnly:
            return "19x"
        case .nonAdultOnly:
            return "非19x"
        }
    }
}

private enum SOOPAdultRoomState {
    case adult
    case nonAdult
}

@Observable
class PlatformDetailViewModel {
    // 平台信息
    var platform: Platformdescription

    // 分类数据
    var categories: [LiveMainListModel] = []
    var selectedMainCategoryIndex: Int = 0
    var selectedSubCategoryIndex: Int = 0

    // 当前选中的分类
    var currentMainCategory: LiveMainListModel? {
        categories.indices.contains(selectedMainCategoryIndex) ? categories[selectedMainCategoryIndex] : nil
    }

    var currentSubCategories: [LiveCategoryModel] {
        currentMainCategory?.subList ?? []
    }

    var currentSubCategory: LiveCategoryModel? {
        let subList = currentSubCategories
        return subList.indices.contains(selectedSubCategoryIndex) ? subList[selectedSubCategoryIndex] : nil
    }

    // 房间列表 - 使用字典按分类索引缓存
    var roomListCache: [String: [LiveModel]] = [:]

    var roomList: [LiveModel] {
        get {
            let key = cacheKey
            return roomListCache[key] ?? []
        }
        set {
            let key = cacheKey
            roomListCache[key] = newValue
        }
    }

    private var cacheKey: String {
        "\(selectedMainCategoryIndex)-\(selectedSubCategoryIndex)"
    }

    // 加载状态
    var isLoadingCategories = false
    var isLoadingRooms = false

    // 错误状态
    var categoryError: Error?
    var roomError: Error?

    // 分页
    var currentPage = 1
    private let pageSize = 20
    var hasMoreRooms = true

    private let soopInitialPreviewPageCount = 3
    private let soopScrollPreviewWindowSize = 48
    var soopAdultRoomFilter: SOOPAdultRoomFilter = .all
    @ObservationIgnored private var soopAdultRoomStates: [String: SOOPAdultRoomState] = [:]
    @ObservationIgnored private var soopPreviewCheckedRoomIDs: Set<String> = []
    @ObservationIgnored private var soopPreviewInFlightRoomIDs: Set<String> = []
    @ObservationIgnored private var previewSnapshotTasks: [String: Task<Void, Never>] = [:]

    init(platform: Platformdescription) {
        self.platform = platform
    }

    // MARK: - 获取分类列表

    @MainActor
    func loadCategories() async {
        isLoadingCategories = true
        categoryError = nil
        defer { isLoadingCategories = false }

        do {
            let fetchedCategories = try await LiveService.fetchCategoryList(liveType: platform.liveType)
            categories = fetchedCategories

            // 自动加载第一个分类的房间列表
            if !categories.isEmpty {
                selectedMainCategoryIndex = 0
                if !currentSubCategories.isEmpty {
                    selectedSubCategoryIndex = 0
                    await loadRoomList()
                }
            }
        } catch {
            print("获取分类列表失败: \(error)")
            categoryError = error
        }
    }

    // MARK: - 获取房间列表

    @MainActor
    func loadRoomList(refresh: Bool = true) async {
        guard let subCategory = currentSubCategory else { return }

        if refresh {
            currentPage = 1
            hasMoreRooms = true
            roomList.removeAll()
            roomError = nil
        }

        isLoadingRooms = true
        defer { isLoadingRooms = false }

        do {
            // 获取 parentBiz (对于 YY 平台可能需要)
            let parentBiz = currentMainCategory?.biz

            let fetchedRooms: [LiveModel]
            if refresh && isSOOPPlatform {
                let result = try await fetchInitialSOOPRoomPages(
                    category: subCategory,
                    parentBiz: parentBiz
                )
                fetchedRooms = result.rooms
                currentPage = result.lastLoadedPage
                hasMoreRooms = result.hasMore
            } else {
                fetchedRooms = try await LiveService.fetchRoomList(
                    liveType: platform.liveType,
                    category: subCategory,
                    parentBiz: parentBiz,
                    page: currentPage
                )

                if fetchedRooms.isEmpty {
                    hasMoreRooms = false
                }
            }

            let roomsWithPreview = roomsByNormalizingSOOPPreviewURLs(fetchedRooms)

            if refresh {
                roomList = roomsWithPreview.removingDuplicates()
            } else {
                roomList = roomList.appendingUnique(contentsOf: roomsWithPreview)
            }
            warmSOOPAdultPreviewSnapshots(
                for: refresh ? roomList : roomsWithPreview,
                cacheKey: cacheKey
            )
            // 清除错误状态（加载成功）
            roomError = nil
        } catch {
            // 检查是否是取消错误
            let isCancelled = (error as? AFError)?.isExplicitlyCancelledError ?? false
                || error is CancellationError
                || (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled

            if !isCancelled {
                // 只有非取消错误才设置到 roomError
                print("获取房间列表失败: \(error)")
                roomError = error
            }
        }
    }

    // MARK: - 加载更多

    @MainActor
    func loadMore() async {
        guard !isLoadingRooms, hasMoreRooms else { return }
        currentPage += 1
        await loadRoomList(refresh: false)
    }

    // MARK: - 切换主分类

    @MainActor
    func selectMainCategory(index: Int) async {
        guard index != selectedMainCategoryIndex,
              categories.indices.contains(index) else { return }

        selectedMainCategoryIndex = index
        selectedSubCategoryIndex = 0
        await loadRoomList()
    }

    // MARK: - 切换子分类

    @MainActor
    func selectSubCategory(index: Int) async {
        guard currentSubCategories.indices.contains(index) else { return }

        selectedSubCategoryIndex = index

        // 检查是否有缓存数据，没有则加载
        if roomList.isEmpty {
            await loadRoomList()
        }
    }

    private var isSOOPPlatform: Bool {
        let pluginId = platform.pluginId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawLiveType = platform.liveType.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pluginId == "soop" || rawLiveType == "8" || rawLiveType == "soop"
    }

    var supportsSOOPAdultRoomFilter: Bool {
        isSOOPPlatform
    }

    @MainActor
    func setSOOPAdultRoomFilter(_ filter: SOOPAdultRoomFilter) {
        guard supportsSOOPAdultRoomFilter, soopAdultRoomFilter != filter else { return }
        soopAdultRoomFilter = filter
        NotificationCenter.default.post(name: .soopAdultRoomFilterDidUpdate, object: self)
    }

    @MainActor
    func filteredRoomList(mainCategoryIndex: Int, subCategoryIndex: Int) -> [LiveModel] {
        let rooms = roomListCache["\(mainCategoryIndex)-\(subCategoryIndex)"] ?? []
        guard supportsSOOPAdultRoomFilter else { return rooms }

        switch soopAdultRoomFilter {
        case .all:
            return rooms
        case .adultOnly:
            return rooms.filter { soopAdultRoomState(for: $0) == .adult }
        case .nonAdultOnly:
            return rooms.filter { soopAdultRoomState(for: $0) == .nonAdult }
        }
    }

    @MainActor
    func preloadSOOPAdultPreviewSnapshots(
        around room: LiveModel,
        mainCategoryIndex: Int,
        subCategoryIndex: Int
    ) {
        guard isSOOPPlatform else { return }
        let key = "\(mainCategoryIndex)-\(subCategoryIndex)"
        let cachedRooms = roomListCache[key] ?? []
        let rawIndex = cachedRooms.firstIndex { cachedRoom in
            cachedRoom.id == room.id
                || (!room.roomId.isEmpty && cachedRoom.roomId == room.roomId)
        }
        guard let rawIndex else { return }

        let endIndex = min(cachedRooms.count, rawIndex + soopScrollPreviewWindowSize)
        let rooms = Array(cachedRooms[rawIndex..<endIndex])
        warmSOOPAdultPreviewSnapshots(for: rooms, cacheKey: key)
    }

    @MainActor
    func preloadInitialSOOPAdultPreviewSnapshots(
        mainCategoryIndex: Int,
        subCategoryIndex: Int
    ) {
        guard isSOOPPlatform else { return }
        let key = "\(mainCategoryIndex)-\(subCategoryIndex)"
        let cachedRooms = roomListCache[key] ?? []
        let rooms = Array(cachedRooms.prefix(soopScrollPreviewWindowSize))
        warmSOOPAdultPreviewSnapshots(for: rooms, cacheKey: key)
    }

    private func fetchInitialSOOPRoomPages(
        category: LiveCategoryModel,
        parentBiz: String?
    ) async throws -> (rooms: [LiveModel], lastLoadedPage: Int, hasMore: Bool) {
        var combinedRooms: [LiveModel] = []
        var lastLoadedPage = 1
        var hasMore = true

        for page in 1...soopInitialPreviewPageCount {
            do {
                let rooms = try await LiveService.fetchRoomList(
                    liveType: platform.liveType,
                    category: category,
                    parentBiz: parentBiz,
                    page: page
                )
                if rooms.isEmpty {
                    hasMore = false
                    break
                }

                combinedRooms.append(contentsOf: rooms)
                lastLoadedPage = page
            } catch {
                if page == 1 {
                    throw error
                }
                Logger.warning("[SOOPPreview] warm page \(page) failed: \(error.localizedDescription)", category: .general)
                break
            }
        }

        return (combinedRooms, lastLoadedPage, hasMore)
    }

    @MainActor
    private func warmSOOPAdultPreviewSnapshots(for rooms: [LiveModel], cacheKey: String) {
        guard isSOOPPlatform else { return }
        var pendingRooms: [LiveModel] = []
        var pendingRoomIDs = Set<String>()

        for room in rooms {
            guard let roomID = soopPreviewRoomID(for: room),
                  !soopPreviewCheckedRoomIDs.contains(roomID),
                  !soopPreviewInFlightRoomIDs.contains(roomID) else {
                continue
            }
            soopPreviewInFlightRoomIDs.insert(roomID)
            pendingRoomIDs.insert(roomID)
            pendingRooms.append(room)
        }
        guard !pendingRooms.isEmpty else { return }

        let taskID = UUID().uuidString
        let task = Task { [weak self, pendingRoomIDs] in
            let probeResult = await SOOPPreviewSnapshotService.adultPlaceholderCandidates(in: pendingRooms)
            await MainActor.run {
                guard let self else { return }
                self.applySOOPAdultProbeResult(probeResult, cacheKey: cacheKey)
            }

            let refreshedCount = await SOOPPreviewSnapshotService.refreshAdultPreviewSnapshots(
                candidates: probeResult.candidates,
                cacheKey: cacheKey
            )
            Logger.debug(
                "[SOOPPreview] snapshot candidates=\(probeResult.candidates.count) refreshed=\(refreshedCount) checked=\(probeResult.checkedRoomIDs.count)",
                category: .general
            )

            await MainActor.run {
                guard let self else { return }
                self.previewSnapshotTasks[taskID] = nil
                self.soopPreviewInFlightRoomIDs.subtract(pendingRoomIDs)
            }
        }
        previewSnapshotTasks[taskID] = task
    }

    @MainActor
    private func applySOOPAdultProbeResult(
        _ result: SOOPPreviewSnapshotService.PlaceholderProbeResult,
        cacheKey: String
    ) {
        for roomID in result.adultRoomIDs {
            soopAdultRoomStates[roomID] = .adult
        }
        for roomID in result.nonAdultRoomIDs {
            soopAdultRoomStates[roomID] = .nonAdult
        }
        soopPreviewCheckedRoomIDs.formUnion(result.checkedRoomIDs)
        soopPreviewInFlightRoomIDs.subtract(result.nonAdultRoomIDs)
        NotificationCenter.default.post(
            name: .soopAdultRoomFilterDidUpdate,
            object: self,
            userInfo: ["cacheKey": cacheKey]
        )
    }

    private func roomsByNormalizingSOOPPreviewURLs(_ rooms: [LiveModel]) -> [LiveModel] {
        guard isSOOPPlatform else { return rooms }

        return rooms.map { room in
            guard let previewURL = LiveImageURLResolver.soopLivePreviewURLString(
                roomId: room.roomId
            ), shouldUseStableSOOPPreviewURL(for: room) else {
                return room
            }

            var normalized = LiveModel(
                userName: room.userName,
                roomTitle: room.roomTitle,
                roomCover: previewURL,
                userHeadImg: room.userHeadImg,
                liveType: room.liveType,
                liveState: room.liveState,
                userId: room.userId,
                roomId: room.roomId,
                liveWatchedCount: room.liveWatchedCount
            )
            normalized.id = room.id
            return normalized
        }
    }

    private func shouldUseStableSOOPPreviewURL(for room: LiveModel) -> Bool {
        let rawCover = room.roomCover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawCover.isEmpty else { return true }

        let normalized = LiveImageURLResolver.normalizedURLString(rawCover)
        guard let url = URL(string: normalized) else { return false }
        return SOOPPreviewSnapshotService.isSOOPLivePreviewURL(url)
    }

    private func soopAdultRoomState(for room: LiveModel) -> SOOPAdultRoomState? {
        guard let roomID = soopPreviewRoomID(for: room) else { return nil }
        return soopAdultRoomStates[roomID]
    }
}

extension Notification.Name {
    static let soopPreviewSnapshotDidUpdate = Notification.Name("SOOPPreviewSnapshotDidUpdate")
    static let soopAdultRoomFilterDidUpdate = Notification.Name("SOOPAdultRoomFilterDidUpdate")
}

private func soopPreviewRoomID(for room: LiveModel) -> String? {
    let roomID = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !roomID.isEmpty, roomID.allSatisfy(\.isNumber) else { return nil }
    return roomID
}

private enum SOOPPreviewSnapshotService {
    private static let adultPlaceholderContentLengthLimit = 12_000
    private static let detectionBatchSize = 16
    private static let playbackSnapshotUserAgent = "libmpv"

    struct PlaceholderProbeResult: Sendable {
        let candidates: [SnapshotCandidate]
        let adultRoomIDs: Set<String>
        let nonAdultRoomIDs: Set<String>
        let checkedRoomIDs: Set<String>
    }

    struct SnapshotCandidate: Sendable {
        let roomID: String
        let room: LiveModel
        let coverURL: URL
    }

    private struct PlaceholderProbe: Sendable {
        let roomIndex: Int
        let roomID: String
        let candidate: SnapshotCandidate?
    }

    static func refreshAdultPreviewSnapshots(
        candidates: [SnapshotCandidate],
        cacheKey: String
    ) async -> Int {
        var refreshedCount = 0
        for candidate in candidates {
            guard !Task.isCancelled else {
                return refreshedCount
            }
            guard let image = await playbackSnapshot(for: candidate.room) else {
                Logger.debug("[SOOPPreview] snapshot image unavailable roomId=\(candidate.room.roomId)", category: .general)
                continue
            }
            storeSnapshot(image, for: candidate.coverURL, cacheKey: cacheKey)
            refreshedCount += 1
        }
        return refreshedCount
    }

    static func adultPlaceholderCandidates(
        in rooms: [LiveModel]
    ) async -> PlaceholderProbeResult {
        var candidates: [SnapshotCandidate] = []
        var adultRoomIDs = Set<String>()
        var nonAdultRoomIDs = Set<String>()
        var checkedRoomIDs = Set<String>()
        let scanRooms = Array(rooms)
        var startIndex = 0

        while startIndex < scanRooms.count {
            guard !Task.isCancelled else {
                return PlaceholderProbeResult(
                    candidates: candidates,
                    adultRoomIDs: adultRoomIDs,
                    nonAdultRoomIDs: nonAdultRoomIDs,
                    checkedRoomIDs: checkedRoomIDs
                )
            }
            let endIndex = min(startIndex + detectionBatchSize, scanRooms.count)
            let batch = Array(scanRooms[startIndex..<endIndex])

            await withTaskGroup(of: PlaceholderProbe?.self) { group in
                for (offset, room) in batch.enumerated() {
                    guard let roomID = soopPreviewRoomID(for: room),
                          let coverURL = URL(string: room.displayRoomCover),
                          isSOOPLivePreviewURL(coverURL) else { continue }
                    let roomIndex = startIndex + offset
                    group.addTask {
                        guard let isPlaceholder = await adultPlaceholderState(at: coverURL) else { return nil }
                        return PlaceholderProbe(
                            roomIndex: roomIndex,
                            roomID: roomID,
                            candidate: isPlaceholder
                                ? SnapshotCandidate(roomID: roomID, room: room, coverURL: coverURL)
                                : nil
                        )
                    }
                }

                var batchProbes: [PlaceholderProbe] = []
                for await result in group {
                    if let result {
                        batchProbes.append(result)
                    }
                }
                for probe in batchProbes {
                    checkedRoomIDs.insert(probe.roomID)
                    if probe.candidate == nil {
                        nonAdultRoomIDs.insert(probe.roomID)
                    }
                }
                let batchCandidates = batchProbes
                    .compactMap { probe -> (Int, SnapshotCandidate)? in
                        guard let candidate = probe.candidate else { return nil }
                        return (probe.roomIndex, candidate)
                    }
                    .sorted { $0.0 < $1.0 }
                    .map(\.1)

                adultRoomIDs.formUnion(batchCandidates.map(\.roomID))
                candidates.append(contentsOf: batchCandidates)
            }

            startIndex = endIndex
        }

        if candidates.isEmpty {
            Logger.debug(
                "[SOOPPreview] snapshot candidates=0 checked=\(checkedRoomIDs.count)",
                category: .general
            )
        }

        return PlaceholderProbeResult(
            candidates: candidates,
            adultRoomIDs: adultRoomIDs,
            nonAdultRoomIDs: nonAdultRoomIDs,
            checkedRoomIDs: checkedRoomIDs
        )
    }

    static func isSOOPLivePreviewURL(_ url: URL) -> Bool {
        url.host?.lowercased() == "liveimg.sooplive.com"
            && url.path.hasPrefix("/m/")
    }

    private static func adultPlaceholderState(at url: URL) async -> Bool? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }

            if let lengthText = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length"),
               let length = Int(lengthText),
               length > 0 {
                return length <= adultPlaceholderContentLengthLimit
            }

            let expectedLength = response.expectedContentLength
            if expectedLength > 0 {
                return expectedLength <= adultPlaceholderContentLengthLimit
            }
        } catch {
            Logger.debug("[SOOPPreview] placeholder HEAD failed: \(error.localizedDescription)", category: .general)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data.count <= adultPlaceholderContentLengthLimit
        } catch {
            Logger.debug("[SOOPPreview] placeholder GET failed: \(error.localizedDescription)", category: .general)
            return nil
        }
    }

    private static func playbackSnapshot(for room: LiveModel) async -> UIImage? {
        do {
            guard let platform = SandboxPluginCatalog.platform(for: room.liveType) else { return nil }
            let playArgs = try await LiveParseJSPlatformManager.getPlayArgs(
                platform: platform,
                roomId: room.roomId,
                userId: room.userId
            )
            guard let selected = RoomPlaybackResolver.firstSelection(
                in: playArgs,
                where: RoomPlaybackResolver.isHLSQuality
            ) ?? RoomPlaybackResolver.preferredInitialSelection(in: playArgs),
                  playArgs.indices.contains(selected.cdnIndex) else {
                return nil
            }

            let cdn = playArgs[selected.cdnIndex]
            let preparedQuality = try await RoomPlaybackPreparer.prepare(
                roomId: room.roomId,
                cdn: cdn,
                quality: selected.quality,
                plugin: platform
            )
            guard let url = RoomPlaybackResolver.playableURL(for: preparedQuality) else { return nil }
            let requestOptions = RoomPlaybackResolver.requestOptions(
                for: preparedQuality,
                fallbackUserAgent: playbackSnapshotUserAgent
            )
            return await firstFrameImage(from: url, headers: requestOptions.headers)
        } catch {
            Logger.debug(
                "[SOOPPreview] snapshot failed roomId=\(room.roomId): \(error.localizedDescription)",
                category: .general
            )
            return nil
        }
    }

    private static func firstFrameImage(from url: URL, headers: [String: String]) async -> UIImage? {
        await Task.detached(priority: .utility) {
            var options: [String: Any] = [:]
            if !headers.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = headers
            }

            let asset = AVURLAsset(url: url, options: options)
            let playerItem = AVPlayerItem(asset: asset)
            let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            playerItem.add(videoOutput)

            let player = AVPlayer(playerItem: playerItem)
            player.isMuted = true
            player.automaticallyWaitsToMinimizeStalling = true
            let imageContext = CIContext()
            defer {
                player.pause()
                playerItem.remove(videoOutput)
            }

            player.play()
            let deadline = Date().addingTimeInterval(7)
            while Date() < deadline {
                guard !Task.isCancelled else { return nil }
                try? await Task.sleep(nanoseconds: 150_000_000)

                let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
                guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
                      let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
                    continue
                }

                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                if let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) {
                    return UIImage(cgImage: cgImage)
                }
            }

            return nil
        }.value
    }

    @MainActor
    private static func storeSnapshot(_ image: UIImage, for url: URL, cacheKey: String) {
        // Keep the model as a normal remote SOOP preview URL. We only replace
        // Kingfisher's in-memory image for that stable URL, so favorites/cloud
        // persistence never receives a generated local file path.
        ImageCache.default.store(image, forKey: url.absoluteString, toDisk: false)
        Logger.debug("[SOOPPreview] snapshot stored key=\(url.absoluteString)", category: .general)
        NotificationCenter.default.post(
            name: .soopPreviewSnapshotDidUpdate,
            object: nil,
            userInfo: ["cacheKey": cacheKey]
        )
    }
}
