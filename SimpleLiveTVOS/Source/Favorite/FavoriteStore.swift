//
//  FavoriteStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import LiveParse
import SwiftUI
import CloudKit

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
    
    func formatErrorCode(error: Error) -> String {
        let theError = error as! CKError
        switch theError.code {
        case .internalError:
            return "iCloud内部错误，请稍后再试"
        case .partialFailure, .networkUnavailable:
            return "网络不可用，请检查网络问题"
        case .badContainer:
            return "容器错误，请联系开发者"
        case .serviceUnavailable:
            return "CloudKit暂停服务，请稍后再试"
        case .requestRateLimited:
            return "操作频繁，请稍后再试"
        case .missingEntitlement:
            return "操作权限异常，请检查iCloud账户状态"
        case .notAuthenticated:
            return "未登录，请检查iCloud账户状态"
        case .permissionFailure:
            return "权限异常，请检查iCloud账户状态"
        case .unknownItem:
            return "操作记录不存在，请更新收藏列表"
        case .invalidArguments:
            return "错误请求，请更新收藏列表"
        case .serverRecordChanged:
            return "请求结果与iCloud不一致，请更新收藏列表"
        case .serverRejectedRequest:
            return "iCloud服务器拒绝了请求，请更新收藏列表"
        case .assetFileNotFound:
            return "文件未找到"
        case .assetFileModified:
            return "保存文件时文件被修改"
        case .incompatibleVersion:
            return "iCloud版本不兼容"
        case .constraintViolation:
            return "唯一字段冲突"
        case .operationCancelled:
            return "操作取消，请重试"
        case .changeTokenExpired:
            return "token异常，请重新登录Apple ID"
        case .batchRequestFailed:
            return "有其他线程访问，请稍后再试"
        case  .zoneBusy:
            return "iCloud服务器繁忙，请稍后再试"
        case .badDatabase:
            return "iCloud数据库异常"
        case .quotaExceeded:
            return "iCloud存储已满，请清理空间后再试"
        case .zoneNotFound:
            return "iCloud不存在此区域，请联系开发者"
        case .limitExceeded:
            return "对服务器的请求太大，请联系开发者"
        case .userDeletedZone:
            return "区域不存在"
        case .tooManyParticipants:
            return "同时操作用户多过，请稍后再试"
        case .alreadyShared:
            return "无法保存"
        case .referenceViolation:
            return "未找到共享区域"
        case .managedAccountRestricted:
            return "由于管理账户限制，请求被拒绝"
        default:
            return "未知错误"
        }
    }
}
