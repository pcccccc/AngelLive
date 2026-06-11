//
//  FavoriteStateModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 10/17/25.
//

import Foundation

/// 刷新发现的一条身份元数据变化,供上层落本地后回写 CloudKit。
/// `oldKey` 是刷新前(本地真相)的稳定主键,`newRoom` 带最新身份 + 新 `identityUpdatedAt`。
/// 不含 `liveState`(状态不上云)。身份相等口径走稳定 key,不用 `LiveModel.==`。
public struct FavoriteIdentityChange: Sendable {
    public let oldKey: String
    public let newRoom: LiveModel
}

/// 收藏刷新结果:UI 用的排序列表 + 分组,外加本次刷新探测到的身份变化(供回写)。
public struct FavoriteSyncResult: Sendable {
    public let rooms: [LiveModel]
    public let grouped: [FavoriteLiveSectionModel]
    public let identityChanges: [FavoriteIdentityChange]
}

public struct FavoriteLiveSectionModel: Identifiable, Sendable {
    /// 稳定身份:title 即逻辑分组键(平台名 / 直播状态名),在两种分组样式下都唯一且稳定。
    /// 不用随机 UUID——否则每次同步重建分组都被 SwiftUI 当成全新 section,导致焦点重置、整段重排动画。
    /// 不用 type——liveState 分组里 type 取自"该状态下第一条房间"的平台,会随排序在多次同步间漂移。
    public var id: String { title }
    public var roomList: [LiveModel] = []
    public var title: String = ""
    public var type: LiveType = .placeholder

    public init() {}
}

