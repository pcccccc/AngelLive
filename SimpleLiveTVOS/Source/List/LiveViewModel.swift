//
//  LiveViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import LiveParse
import SwiftUI
import Observation
import Cache
import SimpleToast

enum LiveRoomListType {
    case live
    case favorite
    case history
    case search
}


@Observable
class LiveViewModel {
    
    let leftMenuMinWidth: CGFloat = 180
    let leftMenuMaxWidth: CGFloat = 300
    let leftMenuMinHeight: CGFloat = 50
    let leftMenuMaxHeight: CGFloat = 1080
    
    //房间列表分类
    var roomListType: LiveRoomListType
    //直播分类
    var liveType: LiveType
    //分类名
    var livePlatformName: String = ""
    
    //菜单列表
    var categories: [LiveMainListModel] = []
    var showOverlay: Bool = false {
        didSet {
            leftWidth = showOverlay == true ? leftMenuMaxWidth : leftMenuMinWidth
            leftHeight = showOverlay == true ? leftMenuMaxHeight : leftMenuMinHeight
            leftMenuCornerRadius = showOverlay == true ? 10 : 25
        }
    }
    var leftListOverlay: CGFloat = 0
    var leftWidth: CGFloat = 180
    var leftHeight: CGFloat = 60
    var leftMenuCornerRadius: CGFloat = 30
    var menuTitleIcon: String = ""
    
    //当前选中的主分类与子分类
    var selectedMainListCategory: LiveMainListModel?
    var selectedSubCategory: [LiveCategoryModel] = []
    var selectedSubListIndex: Int = -1
    var selectedRoomListIndex: Int = -1
    
    //加载状态
    var isLoading = false
   
    //直播列表分页
    var subPageNumber = 0
    var subPageSize = 20
    var roomPage: Int = 1 {
        didSet {
            if roomListType == .favorite {
                return
            }
            getRoomList(index: selectedSubListIndex)
        }
    }
    var roomList: [LiveModel] = []
    var favoriteRoomList: [LiveModel] = []
    var currentRoom: LiveModel?
    /*{
     didSet {
         currentRoomIsFavorited = favoriteModel.roomList.contains { $0.roomId == currentRoom!.roomId }
     }
     }*/
    
    //当前选择房间ViewModel
    var roomInfoViewModel: RoomInfoViewModel?

    var isLeftFocused: Bool = false
    
    var loadingText: String = "正在获取内容"
    var searchTypeArray = ["关键词", "链接/分享口令/房间号", "Youtube链接/VideoId"]
    var searchTypeIndex = 0
    var searchText: String = ""
    var showAlert: Bool = false
    var currentRoomIsFavorited: Bool = false
    
    var appViewModel: SimpleLiveViewModel
    
    //Toast
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    
    init(roomListType: LiveRoomListType, liveType: LiveType, appViewModel: SimpleLiveViewModel) {
        self.liveType = liveType
        self.roomListType = roomListType
        self.appViewModel = appViewModel
        menuTitleIcon = Common.getImage(liveType)
        switch roomListType {
            case .live:
                Task {
                    await getCategoryList()
                }
            case .favorite:
                getRoomList(index: 0)
            case .history:
                getRoomList(index: 0)
            default:
                break
                
        }
    }

    /**
     获取平台直播分类。
     
     - 展示左侧列表子列表
    */
    @MainActor func showSubCategoryList(currentCategory: LiveMainListModel) {
        if self.selectedSubCategory.count == 0 {
            self.selectedMainListCategory = currentCategory
            self.selectedSubCategory.removeAll()
            self.getSubCategoryList()
        }else {
            self.selectedSubCategory.removeAll()
        }
    }
    
    //MARK: 获取相关
    
