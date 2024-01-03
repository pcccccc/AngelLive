//
//  LiveStore.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import LiveParse
import SimpleToast
import SwiftUI

enum LiveRoomListType {
    case live
    case favorite
    case history
}


class LiveStore: ObservableObject {
    
    let leftMenuMinWidth: CGFloat = 180
    let leftMenuMaxWidth: CGFloat = 300
    let leftMenuMinHeight: CGFloat = 50
    let leftMenuMaxHeight: CGFloat = 830
    
    //房间列表分类
    var roomListType: LiveRoomListType
    //直播分类
    var liveType: LiveType
    
    //菜单列表
    @Published var categories: [LiveMainListModel] = []
    @Published var showOverlay: Bool = false {
        didSet {
            leftWidth = showOverlay == true ? leftMenuMaxWidth : leftMenuMinWidth
            leftHeight = showOverlay == true ? leftMenuMaxHeight : leftMenuMinHeight
            leftMenuCornerRadius = showOverlay == true ? 10 : 25
        }
    }
    @Published var leftListOverlay: CGFloat = 0
    @Published var leftWidth: CGFloat = 180
    @Published var leftHeight: CGFloat = 50
    @Published var leftMenuCornerRadius: CGFloat = 25
    @Published var menuTitleIcon: String = ""
    
    //当前选中的主分类与子分类
    @Published var selectedMainListCategory: LiveMainListModel?
    @Published var selectedSubCategory: [LiveCategoryModel] = []
    @Published var selectedSubListIndex: Int = -1
    @Published var selectedRoomListIndex: Int = -1
    
    //加载状态
    @Published var isLoading = false
   
    //直播列表分页
    @Published var subPageNumber = 0
    @Published var subPageSize = 20
    @Published var roomPage: Int = 1 {
        didSet {
            getRoomList(index: selectedSubListIndex)
        }
    }
    @Published var roomList: [LiveModel] = []
    @Published var currentRoom: LiveModel?
    
    //当前选择房间ViewModel
    @Published var roomInfoViewModel: RoomInfoStore?

    @Published var isLeftFocused: Bool = false
    @Published var showToast: Bool = false
    @Published var toastTitle: String = ""
    @Published var toastTypeIsSuccess: Bool = false
    @Published var toastImage: String = "checkmark.circle" {
        didSet {
            toastImage = toastTypeIsSuccess == true ? "checkmark.circle" : "xmark.circle"
        }
    }
    @Published var toastOptions = SimpleToastOptions(
        hideAfter: 1.5
    )
    
    @AppStorage("SimpleLive.Favorite.Category.Bilibili") public var bilibiliFavoriteLiveCategoryList: Array<LiveMainListModel> = []
    @AppStorage("SimpleLive.Favorite.Category.Huya") public var huyaFavoriteLiveCategoryList: Array<LiveMainListModel> = []
    @AppStorage("SimpleLive.Favorite.Category.Douyu") public var douyuFavoriteLiveCategoryList: Array<LiveMainListModel> = []
    @AppStorage("SimpleLive.Favorite.Category.Douyin") public var douyinFavoriteLiveCategoryList: Array<LiveMainListModel> = []
    @Published public var currentLiveTypeFavoriteCategoryList: Array<LiveMainListModel> = [] {
        didSet {
            switch liveType {
                case .bilibili:
                    bilibiliFavoriteLiveCategoryList = currentLiveTypeFavoriteCategoryList
                case .douyu:
                    douyuFavoriteLiveCategoryList = currentLiveTypeFavoriteCategoryList
                case .huya:
                    huyaFavoriteLiveCategoryList = currentLiveTypeFavoriteCategoryList
                case .douyin:
                    douyinFavoriteLiveCategoryList = currentLiveTypeFavoriteCategoryList
                default:
                    break
            }
        }
    }
    
    
    @Published var loadingText: String = "正在获取内容"
    
    init(roomListType: LiveRoomListType, liveType: LiveType) {
        self.liveType = liveType
        self.roomListType = roomListType
        switch liveType {
            case .bilibili: 
                menuTitleIcon = "bilibili_2"
                currentLiveTypeFavoriteCategoryList = bilibiliFavoriteLiveCategoryList
            case .douyu:
                menuTitleIcon = "douyu"
                currentLiveTypeFavoriteCategoryList = douyuFavoriteLiveCategoryList
            case .huya:
                menuTitleIcon = "huya"
                currentLiveTypeFavoriteCategoryList = huyaFavoriteLiveCategoryList
            case .douyin:
                menuTitleIcon = "douyin"
                currentLiveTypeFavoriteCategoryList = douyinFavoriteLiveCategoryList
            default: menuTitleIcon = "douyin"
        }
        switch roomListType {
            case .live:
                getCategoryList()
            case .favorite, .history:
                getRoomList(index: 0)
                
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
                    DispatchQueue.main.async {
                        if self.roomPage == 1 {
                            self.roomList.removeAll()
                        }
                        for item in resList {
                            if self.roomList.contains(item) == false {
                                self.roomList.append(item)
                           }
                        }
                        self.isLoading = false
                    }
                }
            case .history:
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
    
    func getLastestRoomInfo(_ index: Int) {
        isLoading = true
        if self.roomList.count < index {
            return
        }
        Task {
            let newLiveModel = try await ApiManager.fetchLastestLiveInfo(liveModel:roomList[index])
            DispatchQueue.main.async {
                self.roomList[index] = newLiveModel
                self.isLoading = false
                let endLoading = self.roomList.contains{ $0.liveState != nil && $0.liveState != "" }
                if endLoading {
                    self.roomList = self.roomList.sorted(by: {
                        if $0.liveState ?? "3" == "1" && $1.liveState ?? "3" != "1" {
                            return true
                        }else {
                            return false
                        }
                    })
                    var hasIndex: [Int] = []
                    for index in 0 ..< self.roomList.count { // 排序后再做一次去重
                        let item = self.roomList[index]
                        var flag = 0
                        for sub in self.roomList {
                            if item == sub {
                                flag += 1
                            }
                        }
                        if (item.liveState == nil || item.liveState == "") && flag == 2 {
                            hasIndex.append(index)
                        }
                    }
                    for index in hasIndex {
                        self.roomList.remove(at: index)
                    }
                }
            }
        }
    }
    
    func createCurrentRoomViewModel() {
        roomInfoViewModel = RoomInfoStore(currentRoom: roomList[selectedRoomListIndex])
    }
    
    func addFavoriteCategory(_ category: LiveMainListModel) {
        currentLiveTypeFavoriteCategoryList.append(category)
    }
}
