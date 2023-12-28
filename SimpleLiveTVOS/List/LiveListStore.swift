//
//  LiveStore.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import LiveParse
import KSPlayer



class LiveStore: ObservableObject {
    
    let leftMenuMinWidth: CGFloat = 180
    let leftMenuMaxWidth: CGFloat = 300
    let leftMenuMinHeight: CGFloat = 50
    let leftMenuMaxHeight: CGFloat = 830
    //菜单列表
    @Published var categories: [LiveMainListModel] = []
    
    //当前选中的主分类与子分类
    @Published var selectedMainListCategory: LiveMainListModel?
    @Published var selectedSubCategory: [LiveCategoryModel] = []
    @Published var selectedSubListIndex: Int = -1
    
    //加载状态
    @Published var isLoading = false
    var liveType: LiveType
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
    
    @Published var subPageNumber = 0
    @Published var subPageSize = 20
    
    @Published var roomPage: Int = 1 {
        didSet {
            getRoomList(index: selectedSubListIndex)
        }
    }
    @Published var roomList: [LiveModel] = []
    
    @Published var currentRoom: LiveModel?
    @Published var currentRoomPlayArgs: [LiveQualityModel]?
    @Published var currentPlayURL: URL?
    @Published var isLeftFocused: Bool = false
    @Published var playerCoordinator = KSVideoPlayer.Coordinator()
    
    init(liveType: LiveType) {
        self.liveType = liveType
        switch liveType {
            case .bilibili: menuTitleIcon = "bilibili_2"
            case .douyu: menuTitleIcon = "douyu"
            case .huya: menuTitleIcon = "huya"
            case .douyin: menuTitleIcon = "douyin"
            default: menuTitleIcon = "douyin"
        }
        getCategoryList()
    }
    
    func getCategoryList() {
        isLoading = true
        Task {
            do {
                let categories  = try await fetchCategoryList()
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
    
    func getRoomList(index: Int) {
        isLoading = true
        
        do {
            if index == -1 {
                if let subListCategory = self.categories.first?.subList.first {
                    Task {
                        let roomList  = try await fetchRoomList(liveCategory: subListCategory)
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
                    let roomList  = try await fetchRoomList(liveCategory: subListCategory!)
                    DispatchQueue.main.async {
                        if self.roomPage == 1 {
                            self.roomList.removeAll()
                        }
                        self.roomList += roomList
                        self.isLoading = false
                    }
                }
            }
            
        }catch {
            self.isLoading = false
        }
        
    }
    
    func showSubCategoryList(currentCategory: LiveMainListModel) {
        if self.selectedMainListCategory?.title != currentCategory.title || self.selectedSubCategory.count == 0 {
            self.selectedMainListCategory = currentCategory
            self.selectedSubCategory = []
            self.getSubCategoryList()
        }else {
            self.selectedSubCategory = []
        }
    }
    
    func getSubCategoryList() {
        if self.selectedSubCategory.count == 0 {
            let subList = self.selectedMainListCategory?.subList ?? []
            self.selectedSubCategory = subList
        }else {
            self.selectedSubCategory = []
        }
    }
    
    func getPlayArgs() async throws {
        do {
            var playArgs: [LiveQualityModel] = []
            switch liveType {
                case .bilibili:
                    playArgs = try await Bilibili.getPlayArgs(roomId: currentRoom?.roomId ?? "", userId: nil)
                case .huya:
                    playArgs =  try await Huya.getPlayArgs(roomId: currentRoom?.roomId ?? "", userId: nil)
                case .douyin:
                    playArgs =  try await Douyin.getPlayArgs(roomId: currentRoom?.roomId ?? "", userId: currentRoom?.userId ?? "")
                case .douyu:
                    playArgs =  try await Douyu.getPlayArgs(roomId: currentRoom?.roomId ?? "", userId: nil)
                default: break
            }
            DispatchQueue.main.async {
                self.currentRoomPlayArgs = playArgs
                self.changePlayUrl(cdnIndex: 0, urlIndex: 0)
            }
        }catch {
            
        }
    }
    
    func getCurrentRoomLiveState() async throws -> LiveState {
        switch liveType {
        case .bilibili:
            return try await Bilibili.getLiveState(roomId: currentRoom?.roomId ?? "", userId: nil)
        case .huya:
            return try await Huya.getLiveState(roomId: currentRoom?.roomId ?? "", userId: nil)
        case .douyin:
            return try await Douyin.getLiveState(roomId: currentRoom?.roomId ?? "", userId: currentRoom?.userId ?? "")
        case .douyu:
            return try await Douyu.getLiveState(roomId: currentRoom?.roomId ?? "", userId: nil)
        default:
            return .unknow
        }
    }
    
    func changePlayUrl(cdnIndex: Int, urlIndex: Int) {
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = true
        guard currentRoomPlayArgs != nil else {
            return
        }
        let currentCdn = currentRoomPlayArgs![cdnIndex]
        var currentQuality = currentCdn.qualitys[urlIndex]
        if currentQuality.liveCodeType == .flv {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSAVPlayer.self
        }else {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
        }
        if liveType == .bilibili {
            for item in currentRoomPlayArgs! {
                for liveQuality in item.qualitys {
                    if liveQuality.liveCodeType == .hls {
                        KSOptions.firstPlayerType = KSAVPlayer.self
                        KSOptions.secondPlayerType = KSMEPlayer.self
                        
                        self.currentPlayURL = URL(string: liveQuality.url)!
                        return
                    }
                }
            }
        }
        if liveType == .huya {
            if currentQuality.title.contains("HDR") {
                if urlIndex + 1 < currentCdn.qualitys.count {
                    currentQuality = currentCdn.qualitys[urlIndex + 1]
                }
            }
        }
        
        
        self.currentPlayURL = URL(string: currentQuality.url)!
    }
    
    func fetchRoomList(liveCategory: LiveCategoryModel) async throws -> [LiveModel] {
        switch liveType {
        case .bilibili:
            return try await Bilibili.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: self.roomPage)
        case .huya:
            return try await Huya.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: self.roomPage)
        case .douyin:
            return try await Douyin.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: self.roomPage)
        case .douyu:
            return try await Douyu.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: self.roomPage)
        default:
            return []
        }
    }
    
    func fetchCategoryList() async throws -> [LiveMainListModel] {
        switch liveType {
        case .bilibili:
            return try await Bilibili.getCategoryList()
        case .huya:
            return try await Huya.getCategoryList()
        case .douyin:
            return try await Douyin.getCategoryList()
        case .douyu:
            return try await Douyu.getCategoryList()
        default:
            return []
        }
    }
    
    
}
