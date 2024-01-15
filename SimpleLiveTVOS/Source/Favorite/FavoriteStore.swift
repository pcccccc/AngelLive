//
//  FavoriteStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import LiveParse

class FavoriteStore: ObservableObject {
    
    @Published var roomList: [LiveModel] = []
    @Published var isLoading: Bool = false
    
    init() {
        self.fetchFavoriteRoomList()
    }
    
    func fetchFavoriteRoomList() {
        isLoading = true
        Task {
            let roomList = try await CloudSQLManager.searchRecord()
            DispatchQueue.main.async {
                do {
                    self.isLoading = false
                    self.roomList = roomList
                }catch {
                    self.isLoading = false
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
    
    func getState() async throws -> String {
        return await CloudSQLManager.getCloudState()
    }
}
