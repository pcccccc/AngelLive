//
//  LiveViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import LiveParse
import SimpleToast
import SwiftUI
import Observation

enum LiveRoomListType {
    case live
    case favorite
    case history
    case search
}


@Observable
final class LiveViewModel {
    
    let leftMenuMinWidth: CGFloat = 180
    let leftMenuMaxWidth: CGFloat = 300
    let leftMenuMinHeight: CGFloat = 50
    let leftMenuMaxHeight: CGFloat = 830
    
    //房间列表分类
    var roomListType: LiveRoomListType
    //直播分类
    var liveType: LiveType
    
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
    var leftHeight: CGFloat = 50
    var leftMenuCornerRadius: CGFloat = 25
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
            getRoomList(index: selectedSubListIndex)
        }
    }
    var roomList: [LiveModel] = []
    var favoriteRoomList: [LiveModel] = []
    var currentRoom: LiveModel? {
        didSet {
            if favoriteModel != nil {
                currentRoomIsFavorited = favoriteModel!.roomList.contains{ $0.roomId == currentRoom!.roomId }
                print(currentRoomIsFavorited)
            }
        }
    }
    
    //当前选择房间ViewModel
    var roomInfoViewModel: RoomInfoStore?

    var isLeftFocused: Bool = false
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        hideAfter: 1.5
    )
    
    public var watchList: Array<LiveModel> {
        get {
            access(keyPath: \.watchList)
            let dictionaries = UserDefaults.standard.value(forKey: "SimpleLive.History.WatchList") as? Array<Dictionary<String, String?>>
            if dictionaries == nil {
                return []
            }else {
                let jsonEncoder = JSONEncoder()
                if let jsonData = try? jsonEncoder.encode(dictionaries) {
                    let jsonDecoder = JSONDecoder()
                    if let decodedArray = try? jsonDecoder.decode([LiveModel].self, from: jsonData) {
                        return decodedArray
                    }
                }
                return []
            }
        }
        set {
            withMutation(keyPath: \.watchList) {
                let jsonEncoder = JSONEncoder()
                if let jsonData = try? jsonEncoder.encode(newValue) {
                    if let dictionary = try? JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as? [String: Any] {
                        UserDefaults.standard.setValue(dictionary, forKey: "SimpleLive.History.WatchList")
                    }
                }
            }
        }
    }
    
    var favoriteModel: FavoriteModel?
    
    var loadingText: String = "正在获取内容"
    var searchTypeArray = ["关键词", "链接/分享口令/房间号(抖音码选这个)"]
    var searchTypeIndex = 0
    var searchText: String = ""
    var showAlert: Bool = false
    var currentRoomIsFavorited: Bool = false
    
    
    init(roomListType: LiveRoomListType, liveType: LiveType) {
        self.liveType = liveType
        self.roomListType = roomListType
        switch liveType {
            case .bilibili: 
                menuTitleIcon = "bilibili_2"
            case .douyu:
                menuTitleIcon = "douyu"
            case .huya:
                menuTitleIcon = "huya"
            case .douyin:
                menuTitleIcon = "douyin"
            default: menuTitleIcon = "douyin"
        }
        switch roomListType {
            case .live:
                getCategoryList()
            case .favorite, .history:
                getRoomList(index: 0)
            default:
                break
                
        }
    }
    
    //MARK: 操作相关
    
    func showToast(_ success: Bool, title: String) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
    }

    /**
     获取平台直播分类。
     
     - 展示左侧列表子列表
    */
    func showSubCategoryList(currentCategory: LiveMainListModel) {
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
    func getCategoryList() {
        isLoading = true
        Task {
            do {
                let categories  = try await ApiManager.fetchCategoryList(liveType: liveType)
                DispatchQueue.main.async {
                    self.categories = categories
                    self.getRoomList(index: self.selectedSubListIndex)
                    self.isLoading = false
                    
                }
            }catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
        
    }
    
    /**
     获取平台房间列表。
     
     - Returns: 房间列表。
    */
    func getRoomList(index: Int) {
        isLoading = true
        if roomListType == .search {
            searchRoomWithText(text: searchText)
            return
        }
        switch roomListType {
            case .live:
                if index == -1 {
                    if let subListCategory = self.categories.first?.subList.first {
                        Task {
                            let roomList  = try await ApiManager.fetchRoomList(liveCategory: subListCategory, page: self.roomPage, liveType: liveType)
                            DispatchQueue.main.async {
                                if self.roomPage == 1 {
                                    self.roomList.removeAll()
                                }
                                self.roomList += roomList
                                self.isLoading = false
        //                            self.selectedSubListIndex = 0
                            }
                        }
                    }
                }else {
                    let subListCategory = self.selectedMainListCategory?.subList[index]
                    Task {
                        let roomList  = try await ApiManager.fetchRoomList(liveCategory: subListCategory!, page: self.roomPage, liveType: liveType)
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
                    let resList = try await CloudSQLManager.searchRecord()
                    var fetchedModels: [LiveModel] = []
                    // 使用异步的任务组来并行处理所有的请求
                    var bilibiliModels: [LiveModel] = []
                    await withTaskGroup(of: LiveModel?.self, body: { group in
                        for liveModel in resList {
//                            print("房间号\(liveModel.roomId), 主播名字\(liveModel.userName), 平台\(liveModel.liveType)")
                            if liveModel.liveType == .bilibili {
                                bilibiliModels.append(liveModel)
                            }else {
                                group.addTask {
                                    do {
                                        let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: liveModel)
                                        return dataReq
                                    } catch {
                                        print(Date())
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
                    
                    for item in bilibiliModels { //B站可能存在风控，触发条件为访问过快或没有Cookie？
                        do {
                            try? await Task.sleep(nanoseconds: 500_000_000) // 等待2秒
                            let dataReq = try await ApiManager.fetchLastestLiveInfo(liveModel: item)
                            fetchedModels.append(dataReq)
                        }catch {
                            print(error)
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
                    }
                }
            case .history:
                self.roomList = self.watchList
                for index in 0 ..< self.roomList.count {
                    self.getLastestHistoryRoomInfo(index)
                }
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
    
    func createCurrentRoomViewModel() {
        roomInfoViewModel = RoomInfoStore(currentRoom: roomList[selectedRoomListIndex], danmuSettingModel: DanmuSettingModel())
    }
    
    
    func deleteHistory(index: Int) {
        self.watchList.remove(at: index)
        self.roomList.remove(at: index)
    }
    
    func searchRoomWithText(text: String) {
        isLoading = true
        if roomPage == 1 {
            self.roomList.removeAll()
        }
        Task {
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
            DispatchQueue.main.async {
                for item in resArray {
                    if self.roomList.contains(where: { $0 == item }) == false {
                        self.roomList.append(item)
                    }
                }
                self.isLoading = false
            }
            
        }
    }
    
    func searchRoomWithShareCode(text: String) {
        isLoading = true
        self.roomList.removeAll()
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
                
            }
        }
    }
}
