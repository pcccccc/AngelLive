//
//  LiveViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies

enum LiveRoomListType {
    case live
    case favorite
    case history
    case search
}


@Observable
class LiveViewModel {

    // MARK: - Sidebar 相关常量和状态
    let sidebarWidth: CGFloat = 320
    let sidebarPeekWidth: CGFloat = 50  // 收起时露出的宽度
    var isSidebarExpanded: Bool = false

    // 旧属性保持兼容（逐步移除）
    var showOverlay: Bool {
        get { isSidebarExpanded }
        set { isSidebarExpanded = newValue }
    }
    var menuTitleIcon: UIImage?

    //房间列表分类
    var roomListType: LiveRoomListType
    //直播分类
    var liveType: LiveType
    //分类名
    var livePlatformName: String = ""

    //菜单列表
    var categories: [LiveMainListModel] = []
    
    //当前选中的主分类与子分类
    var selectedMainListCategory: LiveMainListModel?
    var selectedSubCategory: [LiveCategoryModel] = []
    var selectedSubListIndex: Int = -1
    var selectedRoomListIndex: Int = -1
    
    //加载状态
    var isLoading = false
    var hasError = false
    var errorMessage = ""
    var errorDetail: String? = nil
    var showErrorDetail = false
    var currentError: Error? = nil
   
    //直播列表分页
    var subPageNumber = 0
    var subPageSize = 20
    var hasMoreRooms = true
    var roomPage: Int = 1 {
        didSet {
            if roomListType == .favorite || !hasMoreRooms {
                return
            }
            getRoomList(index: selectedSubListIndex)
        }
    }
    var roomList: [LiveModel] = []
    var favoriteRoomList: [LiveModel] = []
    var currentRoom: LiveModel? {
         didSet {
             currentRoomIsFavorited = appViewModel.favoriteViewModel.roomList.contains { $0.roomId == currentRoom?.roomId }
         }
     }
    
    //当前选择房间ViewModel
    var roomInfoViewModel: RoomInfoViewModel?

    var isLeftFocused: Bool = false
    
    var loadingText: String = "正在获取内容"
    var searchTypeArray = ["链接/口令 🔗", "关键词 🔍（不推荐）"]
    var searchTypeIndex = 0
    var searchText: String = ""
    var showAlert: Bool = false
    var currentRoomIsFavorited: Bool = false
    
    var appViewModel: AppState
    