    /**
     获取平台直播分类。
     
     - Returns: 平台直播分类（包含子分类）。
    */
    @MainActor func getCategoryList() async {
        livePlatformName = LiveParseTools.getLivePlatformName(liveType)
        isLoading = true
        do {
            let diskConfig = DiskConfig(name: "Simple_Live_TV")
            let memoryConfig = MemoryConfig(expiry: .never, countLimit: 50, totalCostLimit: 50)

            let storage: Storage<String, [LiveMainListModel]> = try Storage<String, [LiveMainListModel]>(
              diskConfig: diskConfig,
              memoryConfig: memoryConfig,
              transformer: TransformerFactory.forCodable(ofType: [LiveMainListModel].self) // Storage<String, User>
            )
            var categories: [LiveMainListModel] = []
            var hasKsCache = false
            if liveType == .ks {
                do {
                    categories = try storage.object(forKey: "ks_categories")
                    hasKsCache = true
                }catch {
                    categories = []
                }
            }
            if categories.isEmpty && hasKsCache == false {
                categories = try await ApiManager.fetchCategoryList(liveType: liveType)
            }
            if liveType == .ks && hasKsCache == false {
                try storage.setObject(categories, forKey: "ks_categories")
            }

            self.categories = categories
            self.getRoomList(index: self.selectedSubListIndex)
            self.isLoading = false
        }catch {
            self.isLoading = false
        }
    }
    
