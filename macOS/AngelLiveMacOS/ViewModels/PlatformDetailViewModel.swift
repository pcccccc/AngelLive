//
//  PlatformDetailViewModel.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import Foundation
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import Alamofire

@MainActor
@Observable
class PlatformDetailViewModel {
    // 平台信息
    var platform: Platformdescription

    // 分类数据
    var categories: [LiveMainListModel] = []
    var selectedMainCategoryIndex: Int = 0
    var selectedSubCategoryIndex: Int = 0

    // 当前选中的分类
    var currentMainCategory: LiveMainListModel? {
        categories.indices.contains(selectedMainCategoryIndex) ? categories[selectedMainCategoryIndex] : nil
    }

    var currentSubCategories: [LiveCategoryModel] {
        currentMainCategory?.subList ?? []
    }

    var currentSubCategory: LiveCategoryModel? {
        let subList = currentSubCategories
        return subList.indices.contains(selectedSubCategoryIndex) ? subList[selectedSubCategoryIndex] : nil
    }

    var currentCategoryTitle: String {
        guard let main = currentMainCategory else { return "全部分类" }
        guard let sub = currentSubCategory else { return main.title }
        return "\(main.title) · \(sub.title)"
    }

    private var roomModels: [String: CategoryRoomListModel] = [:]
    @ObservationIgnored private var catalogRequestID = UUID()

    var roomList: [LiveModel] { roomModels[cacheKey]?.rooms ?? [] }

    private var cacheKey: String {
        "\(selectedMainCategoryIndex)-\(selectedSubCategoryIndex)"
    }

    // 加载状态
    var isLoadingCategories = false
    var isLoadingRooms: Bool { roomModels[cacheKey]?.isLoading ?? false }

    // 错误状态
    var categoryError: Error?
    var roomError: Error? { roomModels[cacheKey]?.error }

    // 分页
    var hasMoreRooms: Bool { roomModels[cacheKey]?.hasMore ?? true }

    init(platform: Platformdescription) {
        self.platform = platform
    }

    // MARK: - 获取分类列表

    @MainActor
    func loadCategories() async {
        let requestID = UUID()
        catalogRequestID = requestID
        isLoadingCategories = true
        categoryError = nil
        defer { if catalogRequestID == requestID { isLoadingCategories = false } }

        do {
            let fetchedCategories = try await LiveService.fetchCategoryList(liveType: platform.liveType)
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            categories = fetchedCategories
            roomModels.removeAll()

            // 自动加载第一个分类的房间列表
            if !categories.isEmpty {
                selectedMainCategoryIndex = 0
                if !currentSubCategories.isEmpty {
                    selectedSubCategoryIndex = 0
                    await loadRoomList()
                }
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            Logger.warning("获取分类列表失败: \(error)", category: .network)
            categoryError = error
        }
    }

    // MARK: - 全量刷新(分类 + 房间)

    /// 重新拉取分类列表并刷新当前分类下的房间。
    /// 尽量按标题保留用户当前选中的主/子分类,匹配不到再回退到第一个。
    @MainActor
    func refreshAll() async {
        let requestID = UUID()
        catalogRequestID = requestID
        // 记录当前选中分类的标题,用于刷新后恢复
        let previousMainTitle = currentMainCategory?.title
        let previousSubTitle = currentSubCategory?.title

        isLoadingCategories = true
        categoryError = nil
        defer { if catalogRequestID == requestID { isLoadingCategories = false } }

        do {
            let fetchedCategories = try await LiveService.fetchCategoryList(liveType: platform.liveType)
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            categories = fetchedCategories
            roomModels.removeAll()

            guard !categories.isEmpty else { return }

            // 恢复主分类选择
            if let previousMainTitle,
               let mainIndex = categories.firstIndex(where: { $0.title == previousMainTitle }) {
                selectedMainCategoryIndex = mainIndex
            } else {
                selectedMainCategoryIndex = 0
            }

            // 恢复子分类选择
            let subList = currentSubCategories
            if let previousSubTitle,
               let subIndex = subList.firstIndex(where: { $0.title == previousSubTitle }) {
                selectedSubCategoryIndex = subIndex
            } else {
                selectedSubCategoryIndex = 0
            }

            if currentSubCategory != nil {
                await loadRoomList()
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            Logger.warning("刷新分类列表失败: \(error)", category: .network)
            categoryError = error
        }
    }

    // MARK: - 获取房间列表

    @MainActor
    func loadRoomList(refresh: Bool = true) async {
        guard let subCategory = currentSubCategory else { return }
        let key = cacheKey
        let model: CategoryRoomListModel
        if let cached = roomModels[key] {
            model = cached
        } else {
            let liveType = platform.liveType
            let parentBiz = currentMainCategory?.biz
            model = CategoryRoomListModel { page in
                do {
                    return try await LiveService.fetchRoomList(
                        liveType: liveType, category: subCategory, parentBiz: parentBiz, page: page
                    )
                } catch {
                    if (error as? AFError)?.isExplicitlyCancelledError == true {
                        throw CancellationError()
                    }
                    // Preserve the existing plugin empty-result compatibility.
                    if let parseError = error as? LiveParseError,
                       parseError.detail.contains("返回结果为空") {
                        return []
                    }
                    throw error
                }
            }
            roomModels[key] = model
        }
        await model.load(refresh: refresh)
    }

    // MARK: - 加载更多

    @MainActor
    func loadMore() async {
        guard !isLoadingRooms, hasMoreRooms else { return }
        await loadRoomList(refresh: false)
    }

    // MARK: - 切换主分类

    @MainActor
    func selectMainCategory(index: Int) async {
        guard index != selectedMainCategoryIndex,
              categories.indices.contains(index) else { return }

        selectedMainCategoryIndex = index
        selectedSubCategoryIndex = 0
        await loadRoomList()
    }

    // MARK: - 切换子分类

    @MainActor
    func selectSubCategory(index: Int) async {
        guard currentSubCategories.indices.contains(index) else { return }

        selectedSubCategoryIndex = index

        // 检查是否有缓存数据，没有则加载
        if roomList.isEmpty {
            await loadRoomList()
        }
    }

    // MARK: - 一次性切换主/子分类

    /// 同时切换主分类与子分类,只在缓存缺失时发一次房间请求。
    /// 供分类筛选面板使用:面板先关闭,再在后台完成切换,避免「等两次网络请求才关窗」的卡顿。
    @MainActor
    func selectCategory(mainIndex: Int, subIndex: Int) async {
        guard categories.indices.contains(mainIndex) else { return }
        selectedMainCategoryIndex = mainIndex

        let subList = currentSubCategories
        guard subList.indices.contains(subIndex) else { return }
        selectedSubCategoryIndex = subIndex

        // 命中缓存则不再请求,直接沿用已有房间列表。
        if roomList.isEmpty {
            await loadRoomList()
        }
    }
}
