//
//  QRCodeStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI
import LiveParse
import SimpleToast
import CloudKit


enum QRCodeType {
    case bilibiliLogin
    case syncServer
}

class QRCodeStore: ObservableObject {
    @Published var qrcode_url = "" {
        didSet {
            generateQRCode()
        }
    }
    @Published var message = ""
    @Published var qrcode_key = ""
    @Published var qrCodeImage: UIImage?
    @Published var qrCodeType: QRCodeType? = .syncServer {
        didSet {
            if qrCodeType == .syncServer {
                qrcode_url = "\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
                message = "服务启动成功，请使用Simple Live手机版选中\(Common.hostName() ?? "")或扫描屏幕二维码\n或在客户端地址框内输入：\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
                syncManager = SyncManager()
                udpManager = UDPListener()
                syncManager?.delegate = self
            }
        }
    }
    
    @Published var syncManager: SyncManager?
    @Published var udpManager: UDPListener?
    @Published var favoriteModel: FavoriteStateModel?
    
    @Published var syncType: SimpleSyncType? {
        didSet {
            switch syncType {
                case .favorite:
                    syncTypeString = "收藏同步"
                case .history:
                    syncTypeString = "观看历史同步"
                case .danmuBlockWords:
                    syncTypeString = "弹幕屏蔽词同步"
                case .bilibiliCookie:
                    syncTypeString = "Bilibili登录信息同步"
                case nil:
                    syncTypeString = ""
            }
        }
    }
    @Published var needOverlay: Bool?
    @Published var roomList: [LiveModel]?
    @Published var showAlert: Bool = false
    @Published var syncTypeString = ""
    
    @Published var showToast: Bool = false
    @Published var toastTitle: String = ""
    @Published var toastTypeIsSuccess: Bool = false
    @Published var toastOptions = SimpleToastOptions(
        hideAfter: 1.5
    )
    
    @Published var showFullScreenLoading = false
    @Published var showFullScreenLoadingText = ""
    @AppStorage("SimpleLive.History.WatchList") public var watchList: Array<LiveModel> = []
   
    func generateQRCode() {
        qrCodeImage = Common.generateQRCode(from: qrcode_url)
    }
    
    func beginSync() async {
        if self.syncType == .favorite {
            let stateString = await CloudSQLManager.getCloudState()
            if stateString == "正常" {
                DispatchQueue.main.async {
                    self.showFullScreenLoading = true
                    self.showFullScreenLoadingText = "正在进行同步"
                }
                await startFavoriteSync()
            }else {
                showToast(false, title: stateString)
            }
        } else if self.syncType == .history {
            DispatchQueue.main.async {
                self.showFullScreenLoading = true
                self.showFullScreenLoadingText = "正在进行同步"
            }
            await startHistorySync()
        }
    }
    
    //MARK: 操作相关
    
