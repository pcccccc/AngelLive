//
//  favoriteModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import LiveParse
import SwiftUI
import CloudKit
import Observation
import SimpleToast

class FavoriteLiveSectionModel: Identifiable {
    var id = UUID()
    var roomList: [LiveModel] = []
    var title: String = ""
    var type: LiveType = .bilibili
}

@Observable
class AppFavoriteModel {
    let actor = FavoriteStateModel()
    var groupedRoomList: [FavoriteLiveSectionModel] = []
    var roomList: [LiveModel] = []
    var isLoading: Bool = false
    var cloudKitReady: Bool = false
    var cloudKitStateString: String = "正在检查iCloud状态"
    var syncProgressInfo: (String, String, String, Int, Int) = ("", "", "", 0, 0)  // 新增进度显示属性
    var cloudReturnError = false
    
    //Toast
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    
    @MainActor
    func syncWithActor() async {
        roomList.removeAll()
        groupedRoomList.removeAll()
        cloudReturnError = false
        syncProgressInfo = ("", "", "", 0, 0)
        self.isLoading = true
        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1
        if self.cloudKitReady {
            // 创建一个异步任务来处理进度更新
            let progressTask = Task { @MainActor in
                while !Task.isCancelled {
                    let progress = await actor.getCurrentProgress()
                    self.syncProgressInfo = progress
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            do {
                let resp = try await actor.syncStreamerLiveStates()
                self.roomList = resp.0
                self.groupedRoomList = resp.1
                progressTask.cancel()
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
            }catch {
                self.cloudKitStateString = "获取收藏列表失败：" + CloudSQLManager.formatErrorCode(error: error)
                progressTask.cancel()
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                cloudReturnError = true
            }
        }else {
            let state = await CloudSQLManager.getCloudState()
            if state == "无法确定状态" {
                self.cloudKitStateString = "iCloud状态可能存在假登录，当前状态：" + state + "请尝试将Apple TV断电后重新在设置APP中登录iCloud"
            }else {
                self.cloudKitStateString = state
            }
            syncProgressInfo = ("", "", "", 0, 0)
            isLoading = false
            cloudReturnError = true
        }
    }
    
    func addFavorite(room: LiveModel) async throws {
        try await CloudSQLManager.saveRecord(liveModel: room)
        var favIndex = -1
        for (index, favoriteRoom) in roomList.enumerated() {
            if LiveState(rawValue: favoriteRoom.liveState ?? "3") != .live {
                favIndex = index
                break
            }
        }
        if favIndex != -1 {
            roomList.insert(room, at: favIndex)
        }
        roomList.append(room)
        if AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) == .section {
            for (index, model) in groupedRoomList.enumerated() {
                if model.type == room.liveType {
                    groupedRoomList[index].roomList.append(room)
                    break
                }
            }
        }else {
            for (index, model) in groupedRoomList.enumerated() {
                if model.title == room.liveStateFormat() {
                    groupedRoomList[index].roomList.append(room)
                    break
                }
            }
        }
    }
    
    func removeFavoriteRoom(room: LiveModel) async throws {
        try await CloudSQLManager.deleteRecord(liveModel: room)
        let index = roomList.firstIndex(of: room)
        if index != nil {
            self.roomList.remove(at: index!)
        }
        for (index, model) in groupedRoomList.enumerated() {
            if model.id == room.id {
                groupedRoomList.remove(at: index)
                break
            }
        }
        refreshView()
    }
    
    //MARK: 操作相关
    func showToast(_ success: Bool, title: String, hideAfter: TimeInterval? = 1.5) {
        showToast = true
        toastTitle = title
        toastTypeIsSuccess = success
        toastOptions = SimpleToastOptions(
            alignment: .topLeading, hideAfter: hideAfter
        )
    }
    
    func refreshView() {
        let theRoomList = roomList
        roomList.removeAll()
        roomList = theRoomList
        var groupedRoomList: [FavoriteLiveSectionModel] = []
        if AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) == .section {
            let types = Set(roomList.map { $0.liveType })
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
            self.groupedRoomList = groupedRoomList
        }else {
            let types = Set(roomList.map { $0.liveState })
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
            self.groupedRoomList = groupedRoomList
        }
    }
}

actor FavoriteStateModel: ObservableObject {
    
    var currentProgress: (String, String, String, Int, Int) = ("", "", "", 0, 0)
    
    func syncStreamerLiveStates() async throws -> ([LiveModel], [FavoriteLiveSectionModel]) {
        var roomList: [LiveModel] = []
        do {
            roomList = try await CloudSQLManager.searchRecord()
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
                group.addTask {
                    // 不在任务中修改 actor 属性，而是返回状态信息
                    do {
                        let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: liveModel)
                        if liveModel.liveType == .ks {
                            var finalLiveModel = liveModel
                            finalLiveModel.liveState = dataReq.liveState
                            return (index, finalLiveModel, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功")
                        } else {
                            return (index, dataReq, liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功")
                        }
                    } catch {
                        var errorModel = liveModel
                        if errorModel.liveType == .yy {
                            errorModel.liveState = LiveState.close.rawValue
                        } else {
                            errorModel.liveState = LiveState.unknow.rawValue
                        }
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


    func getState() async -> (Bool, String)  {
        let stateString = await CloudSQLManager.getCloudState()
        return (stateString == "正常", stateString)
    }
    
    func getCurrentProgress() async -> (String, String, String, Int, Int) {
        return currentProgress
    }
}
