//
//  FavoriteStateModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import Foundation
import LiveParse

public final class FavoriteLiveSectionModel: Identifiable, @unchecked Sendable {
    public var id = UUID()
    public var roomList: [LiveModel] = []
    public var title: String = ""
    public var type: LiveType = .bilibili

    public init() {}
}

public actor FavoriteStateModel: ObservableObject {

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

        //获取是否可以访问google，如果网络环境不允许，则不获取youtube直播相关否则会卡很久
        let youtubeCheckStart = CFAbsoluteTimeGetCurrent()
        let canLoadYoutube = await ApiManager.checkInternetConnection()
        let youtubeCheckDuration = CFAbsoluteTimeGetCurrent() - youtubeCheckStart
        favoriteSyncLog("YouTube reachability check \(canLoadYoutube ? "ok" : "blocked") in \(formatSeconds(youtubeCheckDuration))s")
        for liveModel in roomList {
            if liveModel.liveType == .youtube && canLoadYoutube == false {
                print("当前网络环境无法获取Youtube房间状态\n本次将会跳过")
                break
            }
        }
        
        // 使用任务组并发获取房间状态
        var fetchedModels: [LiveModel] = []
        var platformStats: [LiveType: (count: Int, totalTime: Double, success: Int, failure: Int)] = [:]
        let filteredRoomList = roomList.filter { !(canLoadYoutube == false && $0.liveType == .youtube) }
        let statusSyncStart = CFAbsoluteTimeGetCurrent()
        
        await withTaskGroup(of: (Int, LiveModel?, String, String, String, LiveType, Double).self) { group in
            for (index, liveModel) in filteredRoomList.enumerated() {
                print(index)
                group.addTask {
                    // 不在任务中修改 actor 属性，而是返回状态信息
                    let taskStart = CFAbsoluteTimeGetCurrent()
                    do {
                        let dataReq = try await ApiManager.fetchLastestLiveInfoFast(liveModel: liveModel)
                        let duration = CFAbsoluteTimeGetCurrent() - taskStart
                        if liveModel.liveType == .ks {
                            var finalLiveModel = liveModel
                            finalLiveModel.liveState = dataReq.liveState
                            print((index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功"))
                            return (index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", liveModel.liveType, duration)
                        } else {
                            print(index, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功")
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
                        print((index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败"))
                        return (index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败", liveModel.liveType, duration)
                    }
                    
                }
            }
            
            // 收集结果并保持原始顺序
            var resultModels = [LiveModel?](repeating: nil, count: filteredRoomList.count)
            for await (index, model, userName, platformName, status, liveType, duration) in group {
                // 在主 actor 上下文中更新进度信息
                self.currentProgress = (userName, platformName, status, index + 1, filteredRoomList.count)
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
            
            // 过滤掉nil值并添加到fetchedModels中
            fetchedModels = resultModels.compactMap { $0 }
        }

        let statusSyncDuration = CFAbsoluteTimeGetCurrent() - statusSyncStart
        favoriteSyncLog("Live status sync finished \(filteredRoomList.count) rooms in \(formatSeconds(statusSyncDuration))s")

        let sortedPlatformStats = platformStats.sorted { $0.key.rawValue < $1.key.rawValue }
        for (liveType, stat) in sortedPlatformStats {
            let platformName = LiveParseTools.getLivePlatformName(liveType)
            let totalFavorites = platformFavoriteCounts[liveType] ?? stat.count
            let avg = stat.count > 0 ? stat.totalTime / Double(stat.count) : 0
            favoriteSyncLog("\(platformName): favorites \(totalFavorites), synced \(stat.count), total \(formatSeconds(stat.totalTime))s, avg \(formatSeconds(avg))s, success \(stat.success), fail \(stat.failure)")
        }

        let overallDuration = CFAbsoluteTimeGetCurrent() - overallStart
        favoriteSyncLog("Favorite sync total time \(formatSeconds(overallDuration))s")
        
        let sortedModels = fetchedModels.sorted { firstModel, secondModel in
            switch (firstModel.liveState, secondModel.liveState) {
                case ("1", "1"):
                    return true // 两个都是1，保持原有顺序
                case ("1", _):
                    return true // 第一个是1，应该排在前面
                case (_, "1"):
                    return false // 第二个是1，应该排在前面
                case ("2", "2"):
                    return true // 两个都是2，保持原有顺序
                case ("2", _):
                    return true // 第一个是2，应该排在非1的前面
                case (_, "2"):
                    return false // 第二个是2，应该排在非1的前面
                default:
                    return true // 两个都不是1和2，保持原有顺序
            }
        }
        roomList = sortedModels
        var groupedRoomList: [FavoriteLiveSectionModel] = []
        if AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) == .section {
            let types = Set(sortedModels.map { $0.liveType })
            let formatedRoomList = types.map { type in
                roomList.filter { $0.liveType == type }
            }
            for array in formatedRoomList {
                let model = FavoriteLiveSectionModel()
                model.roomList = array
                model.title = LiveParseTools.getLivePlatformName(array.first?.liveType ?? .bilibili)
                model.type = array.first?.liveType ?? .bilibili
                groupedRoomList.append(model)
            }
            groupedRoomList = groupedRoomList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }else {
            let types = Set(sortedModels.map { $0.liveState })
            let formatedRoomList = types.map { state in
                roomList.filter { $0.liveState == state }
            }
            for array in formatedRoomList {
                let model = FavoriteLiveSectionModel()
                model.roomList = array
                model.title = array.first?.liveStateFormat() ?? "未知状态"
                model.type = array.first?.liveType ?? .bilibili
                groupedRoomList.append(model)
            }
            groupedRoomList = groupedRoomList.sorted { model1, model2 in
                let order = ["正在直播", "回放/轮播", "已下播", "未知状态"]
                if let index1 = order.firstIndex(of: model1.title),
                   let index2 = order.firstIndex(of: model2.title) {
                    return index1 < index2
                }
                return model1.title < model2.title
            }
        }
        return (roomList,groupedRoomList)
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