    func showToast(_ success: Bool, title: String) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
    }
    
    func startFavoriteSync() async {
        if self.needOverlay == true {
            do {
                if let roomList = favoriteModel?.roomList {
                    for index in roomList.indices {
                        DispatchQueue.main.async {
                            self.showFullScreenLoadingText = "正在清理第\(index + 1)个本地收藏"
                        }
                        let roomModel = roomList[index]
                        try await favoriteModel?.removeFavoriteRoom(room: roomModel)
                    }
                }
                if let newRoomList = self.roomList {
                    for index in newRoomList.indices {
                        DispatchQueue.main.async {
                            self.showFullScreenLoadingText = "正在添加第\(index + 1)/\(newRoomList.count)个新收藏"
                        }
                        let roomModel = newRoomList[index]
                        let newLiveModel = try await ApiManager.fetchLastestLiveInfo(liveModel: roomModel)
                        try await favoriteModel?.addFavorite(room: newLiveModel)
                    }
                    DispatchQueue.main.async {
                        self.showFullScreenLoading = false
                        self.showToast(true, title: "同步\(newRoomList.count)个收藏成功")
                    }
                }
            }catch {
                if type(of: error) == CKError.self {
                    showFullScreenLoadingText = CloudSQLManager.formatErrorCode(error: error as! CKError) ?? ""
                }else {
                    showFullScreenLoadingText = "\(error)"
                }
            }
        }else {
            do {
                var repeatCount = 0
                if let newRoomList = self.roomList {
                    for index in newRoomList.indices {
                        var has = false
                        let roomModel = newRoomList[index]
                        DispatchQueue.main.async {
                            self.showFullScreenLoadingText = "正在添加第\(index + 1)/\(newRoomList.count)个新收藏"
                        }
                        if let deviceFavoriteRoomList = favoriteModel?.roomList {
                            for room in deviceFavoriteRoomList {
                                if room.roomId == roomModel.roomId {
                                    has = true
                                    DispatchQueue.main.async {
                                        self.showFullScreenLoadingText = "第\(index + 1)个新收藏重复，已经跳过"
                                    }
                                }
                            }
                        }
                        if has == true {
                            repeatCount += 1
                            continue
                        }
                        let newLiveModel = try await ApiManager.fetchLastestLiveInfo(liveModel: roomModel)
                        try await favoriteModel?.addFavorite(room: newLiveModel)
                    }
                    let repeatString = repeatCount > 0 ? "(重复\(repeatCount)个）": ""
                    DispatchQueue.main.async {
                        self.showFullScreenLoading = false
                        self.showToast(true, title: "同步\(newRoomList.count)个收藏成功\(repeatString)")
                    }
                }
            }catch {
                if type(of: error) == CKError.self {
                    showFullScreenLoadingText = CloudSQLManager.formatErrorCode(error: error as! CKError) ?? ""
                }else {
                    showFullScreenLoadingText = "\(error)"
                }
            }
        }
    }
    
    func startHistorySync() async {
        DispatchQueue.main.async {
            self.showFullScreenLoadingText = "正在清理本地历史记录"
        }
        if self.needOverlay == true {
            DispatchQueue.main.async {
                self.watchList.removeAll()
                self.showFullScreenLoadingText = "成功清理本地历史记录"
            }
        }
        do {
            if let roomList = self.roomList {
                for index in roomList.indices {
                    let room = roomList[index]
                    if self.watchList.contains(where: { room.roomId == $0.roomId }) == false {
                        let newLiveModel = try await ApiManager.fetchLastestLiveInfo(liveModel: room)
                        DispatchQueue.main.async {
                            self.showFullScreenLoadingText = "正在添加第\(index + 1)个历史记录"
                            self.watchList.insert(newLiveModel, at: 0)
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.showFullScreenLoading = false
                    self.showToast(true, title: "同步历史记录成功")
                }
            }
        }catch {
            DispatchQueue.main.async {
                self.showFullScreenLoadingText = "\(error)"
            }
        }
        
    }
    
    deinit {
        syncManager?.closeServer()
        udpManager?.closeServer()
    }
    
    func closeServer() {
        syncManager?.closeServer()
        udpManager?.closeServer()
        syncManager = nil
        udpManager = nil
    }
    
    @MainActor func updateSyncInfo(type: SimpleSyncType, needOverlay: Bool, info: [LiveModel]) {
        DispatchQueue.main.async {
            self.syncType = type
            self.needOverlay = needOverlay
            self.roomList = info
            self.showAlert = true
        }
    }
    
}

extension QRCodeStore: SyncManagerDelegate {
    func syncManagerDidConnectError(error: Error) {
        message = "服务启动失败，错误原因\(error),如果错误原因为端口占用，请关闭App几分钟后再试。"
    }
    
    
    @MainActor func syncManagerDidReciveRequest(type: SimpleSyncType, needOverlay: Bool, info: Any) {
        updateSyncInfo(type: type, needOverlay: needOverlay, info: info as? [LiveModel] ?? [])
    }
    
    
}
