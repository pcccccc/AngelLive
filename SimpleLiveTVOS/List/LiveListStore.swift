//
//  LiveStore.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import LiveParse
import KSPlayer
import SimpleToast


class LiveStore: ObservableObject {
    
    let leftMenuMinWidth: CGFloat = 180
    let leftMenuMaxWidth: CGFloat = 300
    let leftMenuMinHeight: CGFloat = 50
    let leftMenuMaxHeight: CGFloat = 830
    
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
    
    //加载状态
    @Published var isLoading = false
    
    //直播分类
    var liveType: LiveType
   
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
    @Published var currentRoomPlayArgs: [LiveQualityModel]?
    @Published var currentPlayURL: URL?
    @Published var isLeftFocused: Bool = false
    @Published var playerCoordinator = KSVideoPlayer.Coordinator()
    
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
    
    @Published var loadingText: String = "正在获取内容"
    
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
    
    //MARK: 操作相关
    
    func showToast(_ success: Bool, title: String) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
    }
    
    /**
     切换清晰度
    */
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
    
    /**
     获取平台直播分类。
     
     - 展示左侧列表子列表
    */
    func showSubCategoryList(currentCategory: LiveMainListModel) {
        if self.selectedMainListCategory?.title != currentCategory.title || self.selectedSubCategory.count == 0 {
            self.selectedMainListCategory = currentCategory
            self.selectedSubCategory = []
            self.getSubCategoryList()
        }else {
            self.selectedSubCategory = []
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
    }
    /**
     获取平台直播主分类获取子分类。
     
     - Returns: 子分类列表
    */
    func getSubCategoryList() {
        if self.selectedSubCategory.count == 0 {
            let subList = self.selectedMainListCategory?.subList ?? []
            self.selectedSubCategory = subList
        }else {
            self.selectedSubCategory = []
        }
    }
    
    /**
     获取播放参数。
     
     - Returns: 播放清晰度、url等参数
    */
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
    
    
}
