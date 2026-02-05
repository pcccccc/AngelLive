//
//  FavoriteStateModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 10/17/25.
//

import Foundation
import LiveParse

public struct FavoriteLiveSectionModel: Identifiable, Sendable {
    public var id = UUID()
    public var roomList: [LiveModel] = []
    public var title: String = ""
    public var type: LiveType = .bilibili

    public init() {}
}

public actor FavoriteStateModel {

    var currentProgress: (String, String, String, Int, Int) = ("", "", "", 0, 0)
    private var isSyncing = false  // 添加同步标志

    public init() {}

    public func syncStreamerLiveStates() async throws -> ([LiveModel], [FavoriteLiveSectionModel]) {
        let overallStart = CFAbsoluteTimeGetCurrent()
        // 防止并发执行
        guard !isSyncing else {
            print("Actor 正在同步中，拒绝重复调用")
            throw NSError(domain: "FavoriteStateModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "正在同步中"])
        }

        isSyncing = true
        defer { isSyncing = false }

        var roomList: [LiveModel] = []
        do {
            let cloudStart = CFAbsoluteTimeGetCurrent()
            roomList = try await FavoriteService.searchRecord()
            let cloudDuration = CFAbsoluteTimeGetCurrent() - cloudStart
            favoriteSyncLog("CloudKit fetched \(roomList.count) favorites in \(formatSeconds(cloudDuration))s")
        }catch {
            throw error
        }

        var platformFavoriteCounts: [LiveType: Int] = [:]
        for room in roomList {
            platformFavoriteCounts[room.liveType, default: 0] += 1
        }

        // 分离 YouTube 和非 YouTube 收藏
        let youtubeRooms = roomList.filter { $0.liveType == .youtube }
        let nonYoutubeRooms = roomList.filter { $0.liveType != .youtube }

        // 使用任务组并发获取房间状态
        var fetchedModels: [LiveModel] = []
        var platformStats: [LiveType: (count: Int, totalTime: Double, success: Int, failure: Int)] = [:]
        let statusSyncStart = CFAbsoluteTimeGetCurrent()

        // YouTube 可达性检查与非 YouTube 同步并行进行
        let youtubeCheckTask = Task<Bool, Never> {
            guard !youtubeRooms.isEmpty else { return false }
            let checkStart = CFAbsoluteTimeGetCurrent()
            let result = await ApiManager.checkInternetConnection()
            let duration = CFAbsoluteTimeGetCurrent() - checkStart
            favoriteSyncLog("YouTube reachability check \(result ? "ok" : "blocked") in \(formatSeconds(duration))s (async)")
            return result
        }
        
        // 第一阶段：先同步非 YouTube 收藏（与 YouTube 检查并行）
        await withTaskGroup(of: (Int, LiveModel?, String, String, String, LiveType, Double).self) { group in
            for (index, liveModel) in nonYoutubeRooms.enumerated() {
                group.addTask {
                    // 不在任务中修改 actor 属性，而是返回状态信息
                    let taskStart = CFAbsoluteTimeGetCurrent()
                    do {
                        let dataReq = try await ApiManager.fetchLastestLiveInfoFast(liveModel: liveModel)
                        let duration = CFAbsoluteTimeGetCurrent() - taskStart
                        if liveModel.liveType == .ks {
                            var finalLiveModel = liveModel
                            finalLiveModel.liveState = dataReq.liveState
                            return (index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", liveModel.liveType, duration)
                        } else {
                            return (index, dataReq, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", liveModel.liveType, duration)
                        }
                    } catch {
                        let duration = CFAbsoluteTimeGetCurrent() - taskStart
                        var errorModel = liveModel
                        if errorModel.liveType == .yy {
                            errorModel.liveState = LiveState.close.rawValue
                        } else {
                            errorModel.liveState = LiveState.unknow.rawValue
                        }
                        return (index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败", liveModel.liveType, duration)
                    }
                }
            }

            // 收集非 YouTube 结果
            var resultModels = [LiveModel?](repeating: nil, count: nonYoutubeRooms.count)
            for await (index, model, userName, platformName, status, liveType, duration) in group {
                self.currentProgress = (userName, platformName, status, index + 1, nonYoutubeRooms.count)
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
        }

        // 第二阶段：等待 YouTube 检查结果，如果可达则同步 YouTube 收藏
        let canLoadYoutube = await youtubeCheckTask.value
        if canLoadYoutube && !youtubeRooms.isEmpty {
            favoriteSyncLog("开始同步 YouTube 收藏，共 \(youtubeRooms.count) 个")
            await withTaskGroup(of: (Int, LiveModel?, String, String, String, LiveType, Double).self) { group in
                for (index, liveModel) in youtubeRooms.enumerated() {
                    group.addTask {
                        let taskStart = CFAbsoluteTimeGetCurrent()
                        do {
                            let dataReq = try await ApiManager.fetchLastestLiveInfoFast(liveModel: liveModel)
                            let duration = CFAbsoluteTimeGetCurrent() - taskStart
                            return (index, dataReq, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", liveModel.liveType, duration)
                        } catch {
                            let duration = CFAbsoluteTimeGetCurrent() - taskStart
                            var errorModel = liveModel
                            errorModel.liveState = LiveState.unknow.rawValue
                            return (index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败", liveModel.liveType, duration)
                        }
                    }
                }

                for await (index, model, userName, platformName, status, liveType, duration) in group {
                    self.currentProgress = (userName, platformName, status, nonYoutubeRooms.count + index + 1, roomList.count)
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
                        fetchedModels.append(model)
                    }
                }
            }
        } else if !youtubeRooms.isEmpty {
            favoriteSyncLog("YouTube 不可达，跳过 \(youtubeRooms.count) 个 YouTube 收藏")
        }

        let statusSyncDuration = CFAbsoluteTimeGetCurrent() - statusSyncStart
        let syncedCount = fetchedModels.count
        favoriteSyncLog("Live status sync finished \(syncedCount) rooms in \(formatSeconds(statusSyncDuration))s")

        let sortedPlatformStats = platformStats.sorted { $0.key.rawValue < $1.key.rawValue }
        for (liveType, stat) in sortedPlatformStats {
            let platformName = LiveParseTools.getLivePlatformName(liveType)
            let totalFavorites = platformFavoriteCounts[liveType] ?? stat.count
            let avg = stat.count > 0 ? stat.totalTime / Double(stat.count) : 0
            favoriteSyncLog("\(platformName): favorites \(totalFavorites), synced \(stat.count), total \(formatSeconds(stat.totalTime))s, avg \(formatSeconds(avg))s, success \(stat.success), fail \(stat.failure)")
        }

        let overallDuration = CFAbsoluteTimeGetCurrent() - overallStart
        favoriteSyncLog("Favorite sync total time \(formatSeconds(overallDuration))s")
        
        // 使用抽取的排序和分组方法，消除重复代码
        let sortedModels = fetchedModels.sortedByLiveState()
        let style = AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) ?? .liveState
        let groupedRoomList = sortedModels.groupedBySections(style: style)
        
        return (sortedModels, groupedRoomList)
    }


    public func getState() async -> (Bool, String)  {
        let stateString = await FavoriteService.getCloudState()
        return (stateString == "正常", stateString)
    }

    public func getCurrentProgress() async -> (String, String, String, Int, Int) {
        return currentProgress
    }
}

private func favoriteSyncLog(_ message: String) {
#if DEBUG
    print("[FavoriteSync] \(message)")
#endif
}

private func formatSeconds(_ seconds: Double) -> String {
    return String(format: "%.2f", seconds)
}
