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
    @Published var selectedSubCategory: LiveCategoryModel?
    
    //加载状态
    @Published var isLoading = false
    var liveType: LiveType
    @Published var showOverlay: Bool = false {
        didSet {
            leftListOverlay = showOverlay == true ? 0 : 0
        }
    }
    @Published var leftListOverlay: CGFloat = 0
    @Published var menuTitleIcon: String = ""
    
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
                    self.isLoading = false
                }
            }catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
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
