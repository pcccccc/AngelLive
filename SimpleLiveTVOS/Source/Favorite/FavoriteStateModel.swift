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
    var cloudKitStateString: String = "正在检查状态"
    var syncProgressInfo: (String, String, String, Int, Int) = ("", "", "", 0, 0)  // 新增进度显示属性
    
    //Toast
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    
    @MainActor
    func syncWithActor() async {
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
            let resp = await actor.syncStreamerLiveStates()
            self.roomList = resp.0
            self.groupedRoomList = resp.1
            progressTask.cancel()
            isLoading = false
        }else {
            isLoading = false
        }
    }
    
    func addFavorite(room: LiveModel) async throws {
        try await CloudSQLManager.saveRecord(liveModel: room)
        self.roomList.append(room)
    }
    
    func removeFavoriteRoom(room: LiveModel) async throws {
        try await CloudSQLManager.deleteRecord(liveModel: room)
        let index = roomList.firstIndex(of: room)
        if index != nil {
            self.roomList.remove(at: index!)
        }
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
}

actor FavoriteStateModel: ObservableObject {
    
    var currentProgress: (String, String, String, Int, Int) = ("", "", "", 0, 0)
    
    func syncStreamerLiveStates() async -> ([LiveModel], [FavoriteLiveSectionModel]) {
        var roomList: [LiveModel] = []
        do {
            roomList = try await CloudSQLManager.searchRecord()
        }catch {
            print("获取收藏列表失败: \(error)")
        }
        //获取是否可以访问google，如果网络环境不允许，则不获取youtube直播相关否则会卡很久
        let canLoadYoutube = await ApiManager.checkInternetConnection()
        for liveModel in roomList {
            if liveModel.liveType == .youtube && canLoadYoutube == false {
                print("当前网络环境无法获取Youtube房间状态\n本次将会跳过")
                break
            }
        }
        var fetchedModels: [LiveModel] = []
        var bilibiliModels: [LiveModel] = []
        for liveModel in roomList {
            if liveModel.liveType == .bilibili {
                bilibiliModels.append(liveModel)
            }else if liveModel.liveType == .youtube && canLoadYoutube == false {
                continue
            }else {
                do {
                    currentProgress = (liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "同步中", fetchedModels.count + 1, roomList.count)
                    let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: liveModel)
                    currentProgress = (liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "成功", fetchedModels.count + 1, roomList.count)
                    if liveModel.liveType == .ks {
                        var finalLiveModel = liveModel
                        finalLiveModel.liveState = dataReq.liveState
                        fetchedModels.append(finalLiveModel)
                    }else {
                        fetchedModels.append(dataReq)
                    }
                } catch {
                    currentProgress = (liveModel.userName, LiveParseTools.getLivePlatformName(liveModel.liveType), "失败", fetchedModels.count + 1, roomList.count)
                    var errorModel = liveModel
                    if errorModel.liveType == .yy {
                        errorModel.liveState = LiveState.close.rawValue
                    }else {
                        errorModel.liveState = LiveState.unknow.rawValue
                    }
                    fetchedModels.append(errorModel)
                }
            }
        }
        
        //B站可能存在风控，触发条件为访问过快或没有Cookie？
        if bilibiliModels.count > 0 {
            print("同步除B站主播状态成功, 开始同步B站主播状态,预计时间\(Double(bilibiliModels.count) * 1.5)秒")
        }
        for item in bilibiliModels {
            do {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 等待1.5秒
                currentProgress = (item.userName, LiveParseTools.getLivePlatformName(item.liveType), "同步中", fetchedModels.count + 1, roomList.count)
                let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: item)
                currentProgress = (item.userName, LiveParseTools.getLivePlatformName(item.liveType), "成功", fetchedModels.count + 1, roomList.count)
                fetchedModels.append(dataReq)
            }catch {
                currentProgress = (item.userName, LiveParseTools.getLivePlatformName(item.liveType), "失败", fetchedModels.count + 1, roomList.count)
            }
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