    //Toast
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    var endFirstLoading = false
    var lodingTimer: Timer?

    
    init(roomListType: LiveRoomListType, liveType: LiveType, appViewModel: AppState, shouldLoadData: Bool = true) {
        self.liveType = liveType
        self.roomListType = roomListType
        self.appViewModel = appViewModel
        menuTitleIcon = TVPlatformIconProvider.tabImage(for: liveType)
        guard shouldLoadData else { return }
        switch roomListType {
            case .live:
                Task {
                    await getCategoryList()
                }
            case .favorite: break
//                getRoomList(index: 0)
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
    
    func getCategoryList() async {
        await MainActor.run {
            livePlatformName = LiveParseTools.getLivePlatformName(liveType)
            isLoading = true
        }
        do {
            let fetchedCategories = try await LiveService.fetchCategoryList(liveType: liveType)
            await MainActor.run {
                self.categories = fetchedCategories
                self.getRoomList(index: self.selectedSubListIndex)
                self.isLoading = false
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                await MainActor.run {
                    self.endFirstLoading = true
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.handleError(error)
            }
        }
    }

    func getRoomList(index: Int) {
        if index == -1 || index == 1 {
            selectedRoomListIndex = 0
        }
        isLoading = true
        if roomListType == .search {
            Task {
                await searchRoomWithText(text: searchText)
            }
            return
        }
        
        switch roomListType {
        case .live:
            fetchLiveRooms(index: index)
        case .favorite:
            // Favorite logic remains here for now as it's complex and involves CloudKit.
            // It's a good candidate for its own ViewModel/Service later.
            break
        case .history:
            self.roomList = appViewModel.historyViewModel.watchList
            self.isLoading = false // Make sure to turn off loading indicator
        default:
            self.isLoading = false // Make sure to turn off loading indicator
            break
        }
    }
    
    private func fetchLiveRooms(index: Int) {
        Task {
            do {
                let newRooms: [LiveModel]
                if index == -1 {
                    if let subListCategory = self.categories.first?.subList.first {
                        let parentBiz = self.categories.first?.biz
                        newRooms = try await LiveService.fetchRoomList(liveType: liveType, category: subListCategory, parentBiz: parentBiz, page: self.roomPage)
                    } else {
                        newRooms = []
                    }
                } else {
                    if let subListCategory = self.selectedMainListCategory?.subList[index] {
                        let parentBiz = self.selectedMainListCategory?.biz
                        newRooms = try await LiveService.fetchRoomList(liveType: liveType, category: subListCategory, parentBiz: parentBiz, page: self.roomPage)
                    } else {
                        newRooms = []
                    }
                }

                await MainActor.run {
                    if self.roomPage == 1 {
                        self.hasMoreRooms = true
                    }
                    if newRooms.isEmpty {
                        self.hasMoreRooms = false
                    }
                    let mergedRooms: [LiveModel]
                    if self.roomPage == 1 {
                        mergedRooms = newRooms.removingDuplicates()
                    } else {
                        mergedRooms = self.roomList.appendingUnique(contentsOf: newRooms)
                    }
                    self.roomList = mergedRooms
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    // 插件抛 "返回结果为空" 不算错误:分页到底 / 当前分类无房间。
                    // 不弹错误页,只置 hasMoreRooms=false,首页同时清空列表让空态接管。
                    if let liveParseError = error as? LiveParseError,
                       liveParseError.detail.contains("返回结果为空") {
                        self.hasMoreRooms = false
                        if self.roomPage == 1 {
                            self.roomList = []
                        }
                        return
                    }
                    self.handleError(error)
                }
            }
        }
    }

    func searchRoomWithText(text: String) async {
        await MainActor.run {
            isLoading = true
        }
        do {
            let newRooms = try await LiveService.searchRooms(keyword: text, page: roomPage)
            await MainActor.run {
                if roomPage == 1 {
                    self.roomList = newRooms.removingDuplicates()
                } else {
                    self.roomList = self.roomList.appendingUnique(contentsOf: newRooms)
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                // 检查是否是空结果错误（搜索时空结果是正常情况，不应显示错误）
                if let liveParseError = error as? LiveParseError,
                   liveParseError.detail.contains("返回结果为空") {
                    // 空结果不是错误，只是没有搜索到内容，不设置 hasError
                    self.roomList = []
                } else {
                    // 真正的错误才调用 handleError
                    handleError(error)
                }
            }
        }
    }

    func searchRoomWithShareCode(text: String) async {
        await MainActor.run {
            isLoading = true
            roomList.removeAll()
        }
        do {
            if let room = try await LiveService.searchRoomWithShareCode(shareCode: text) {
                await MainActor.run {
                    roomList.append(room)
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                // 检查是否是空结果错误（搜索时空结果是正常情况，不应显示错误）
                if let liveParseError = error as? LiveParseError,
                   liveParseError.detail.contains("返回结果为空") {
                    // 空结果不是错误，只是没有搜索到内容，不设置 hasError
                    self.roomList = []
                } else {
                    // 真正的错误才调用 handleError
                    handleError(error)
                }
            }
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
                let fetchedLiveModel = try await ApiManager.fetchLastestLiveInfo(liveModel:roomList[index])
                // 确保在主线程更新UI
                await MainActor.run {
                    var newLiveModel = fetchedLiveModel
                    if newLiveModel.liveState == "" || newLiveModel.liveState == nil {
                        newLiveModel.liveState = "0"
                    }
                    updateList(newLiveModel, index: index)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    handleError(error)
                }
            }
        }
    }

    @MainActor func updateList(_ newModel: LiveModel, index: Int) {
        if index < self.roomList.count {
            self.roomList[index] = newModel
        }
    }
    
    @MainActor func createCurrentRoomViewModel(enterFromLive: Bool) {
        guard let currentRoom = self.currentRoom else { return }
        roomInfoViewModel = RoomInfoViewModel(currentRoom: currentRoom, appViewModel: appViewModel, enterFromLive: enterFromLive, roomType: roomListType)
        roomInfoViewModel?.roomList = roomList
    }
    
    func deleteHistory(index: Int) {
        appViewModel.historyViewModel.watchList.remove(at: index)
        self.roomList.remove(at: index)
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

    // MARK: - 错误处理

    /// 处理错误并提取详细信息
    func handleError(_ error: Error) {
        self.hasError = true
        self.currentError = error

        if let liveParseError = error as? LiveParseError {
            // 使用用户友好的简短消息
            self.errorMessage = liveParseError.title
            // 存储详细信息供查看
            self.errorDetail = liveParseError.detail
        } else {
            self.errorMessage = error.localizedDescription
            self.errorDetail = nil
        }
    }
}
