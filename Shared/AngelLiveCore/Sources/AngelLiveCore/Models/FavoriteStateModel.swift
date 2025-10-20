//
//  FavoriteStateModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
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

    public init() {}

    public func syncStreamerLiveStates() async throws -> ([LiveModel], [FavoriteLiveSectionModel]) {
        var roomList: [LiveModel] = []
        do {
            roomList = try await FavoriteService.searchRecord()
        }catch {
            throw error
        }
        //获取是否可以访问google，如果网络环境不允许，则不获取youtube直播相关否则会卡很久
        let canLoadYoutube = await ApiManager.checkInternetConnection()
        for liveModel in roomList {
            if liveModel.liveType == .youtube && canLoadYoutube == false {
                print("当前网络环境无法获取Youtube房间状态\n本次将会跳过")
                break
            }
        }
        
        // 使用任务组并发获取房间状态
        var fetchedModels: [LiveModel] = []
        let filteredRoomList = roomList.filter { !(canLoadYoutube == false && $0.liveType == .youtube) }
        
        await withTaskGroup(of: (Int, LiveModel?, String, String, String).self) { group in
            for (index, liveModel) in filteredRoomList.enumerated() {
                print(index)
                group.addTask {
                    // 不在任务中修改 actor 属性，而是返回状态信息
                    do {
                        let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: liveModel)
                        if liveModel.liveType == .ks {
                            var finalLiveModel = liveModel
                            finalLiveModel.liveState = dataReq.liveState
                            print((index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功"))
                            return (index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功")
                        } else {
                            print(index, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功")
                            return (index, dataReq, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功")
                        }
                    } catch {
                        var errorModel = liveModel
                        if errorModel.liveType == .yy {
                            errorModel.liveState = LiveState.close.rawValue
                        } else {
                            errorModel.liveState = LiveState.unknow.rawValue
                        }
                        print((index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败"))
                        return (index, errorModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败")
                    }
                    
                }
            }
            
            // 收集结果并保持原始顺序
            var resultModels = [LiveModel?](repeating: nil, count: filteredRoomList.count)
            for await (index, model, userName, platformName, status) in group {
                // 在主 actor 上下文中更新进度信息
                self.currentProgress = (userName, platformName, status, index + 1, filteredRoomList.count)
                if let model = model {
                    resultModels[index] = model
                }
            }
            
            // 过滤掉nil值并添加到fetchedModels中
            fetchedModels = resultModels.compactMap { $0 }
        }
        
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
