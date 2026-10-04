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
@MainActor
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
            if roomListType == .favorite || roomListType == .search || !hasMoreRooms {
                return
            }
            getRoomList(index: selectedSubListIndex)
        }
    }
    private var storedRoomList: [LiveModel] = []
    var roomList: [LiveModel] {
        get { roomListType == .search ? searchRequest.rooms : storedRoomList }
        set {
            guard roomListType != .search else { return }
            storedRoomList = newValue
        }
    }
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
    private var roomRequestGeneration = UUID()
    private var catalogRequestGeneration = UUID()
    let searchRequest = SearchRequestModel(
        fetchOutcome: LiveViewModel.fetchSearch,
        onAccepted: LiveViewModel.recordAcceptedSearch
    )

    
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
        let generation = UUID()
        catalogRequestGeneration = generation
        livePlatformName = LiveParseTools.getLivePlatformName(liveType)
        isLoading = true
        var handedLoadingToRoomRequest = false
        defer {
            if catalogRequestGeneration == generation, !handedLoadingToRoomRequest {
                isLoading = false
            }
        }
        do {
            let fetchedCategories = try await LiveService.fetchCategoryList(liveType: liveType)
            guard !Task.isCancelled, catalogRequestGeneration == generation else { return }
            categories = fetchedCategories
            selectedMainListCategory = nil
            selectedSubCategory = []
            selectedSubListIndex = -1
            getRoomList(index: selectedSubListIndex)
            handedLoadingToRoomRequest = roomListType == .live
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                guard !Task.isCancelled, self.catalogRequestGeneration == generation else { return }
                self.endFirstLoading = true
            }
        } catch {
            guard !Task.isCancelled, catalogRequestGeneration == generation else { return }
            handleError(error)
        }
    }

    @discardableResult
    func selectCategory(parentIndex: Int, subIndex: Int) -> Bool {
        guard categories.indices.contains(parentIndex) else { return false }
        let parent = categories[parentIndex]
        guard parent.subList.indices.contains(subIndex) else { return false }

        selectedMainListCategory = parent
        selectedSubCategory = parent.subList
        selectedSubListIndex = subIndex
        selectedRoomListIndex = 0
        hasMoreRooms = true
        roomPage = 1
        return true
    }

    func getRoomList(index: Int) {
        if roomListType == .search {
            return
        }
        if roomPage == 1 {
            selectedRoomListIndex = 0
        }
        isLoading = true

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
        let generation = UUID()
        roomRequestGeneration = generation
        let requestedPage = roomPage
        let requestedCategory: LiveCategoryModel?
        let requestedParentBiz: String?
        if index == -1 {
            requestedCategory = categories.first?.subList.first
            requestedParentBiz = categories.first?.biz
        } else if let selectedMainListCategory,
                  selectedMainListCategory.subList.indices.contains(index) {
            requestedCategory = selectedMainListCategory.subList[index]
            requestedParentBiz = selectedMainListCategory.biz
        } else {
            requestedCategory = nil
            requestedParentBiz = nil
        }

        Task {
            do {
                let newRooms: [LiveModel]
                if let requestedCategory {
                    newRooms = try await LiveService.fetchRoomList(
                        liveType: liveType,
                        category: requestedCategory,
                        parentBiz: requestedParentBiz,
                        page: requestedPage
                    )
                } else {
                    newRooms = []
                }

                await MainActor.run {
                    guard self.roomRequestGeneration == generation else { return }
                    if requestedPage == 1 {
                        self.hasMoreRooms = true
                    }
                    if newRooms.isEmpty {
                        self.hasMoreRooms = false
                    }
                    let mergedRooms: [LiveModel]
                    if requestedPage == 1 {
                        mergedRooms = newRooms.removingDuplicates()
                    } else {
                        mergedRooms = self.roomList.appendingUnique(contentsOf: newRooms)
                    }
                    self.roomList = mergedRooms
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard self.roomRequestGeneration == generation else { return }
                    self.isLoading = false
                    // 插件抛 "返回结果为空" 不算错误:分页到底 / 当前分类无房间。
                    // 不弹错误页,只置 hasMoreRooms=false,首页同时清空列表让空态接管。
                    if let liveParseError = error as? LiveParseError,
                       liveParseError.detail.contains("返回结果为空") {
                        self.hasMoreRooms = false
                        if requestedPage == 1 {
                            self.roomList = []
                        }
                        return
                    }
                    self.handleError(error)
                }
            }
        }
    }

    func submitSearch(input: String, kind: RoomSearchKind) {
        searchRequest.submit(input: input, kind: kind)
    }

    private static func fetchSearch(_ request: RoomSearchRequest) async throws -> RoomSearchOutcome {
        let operationID = SupportDiagnosticsService.shared.recordAction(
            .searched,
            context: request.kind == .keyword
                ? SupportDiagnosticActionContext.search(keyword: request.input, page: request.page, additional: ["searchKind": "keyword"])
                : SupportDiagnosticActionContext.shareSearch(page: request.page)
        )
        do {
            return try await SupportDiagnosticContext.$operationID.withValue(operationID) {
                switch request.kind {
                case .keyword:
                    return try await LiveService.searchRoomsWithOutcome(keyword: request.input, page: request.page)
                case .share:
                    return try await LiveService.searchRoomWithShareCodeWithOutcome(shareCode: request.input)
                }
            }
        } catch let error as LiveParseError where error.detail.contains("返回结果为空") {
            return RoomSearchOutcome(rooms: [])
        }
    }

    private static func recordAcceptedSearch(_ request: RoomSearchRequest, _ rooms: [LiveModel]) {
        guard request.kind == .share, let room = rooms.first else { return }
        SupportDiagnosticsService.shared.recordAction(
            .searched,
            context: SupportDiagnosticActionContext.room(
                room,
                additional: ["searchKind": "share", "entryPoint": "searchResult"]
            )
        )
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
