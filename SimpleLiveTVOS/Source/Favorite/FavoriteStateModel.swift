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


actor FavoriteStateModel: ObservableObject {
    
    var roomList: [LiveModel] = []
    var isLoading: Bool = false
    var cloudKitReady: Bool = false
    var cloudKitStateString: String = "正在检查状态"
    
    init() {
        Task { await self.getState() }
    }
    
    func fetchFavoriteRoomList() async {
        self.isLoading = true
        do {
            if self.cloudKitReady == true {
                let roomList = try await CloudSQLManager.searchRecord()
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isLoading = false
                }
                self.roomList = roomList
            }
        }catch {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.cloudKitStateString = CloudSQLManager.formatErrorCode(error: error)
                self.isLoading = false
                self.cloudKitReady = false
            }
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
    
    func getState() {
        Task {
            self.cloudKitStateString = "正在获取iCloud状态"
            let stateString = await CloudSQLManager.getCloudState()
            self.cloudKitStateString = stateString
            if stateString == "正常" {
                Task {
                    await self.fetchFavoriteRoomList()
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.cloudKitReady = true
                }
            }else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.cloudKitReady = false
                }
            }
        }
    }
}
