//
//  FavoriteStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import LiveParse
import SwiftUI

class FavoriteStore: ObservableObject {
    
    @Published var roomList: [LiveModel] = []
    @Published var isLoading: Bool = false
    @Published var cloudKitReady: Bool = false
    @Published var cloudKitStateString: String = "正在检查状态"
    
    init() {
        self.fetchFavoriteRoomList()
        self.getState()
    }
    
    func fetchFavoriteRoomList() {
        withAnimation(.easeInOut(duration: 0.25)) {
            self.isLoading = true
        }
        Task {
            do {
                let roomList = try await CloudSQLManager.searchRecord()
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.isLoading = false
                    }
                    self.roomList = roomList
                }
            }catch {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.isLoading = false
                    }
                }
            }
            
        }
    }
    
    func addFavorite(room: LiveModel) async throws {
        try await CloudSQLManager.saveRecord(liveModel: room)
        DispatchQueue.main.async {
            self.roomList.append(room)
        }
    }
    
    func removeFavoriteRoom(room: LiveModel) async throws {
        try await CloudSQLManager.deleteRecord(liveModel: room)
        let index = roomList.firstIndex(of: room)
        if index != nil {
            DispatchQueue.main.async {
                self.roomList.remove(at: index!)
            }
        }
    }
    
    func getState() {
        Task {
            let stateString = await CloudSQLManager.getCloudState()
            DispatchQueue.main.async {
                self.cloudKitStateString = stateString
                if stateString == "正常" {
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
}