public actor FavoriteStateModel {

    var currentProgress: (String, String, String, Int, Int) = ("", "", "", 0, 0)
    private var isSyncing = false  // 添加同步标志

    public init() {}

    /// 刷新收藏的直播状态。
    /// - Parameter members: 成员列表来源。Phase③ 由上层传入本地真相(CKSyncEngine 已同步);
    ///   传 nil 时回退到旧行为(从默认 Zone 拉取),保留向后兼容。
    public func syncStreamerLiveStates(members: [LiveModel]? = nil) async throws -> FavoriteSyncResult {
        let overallStart = CFAbsoluteTimeGetCurrent()
        let consoleEntryId = await MainActor.run {
            PluginConsoleService.shared.log(tag: "FavoriteSync", method: "syncAll", status: .loading)
        }
        // 防止并发执行
        guard !isSyncing else {
            print("Actor 正在同步中，拒绝重复调用")
            await MainActor.run {
                PluginConsoleService.shared.updateStatus(
                    id: consoleEntryId,
                    status: .error,
                    duration: CFAbsoluteTimeGetCurrent() - overallStart,
                    errorMessage: "正在同步中,拒绝重复调用"
                )
            }
            throw NSError(domain: "FavoriteStateModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "正在同步中"])
        }

        isSyncing = true
        defer { isSyncing = false }

        var roomList: [LiveModel] = []
        if let members {
            // Phase③:成员来自本地真相(CKSyncEngine 已同步),不再拉默认 Zone。
            roomList = deduplicateFavoriteRooms(members)
            favoriteSyncLog("使用本地成员 \(roomList.count) 条(引擎已同步)")
        } else {
            do {
                let cloudStart = CFAbsoluteTimeGetCurrent()
                roomList = try await FavoriteService.searchRecord()
                roomList = deduplicateFavoriteRooms(roomList)
                let cloudDuration = CFAbsoluteTimeGetCurrent() - cloudStart
                favoriteSyncLog("CloudKit fetched \(roomList.count) favorites in \(formatSeconds(cloudDuration))s")
            } catch {
                await MainActor.run {
                    PluginConsoleService.shared.updateStatus(
                        id: consoleEntryId,
                        status: .error,
                        duration: CFAbsoluteTimeGetCurrent() - overallStart,
                        errorMessage: "CloudKit 拉取收藏失败: \(error.localizedDescription)"
                    )
                }
                throw error
            }
        }
        let cloudFetchedCount = roomList.count
        await MainActor.run {
            PluginConsoleService.shared.updateRequest(
                id: consoleEntryId,
                body: "CloudKit fetched: \(cloudFetchedCount) rooms"
            )
        }

        var platformFavoriteCounts: [LiveType: Int] = [:]
        for room in roomList {
            platformFavoriteCounts[room.liveType, default: 0] += 1
        }

        // 使用任务组并发获取房间状态
        var fetchedModels: [LiveModel] = []
        // 本次刷新探测到的身份变化(供上层落本地后回写 CloudKit)。
        var identityChanges: [FavoriteIdentityChange] = []
        var platformStats: [LiveType: (count: Int, totalTime: Double, success: Int, failure: Int)] = [:]
        let statusSyncStart = CFAbsoluteTimeGetCurrent()

        await withTaskGroup(of: (Int, LiveModel?, String, String, String, LiveType, Double).self) { group in
            for (index, liveModel) in roomList.enumerated() {
                group.addTask {
                    let platformName = LiveParseTools.getLivePlatformName(liveModel.liveType)
                    favoriteSyncLog("[\(index + 1)/\(roomList.count)] 开始查询 \(platformName) - \(liveModel.userName) (roomId=\(liveModel.roomId), userId=\(liveModel.userId))")
                    let taskStart = CFAbsoluteTimeGetCurrent()
                    do {
                        let dataReq = try await ApiManager.fetchLastestLiveInfoFast(liveModel: liveModel)
                        let duration = CFAbsoluteTimeGetCurrent() - taskStart
                        if PlatformHostBehavior.shouldPreserveFavoriteRoomInfoOnRefresh(for: liveModel.liveType) {
                            var finalLiveModel = liveModel
                            finalLiveModel.liveState = dataReq.liveState
                            return (index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", liveModel.liveType, duration)
                        } else {
                            return (index, dataReq, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", liveModel.liveType, duration)
                        }
                    } catch {
                        let duration = CFAbsoluteTimeGetCurrent() - taskStart
                        favoriteSyncLog("[\(index + 1)/\(roomList.count)] 查询失败 \(platformName) - \(liveModel.userName) 耗时 \(formatSeconds(duration))s 错误: \(error)")
                        var errorModel = liveModel
                        errorModel.liveState = PlatformHostBehavior.liveStateOnFavoriteRefreshFailure(for: errorModel.liveType).rawValue
                        return (index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败", liveModel.liveType, duration)
                    }
                }
            }

            var resultModels = [LiveModel?](repeating: nil, count: roomList.count)
            for await (index, model, userName, platformName, status, liveType, duration) in group {
                self.currentProgress = (userName, platformName, status, index + 1, roomList.count)
                favoriteSyncLog("\(platformName) - \(userName) \(status) in \(formatSeconds(duration))s")

                var stat = platformStats[liveType] ?? (0, 0, 0, 0)
                stat.count += 1
                stat.totalTime += duration
                if status == "成功" {
                    stat.success += 1
                } else {
                    stat.failure += 1
                }
                platformStats[liveType] = stat

                if let model = model {
                    resultModels[index] = model
                }
            }
            fetchedModels = resultModels.compactMap { $0 }

            // 身份 diff:在 dedup/排序之前按 index 配对 旧(本地真相)↔ 新(刷新结果)。
            // 仅非 preserve 平台、且身份字段(非 liveState)有"非降级"变化时产出回写事件。
            // preserve 平台身份不刷新、失败项身份未变,均自然不产出。
            for (index, old) in roomList.enumerated() {
                guard let new = resultModels[index] else { continue }
                if PlatformHostBehavior.shouldPreserveFavoriteRoomInfoOnRefresh(for: old.liveType) { continue }
                guard AppFavoriteModel.favoriteIdentityChanged(old: old, new: new) else { continue }
                var stamped = new
                stamped.identityUpdatedAt = Date()
                identityChanges.append(FavoriteIdentityChange(
                    oldKey: AppFavoriteModel.favoriteUniqueKey(for: old),
                    newRoom: stamped
                ))
            }
        }

        fetchedModels = deduplicateFavoriteRooms(fetchedModels)

        let statusSyncDuration = CFAbsoluteTimeGetCurrent() - statusSyncStart
        let syncedCount = fetchedModels.count
        favoriteSyncLog("Live status sync finished \(syncedCount) rooms in \(formatSeconds(statusSyncDuration))s")

        let sortedPlatformStats = platformStats.sorted { $0.key.rawValue < $1.key.rawValue }
        var consoleReportLines: [String] = []
        var totalSuccess = 0
        var totalFailure = 0
        for (liveType, stat) in sortedPlatformStats {
            let platformName = LiveParseTools.getLivePlatformName(liveType)
            let totalFavorites = platformFavoriteCounts[liveType] ?? stat.count
            let avg = stat.count > 0 ? stat.totalTime / Double(stat.count) : 0
            favoriteSyncLog("\(platformName): favorites \(totalFavorites), synced \(stat.count), total \(formatSeconds(stat.totalTime))s, avg \(formatSeconds(avg))s, success \(stat.success), fail \(stat.failure)")
            consoleReportLines.append("\(platformName): \(stat.success)/\(stat.count) 成功, 失败 \(stat.failure), 总耗时 \(formatSeconds(stat.totalTime))s (avg \(formatSeconds(avg))s)")
            totalSuccess += stat.success
            totalFailure += stat.failure
        }

        let overallDuration = CFAbsoluteTimeGetCurrent() - overallStart
        favoriteSyncLog("Favorite sync tox xtal time \(formatSeconds(overallDuration))s")
        let consoleResponseBody = """
        CloudKit fetched: \(cloudFetchedCount) rooms
        synced: \(syncedCount), 成功 \(totalSuccess), 失败 \(totalFailure)
        status sync: \(formatSeconds(statusSyncDuration))s, total: \(formatSeconds(overallDuration))s

        per-platform:
        \(consoleReportLines.isEmpty ? "(无)" : consoleReportLines.joined(separator: "\n"))
        """
        let finalConsoleStatus: PluginConsoleEntryStatus = (totalFailure > 0 ? .success : .success)
        // 注:即使有平台失败也走 success,失败计数已经体现在响应体里;只有 throw 才算 .error。
        await MainActor.run {
            PluginConsoleService.shared.updateStatus(
                id: consoleEntryId,
                status: finalConsoleStatus,
                duration: overallDuration,
                responseBody: consoleResponseBody
            )
        }
        
        // 使用抽取的排序和分组方法，消除重复代码
        let sortedModels = fetchedModels.sortedByLiveState()
        let style = AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) ?? .liveState
        let groupedRoomList = sortedModels.groupedBySections(style: style)

        if !identityChanges.isEmpty {
            favoriteSyncLog("身份回写候选 \(identityChanges.count) 条")
        }
        return FavoriteSyncResult(rooms: sortedModels, grouped: groupedRoomList, identityChanges: identityChanges)
    }


    public func getState() async -> (Bool, String)  {
        let stateString = await FavoriteService.getCloudState()
        return (stateString == "正常", stateString)
    }

    public func getCurrentProgress() async -> (String, String, String, Int, Int) {
        return currentProgress
    }
}

private func deduplicateFavoriteRooms(_ rooms: [LiveModel]) -> [LiveModel] {
    // 多维度去重(平台无关):同平台下 userId 或 roomId 任一有效维度相同即同一主播。
    let result = AppFavoriteModel.deduplicated(rooms)
    if result.count != rooms.count {
        print("[FavoriteDedup] 多维度去重 \(rooms.count) → \(result.count)(合并 \(rooms.count - result.count) 条)")
    }
    return result
}

private func favoriteSyncLog(_ message: String) {
    print("[FavoriteSync] \(message)")
}

private func formatSeconds(_ seconds: Double) -> String {
    return String(format: "%.2f", seconds)
}
