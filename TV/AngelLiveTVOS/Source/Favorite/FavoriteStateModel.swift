//
//  favoriteModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import SwiftUI
import CloudKit
import Observation
import AngelLiveCore
import AngelLiveDependencies



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

        // 先重置状态，确保 UI 能感知变化
        self.cloudKitReady = false

        let state = await actor.getState()
        self.cloudKitStateString = state.1
        self.cloudKitReady = state.0  // 在设置 stateString 后再设置 ready 状态

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
                self.cloudKitStateString = "获取收藏列表失败：" + FavoriteService.formatErrorCode(error: error)
                progressTask.cancel()
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                cloudReturnError = true
            }
        }else {
            // cloudKitReady 为 false，不需要再次获取状态
            // cloudKitStateString 已经在上面设置过了
            syncProgressInfo = ("", "", "", 0, 0)
            isLoading = false
            cloudReturnError = true
        }
    }
    
    func addFavorite(room: LiveModel) async throws {
        try await FavoriteService.saveRecord(liveModel: room)
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
        try await FavoriteService.deleteRecord(liveModel: room)
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

