//
//  QRCodeStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI
import CloudKit
import AngelLiveDependencies
import AngelLiveCore

enum SimpleLiveSyncTaskState: CustomStringConvertible {
    case cleanOld
    case addICloud
    case syncFavorite
    case idle
    
    var description: String {
        switch self {
            case .cleanOld: return "清理旧数据"
            case .addICloud: return "同步收藏至iCloud"
            case .syncFavorite: return "拉取主播最新信息"
            case .idle: return "空闲"
        }
    }
}

@Observable
class QRCodeViewModel {

    private let actor = QRCodeActor()
    // 是否收到同步请求、 提示文字、 同步类型、 是否需要覆盖、 房间列表
    var currentState: (Bool, String, SimpleSyncType, Bool, [LiveModel]) = (false, "", .favorite, false, [])
    var fullScreenLoading: Bool = false
    var progressTask: Task<Void, Error>?
    var message = ""
    var fullScreenSyncState = ""
    var favoriteSyncTaskStart = false
    var currentTaskState = SimpleLiveSyncTaskState.idle
    var progress = 0.0
    var desc = ""
    var qrCodeKey = ""
    var isPlatformLogin = false
    var qrcodeUrl = "" {
        didSet {
            if isPlatformLogin == false {
                Task {
                    // 创建一个异步任务来处理进度更新
                    progressTask = Task { @MainActor in
                        while !Task.isCancelled {
                            currentState = actor.getCurrentState()
                            message = currentState.1
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                    }
                }
            }
        }
    }

    //Toast
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    
    @MainActor
    private func generateQRCode() async -> UIImage? {
        if let image = actor.generateQRCode(url: qrcodeUrl) {
            return image
        }
        return nil
    }

    func setupSyncServer() async {
        let resp = actor.setupSyncServer()
        qrcodeUrl = resp
    }

    func startSyncTask(appViewModel: AppState) async {
        actor.resetMessage()
        currentTaskState = .cleanOld
        fullScreenLoading = true
        let syncType = currentState.2
        let needOverlay = currentState.3
        let roomList = currentState.4
        if syncType == .favorite {
            appViewModel.favoriteViewModel.groupedRoomList.removeAll()
            let oldFavoriteListCount = appViewModel.favoriteViewModel.roomList.count
            if needOverlay {
                for (index, room) in appViewModel.favoriteViewModel.roomList.enumerated() {
                    do {
                        progress = Double(index) / Double(oldFavoriteListCount)
                        fullScreenSyncState = "正在清除旧收藏：第 \(index + 1) 个房间"
                        try await appViewModel.favoriteViewModel.removeFavoriteRoom(room: room)
                        fullScreenSyncState = "成功"
                    }catch {
                        fullScreenSyncState = "失败:\(SyncError.from(error).displayText)"
                    }
                }
            }
            currentTaskState = .addICloud
            for (index, newRoom) in roomList.enumerated() {
                progress = Double(index) / Double(roomList.count)
                if appViewModel.favoriteViewModel.roomList.contains(where: { $0.roomId == newRoom.roomId }) {
                    fullScreenSyncState = "失败:房间已存在"
                }else {
                    do {
                        fullScreenSyncState = "添加至iCloud: \(index + 1) / \(roomList.count)"
                        try await appViewModel.favoriteViewModel.addFavorite(room: newRoom)
                    }catch {
                        fullScreenSyncState = "失败:\(SyncError.from(error).displayText)"
                    }
                }
            }
            favoriteSyncTaskStart = true
            currentTaskState = .syncFavorite
            await appViewModel.favoriteViewModel.syncWithActor()
            favoriteSyncTaskStart = false
            currentTaskState = .idle
            showToast(true, title: "收藏同步完成")
            TopShelfManager.notifyContentChanged()
        } else if syncType == .history {
            if !appViewModel.pluginAvailability.hasAvailablePlugins {
                // ShellUI 保持原有同步行为，持久化修复仅作用于 FullUI。
                if needOverlay {
                    appViewModel.historyViewModel.watchList = roomList
                } else {
                    for room in roomList {
                        if appViewModel.historyViewModel.watchList.contains(where: { $0.roomId != room.roomId }) {
                            appViewModel.historyViewModel.watchList.append(room)
                        }
                    }
                }
            } else if needOverlay {
                appViewModel.historyViewModel.replaceHistories(roomList)
            } else {
                appViewModel.historyViewModel.mergeHistories(roomList)
            }
        }
        fullScreenLoading = false
        currentState = (false, "", .favorite, false, [])
    }
    
    func resetSyncTaskState() async {
        actor.resetCurrentState()
        favoriteSyncTaskStart = false
        fullScreenLoading = false
        currentState = (false, "", .favorite, false, [])
    }

    func stopSyncServer() {
        progressTask?.cancel()
        actor.closeServer()
        Logger.debug("停止", category: .ui)
    }
    
    func showToast(_ success: Bool, title: String, hideAfter: TimeInterval? = 1.5) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
        self.toastOptions = SimpleToastOptions(
            alignment: .topLeading, hideAfter: hideAfter
        )
    }
}

