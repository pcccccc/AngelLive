//
//  CloudSQLManager.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/19.
//

import Foundation
import CloudKit
import LiveParse

let roomId_colum_cloud = "room_id"
let userId_column_cloud = "user_id"
let userName_column_cloud = "user_name"
let roomTitle_column_cloud = "room_title"
let roomCover_column_cloud = "room_cover"
let userHeadImg_column_cloud = "user_head_img"
let liveType_column_cloud =  "live_type"
let liveState_column_cloud = "live_state"
let ck_identifier = "iCloud.icloud.dev.igod.simplelive"

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
    
    
}

class CloudSQLManager: NSObject {
    
    class func saveRecord(liveModel: LiveModel) async throws {
        let rec = CKRecord(recordType: "favorite_streamers")
        rec.setValue(liveModel.roomId, forKey: roomId_colum_cloud)
        rec.setValue(liveModel.userId, forKey: userId_column_cloud)
        rec.setValue(liveModel.userName, forKey: userName_column_cloud)
        rec.setValue(liveModel.roomTitle, forKey: roomTitle_column_cloud)
        rec.setValue(liveModel.roomCover, forKey: roomCover_column_cloud)
        rec.setValue(liveModel.userHeadImg, forKey: userHeadImg_column_cloud)
        rec.setValue(liveModel.liveType.rawValue, forKey: liveType_column_cloud)
        rec.setValue(liveModel.liveState ?? "", forKey: liveState_column_cloud)
        try await CKContainer(identifier: ck_identifier).privateCloudDatabase.save(rec)
    }
    
    class func searchRecord(roomId: String) async throws -> [LiveModel] {
        let container = CKContainer(identifier: ck_identifier)
        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: " \(roomId_colum_cloud) = '\(roomId)' ")
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        let recordArray = try await database.perform(query, inZoneWith: CKRecordZone.default().zoneID)
        var temp: Array<LiveModel> = []
        for record in recordArray {
            temp.append(LiveModel(userName: record.value(forKey: userName_column_cloud) as? String ?? "", roomTitle: record.value(forKey: roomTitle_column_cloud) as? String ?? "", roomCover: record.value(forKey: roomCover_column_cloud) as? String ?? "", userHeadImg: record.value(forKey: userHeadImg_column_cloud) as? String ?? "", liveType: LiveType(rawValue: record.value(forKey: liveType_column_cloud) as? String ?? "") ?? .bilibili, liveState: record.value(forKey: liveState_column_cloud) as? String ?? "", userId: record.value(forKey: userId_column_cloud) as? String ?? "", roomId: record.value(forKey: roomId_colum_cloud) as? String ?? "", liveWatchedCount: nil))
        }
        return temp
    }
    
    class func searchRecord() async throws -> [LiveModel] {
        let container = CKContainer(identifier: ck_identifier)
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "favorite_streamers", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        let recordArray = try await database.perform(query, inZoneWith: CKRecordZone.default().zoneID)
        var temp: Array<LiveModel> = []
        for record in recordArray {
            temp.append(LiveModel(userName: record.value(forKey: userName_column_cloud) as? String ?? "", roomTitle: record.value(forKey: roomTitle_column_cloud) as? String ?? "", roomCover: record.value(forKey: roomCover_column_cloud) as? String ?? "", userHeadImg: record.value(forKey: userHeadImg_column_cloud) as? String ?? "", liveType: LiveType(rawValue: record.value(forKey: liveType_column_cloud) as? String ?? "") ?? .bilibili, liveState: record.value(forKey: liveState_column_cloud) as? String ?? "", userId: record.value(forKey: userId_column_cloud) as? String ?? "", roomId: record.value(forKey: roomId_colum_cloud) as? String ?? "", liveWatchedCount: nil))
        }
        return temp
    }
    
    class func deleteRecord(liveModel: LiveModel) async throws {

        let container = CKContainer(identifier: ck_identifier)
        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: " \(roomId_colum_cloud) = '\(liveModel.roomId)' ")
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        let recordArray = try await database.perform(query, inZoneWith: CKRecordZone.default().zoneID)
        if recordArray.count > 0 {
            try await database.deleteRecord(withID: recordArray.first!.recordID)
        }
    }
    
    class func getCloudState() async -> String {
        do {
            let status = try await CKContainer(identifier: ck_identifier).accountStatus()
            switch status {
                case .available:
                    return "正常"
                case .couldNotDetermine:
                    return "无法确定状态"
                case .restricted:
                    return "受限"
                case .noAccount:
                    return "请登录iCloud"
                case .temporarilyUnavailable:
                    return "暂时不可用，请尝试更新Apple ID设置"
                default:
                    return "无法确定状态"
            }
        }catch {
            return error.localizedDescription
        }
    }
}