    /**
     获取平台房间列表。
     
     - Returns: 房间列表。
    */
    func getRoomList(index: Int) {
        isLoading = true
        if roomListType == .search {
            Task {
                await searchRoomWithText(text: searchText)
            }
            return
        }
        switch roomListType {
            case .live:
                if index == -1 {
                    if let subListCategory = self.categories.first?.subList.first {
                        Task {
                            var finalSubListCategory = subListCategory
                            if liveType == .yy {
                                finalSubListCategory.id = self.categories.first!.biz ?? ""
                                finalSubListCategory.parentId = subListCategory.biz ?? ""
                            }
                            let roomList  = try await ApiManager.fetchRoomList(liveCategory: finalSubListCategory, page: self.roomPage, liveType: liveType)
                            DispatchQueue.main.async {
                                if self.roomPage == 1 {
                                    self.roomList.removeAll()
                                }
                                self.roomList += roomList
                                self.isLoading = false
                            }
                        }
                    }
                }else {
                    let subListCategory = self.selectedMainListCategory?.subList[index]
                    Task {
                        var finalSubListCategory = subListCategory
                        if liveType == .yy {
                            finalSubListCategory?.id = self.categories.first!.biz ?? ""
                            finalSubListCategory?.parentId = subListCategory?.biz ?? ""
                        }
                        let roomList  = try await ApiManager.fetchRoomList(liveCategory: finalSubListCategory!, page: self.roomPage, liveType: liveType)
                        DispatchQueue.main.async {
                            if self.roomPage == 1 {
                                self.roomList.removeAll()
                            }
                            self.roomList += roomList
                            self.isLoading = false
                        }
                    }
                }
            case .favorite:
                Task {
                    await appViewModel.favoriteStateModel.fetchFavoriteRoomList()
                    let resList = appViewModel.favoriteStateModel.roomList
                    if resList.count > 0 {
                        if appViewModel.selection == 0 {
                            showToast(true, title: "通过CloudKit拉取数据成功,正在同步主播状态", hideAfter: 1.5)
                        }
                    }
                    var fetchedModels: [LiveModel] = []
                    // 使用异步的任务组来并行处理所有的请求
                    var bilibiliModels: [LiveModel] = []
                    await withTaskGroup(of: LiveModel?.self, body: { group in
                        for liveModel in resList {
                            if liveModel.liveType == .bilibili {
                                bilibiliModels.append(liveModel)
                            }else {
                                group.addTask {
                                    do {
                                        let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: liveModel)
                                        return dataReq
                                    } catch {
                                        print("房间号\(liveModel.roomId), 主播名字\(liveModel.userName), 平台\(liveModel.liveType), \(error)")
                                        var errorModel = liveModel
                                        errorModel.liveState = LiveState.unknow.rawValue
                                        return errorModel
                                    }
                                }
                            }
                        }
                        // 收集任务组中每个任务的结果
                        for await result in group {
                            if let newLiveModel = result {
                                fetchedModels.append(newLiveModel)
                            }
                        }
                    })
                    
                    if bilibiliModels.count > 0 {
                        if appViewModel.selection == 0 {
                            showToast(true, title: "同步除B站主播状态成功, 开始同步B站主播状态,预计时间\(Double(bilibiliModels.count) * 1.5)秒", hideAfter: 3)
                        }
                    }
                    
                    for item in bilibiliModels { //B站可能存在风控，触发条件为访问过快或没有Cookie？
                        do {
                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 等待1.5秒
                            let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: item)
                            fetchedModels.append(dataReq)
                        }catch {
                            print("房间号\(item.roomId), 主播名字\(item.userName), 平台\(item.liveType), \(error)")
                        }
                    }

                    let sortedModels = fetchedModels.sorted { firstModel, secondModel in
                        if firstModel.liveState == "1", secondModel.liveState != "1" {
                            return true
                        } else if firstModel.liveState != "1", secondModel.liveState == "1" {
                            return false
                        }
                        return true // 如果两个模型的liveState相同，保持它们的当前顺序不变
                    }

                    // 最后，更新tempArray
                    await MainActor.run {
                        self.favoriteRoomList.removeAll()
                        self.roomList.removeAll()
                        self.roomList = sortedModels
                        self.favoriteRoomList = self.roomList
                        self.isLoading = false
                        print("结束")
                    }
                }
            case .history:
                self.roomList = appViewModel.historyModel.watchList
            break
            default:
                break
        }
    }
    /**
     获取平台直播主分类获取子分类。
     
     - Returns: 子分类列表
    */
    func getSubCategoryList() {
        let subList = self.selectedMainListCategory?.subList ?? []
        self.selectedSubCategory = subList
    }
    
    func getLastestHistoryRoomInfo(_ index: Int) {
        isLoading = true
        Task {
            do {
                var newLiveModel = try await ApiManager.fetchLastestLiveInfo(liveModel:roomList[index])
                if newLiveModel.liveState == "" || newLiveModel.liveState == nil {
                    newLiveModel.liveState = "0"
                }
                await updateList(newLiveModel, index: index)
            }catch {
                
            }
        }
    }
    
    @MainActor func updateList(_ newModel: LiveModel, index: Int) { //后续会优化掉这个方法
        self.roomList[index] = newModel
    }
    
    func createCurrentRoomViewModel(enterFromLive: Bool) {
        roomInfoViewModel = RoomInfoViewModel(currentRoom: roomList[selectedRoomListIndex], appViewModel: appViewModel, enterFromLive: enterFromLive, roomType: roomListType)
        roomInfoViewModel?.roomList = roomList
    }
    
    
    func deleteHistory(index: Int) {
        appViewModel.historyModel.watchList.remove(at: index)
        self.roomList.remove(at: index)
    }
    
    @MainActor func searchRoomWithText(text: String) async {
        do {
            isLoading = true
            if roomPage == 1 {
                self.roomList.removeAll()
            }
            let bilibiliResList = try await Bilibili.searchRooms(keyword: text, page: roomPage)
            let douyinResList = try await Douyin.searchRooms(keyword: text, page: roomPage)
            var finalDouyinResList: [LiveModel] = []
            for room in douyinResList {
                let liveState = try await Douyin.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                finalDouyinResList.append(.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount))
            }
            let huyaResList = try await Huya.searchRooms(keyword: text, page: roomPage)
            let douyuResList = try await Douyu.searchRooms(keyword: text, page: roomPage)
            var finalDouyuResList: [LiveModel] = []
            for room in douyuResList {
                let liveState = try await Douyu.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                finalDouyuResList.append(.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount))
            }
            var resArray: [LiveModel] = []
            resArray.append(contentsOf: bilibiliResList)
            resArray.append(contentsOf: finalDouyinResList)
            resArray.append(contentsOf: huyaResList)
            resArray.append(contentsOf: finalDouyuResList)
            for item in resArray {
                if self.roomList.contains(where: { $0 == item }) == false {
                    self.roomList.append(item)
                }
            }
            self.isLoading = false
        }catch {
            
        }
    }
    
    func searchRoomWithShareCode(text: String) {
        isLoading = true
        self.roomList.removeAll()
        if self.searchTypeIndex == 2 {
            Task {
                do {
                    let u2bResRoom = try await YoutubeParse.getRoomInfoFromShareCode(shareCode: text)
                    DispatchQueue.main.async {
                        self.roomList.append(u2bResRoom)
                        self.isLoading = false
                    }
                }catch {
                    
                }
            }
        }else {
            Task {
                if text.contains("b23.tv") || text.contains("bilibili") {
                    let bilibiliResRoom = try await Bilibili.getRoomInfoFromShareCode(shareCode: text)
                    DispatchQueue.main.async {
                        self.roomList.append(bilibiliResRoom)
                        self.isLoading = false
                    }
                }else if text.contains("douyin") {
                    let room = try await Douyin.getRoomInfoFromShareCode(shareCode: text)
                    let liveState = try await Douyin.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    let finalDouyinResRoom = LiveModel.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount)
                    DispatchQueue.main.async {
                        self.roomList.append(finalDouyinResRoom)
                        self.isLoading = false
                    }
                }else if text.contains("huya") {
                    let huyaResRoom = try await Huya.getRoomInfoFromShareCode(shareCode: text)
                    DispatchQueue.main.async {
                        self.roomList.append(huyaResRoom)
                        self.isLoading = false
                    }
                }else if text.contains("douyu") {
                    let room = try await Douyu.getRoomInfoFromShareCode(shareCode: text)
                    let liveState = try await Douyu.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    let finalDouyuResRoom = LiveModel.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount)
                    DispatchQueue.main.async {
                        self.roomList.append(finalDouyuResRoom)
                        self.isLoading = false
                    }
                }else if text.contains("cc.163.com") {
                    let room = try await NeteaseCC.getRoomInfoFromShareCode(shareCode: text)
                    let liveState = try await NeteaseCC.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    let finalCCResRoom = LiveModel.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount)
                    DispatchQueue.main.async {
                        self.roomList.append(finalCCResRoom)
                        self.isLoading = false
                    }
                }else if text.contains("kuaishou.com") {
                    let room = try await KuaiShou.getRoomInfoFromShareCode(shareCode: text)
                    let liveState = try await KuaiShou.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    let finalKSResRoom = LiveModel.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount)
                    DispatchQueue.main.async {
                        self.roomList.append(finalKSResRoom)
                        self.isLoading = false
                    }
                }else if text.contains("yy.com") {
                    let room = try await YY.getRoomInfoFromShareCode(shareCode: text)
                    let liveState = try await YY.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
                    let finalYYResRoom = LiveModel.init(userName: room.userName, roomTitle: room.roomTitle, roomCover: room.roomCover, userHeadImg: room.userHeadImg, liveType: room.liveType, liveState: liveState, userId: room.userId, roomId: room.roomId, liveWatchedCount: room.liveWatchedCount)
                    DispatchQueue.main.async {
                        self.roomList.append(finalYYResRoom)
                        self.isLoading = false
                    }
                }else { //如果是房间号?
                    do {
                        let bilibiliResRoom = try await Bilibili.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(bilibiliResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                    do {
                        let douyinResRoom = try await Douyin.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(douyinResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                    do {
                        let huyaResRoom = try await Huya.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(huyaResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                    do {
                        let douyuResRoom = try await Douyu.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(douyuResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                    do {
                        let ccResRoom = try await NeteaseCC.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(ccResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                    do {
                        let ksResRoom = try await KuaiShou.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(ksResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                    do {
                        let yyResRoom = try await YY.getRoomInfoFromShareCode(shareCode: text)
                        DispatchQueue.main.async {
                            self.roomList.append(yyResRoom)
                            self.isLoading = false
                        }
                    }catch {
                        
                    }
                }
            }
        }
    }
    

    
    //MARK: 操作相关
    
    func showToast(_ success: Bool, title: String, hideAfter: TimeInterval? = 1.5) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
        self.toastOptions = SimpleToastOptions(
            alignment: .topLeading, hideAfter: hideAfter
        )
    }
}
