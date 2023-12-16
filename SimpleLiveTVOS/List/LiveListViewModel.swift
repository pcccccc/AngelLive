//
//  LiveListViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/12/14.
//

import Foundation
import LiveParse


class LiveListViewModel: ObservableObject {
    //菜单列表
    @Published var categories: [LiveMainListModel] = []
    
    //当前选中的主分类与子分类
    @Published var selectedMainListCategory: LiveMainListModel?
    @Published var selectedSubCategory: [LiveCategoryModel] = []
    
    //加载状态
    @Published var isLoading = false
    var liveType: LiveType
    @Published var showOverlay: Bool = false {
        didSet {
            leftListOverlay = showOverlay == true ? 0 : -350
        }
    }
    @Published var leftListOverlay: CGFloat = -350
    @Published var menuTitleIcon: String = ""
    
    @Published var subPageNumber = 0
    @Published var subPageSize = 20
    
    @Published var roomPage: Int = 1
    @Published var roomList: [LiveModel] = []

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
                
                print(categories)
                DispatchQueue.main.async {
                    self.categories = categories
                    self.getRoomList(index: -1)
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
        Task {
            do {
                if index == -1 {
                    if let subListCategory = self.categories.first?.subList.first {
                        let roomList  = try await fetchRoomList(liveCategory: subListCategory)
                        print(categories)
                        DispatchQueue.main.async {
                            self.roomList = roomList
                            self.isLoading = false
                        }
                    }
                }else {
                    let subListCategory = self.selectedSubCategory[index]
                    let roomList  = try await fetchRoomList(liveCategory: subListCategory)
                    print(categories)
                    DispatchQueue.main.async {
                        self.roomList = roomList
                        self.isLoading = false
                    }
                }
                
            }catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
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