/// 在主 actor 上管理同步服务生命周期和界面状态。
@MainActor
final class QRCodeActor: SyncManagerDelegate {
    
    private var qrcode_url = ""
    private var message = ""
    private var qrcode_key = ""
    private var qrCodeImage: UIImage?
    private var syncManager: SyncManager?
    private var udpManager: UDPListener?
    private var syncType: SimpleSyncType?
    private var needOverlay: Bool?
    private var roomList: [LiveModel]?
    private var startSyncTask: Bool = false
    
    func resetMessage() {
        message = ""
    }
    
    func resetCurrentState() {
        startSyncTask = false
        message = "服务启动成功，请使用Simple Live手机版选中\(Common.hostName() ?? "")或扫描屏幕二维码\n或在客户端地址框内输入：\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
        syncType = nil
        needOverlay = nil
        roomList = nil
    }
    
    func getCurrentState() -> (Bool, String, SimpleSyncType, Bool, [LiveModel]) {
        return (startSyncTask, message, syncType ?? .favorite, needOverlay ?? false, roomList ?? [])
    }
    
    func generateQRCode(url: String) -> UIImage? {
        qrcode_url = url
        qrCodeImage = Common.generateQRCode(from: url)
        return qrCodeImage
    }
    
    func setupSyncServer() -> String {
        qrcode_url = "\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
        syncManager = SyncManager()
        syncManager?.delegate = self
        udpManager = UDPListener()
        message = "服务启动成功，请使用Simple Live手机版选中\(Common.hostName() ?? "")或扫描屏幕二维码\n或在客户端地址框内输入：\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
        return qrcode_url
    }
    
    func closeServer() {
        syncManager?.closeServer()
        udpManager?.closeServer()
        syncManager = nil
        udpManager = nil
    }
    
    func syncManagerDidConnectError(error: any Error) {
        updateMessage("服务启动失败，错误原因\(error.localizedDescription)，如果错误原因为端口占用，请关闭App几分钟后再试。")
    }

    func syncManagerDidReceiveRequest(type: SimpleSyncType, needOverlay: Bool, rooms: [LiveModel]) {
        updateSyncState(type: type, needOverlay: needOverlay, rooms: rooms)
    }

    // 新增一个隔离方法来更新消息
    func updateMessage(_ newMessage: String) {
       message = newMessage
    }

    // 新增一个隔离方法来更新同步状态
    func updateSyncState(type: SimpleSyncType, needOverlay: Bool, rooms: [LiveModel]) {
       self.startSyncTask = true
       self.syncType = type
       self.needOverlay = needOverlay
       self.roomList = rooms
       self.message = "收到\(type.description)请求，本次请求\(needOverlay ? "会" : "不会")覆盖你之前的数据。您确认要同步吗？"
    }
}
