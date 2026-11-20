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
    @ObservationIgnored private var roomTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var catalogRequestID = UUID()
    @ObservationIgnored private var catalogGeneration = UUID()

    var roomList: [LiveModel] { roomModels[cacheKey]?.rooms ?? [] }
    var currentRoomListModel: CategoryRoomListModel? { roomModels[cacheKey] }

    private var cacheKey: String {
        "\(selectedMainCategoryIndex)-\(selectedSubCategoryIndex)"
    }

    // 加载状态
    var isLoadingCategories = false
    var isLoadingRooms: Bool { roomModels[cacheKey]?.isLoading ?? false }
    var isLoadingMoreRooms: Bool { roomModels[cacheKey]?.isLoadingMore ?? false }
    var roomListPhase: RoomListDisplayPhase { roomModels[cacheKey]?.phase ?? .skeleton }

    // 错误状态
    var categoryError: Error?
    var roomError: Error? {
        guard roomModels[cacheKey]?.phase == .failure else { return nil }
        return roomModels[cacheKey]?.error
    }

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
            replaceRoomCatalog()

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
            replaceRoomCatalog()

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
        let generation = catalogGeneration
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

        let previous = roomTasks[key]
        previous?.cancel()
        await previous?.value
        guard !Task.isCancelled, catalogGeneration == generation, roomModels[key] != nil else { return }
        let task = Task { @MainActor in
            await model.load(refresh: refresh)
        }
        roomTasks[key] = task
        await task.value
    }

    /// 切到当前分类：取消其它分类的请求，有缓存就留在原地再刷新。
    @MainActor
    private func activateCurrentCategory() async {
        let key = cacheKey
        for (other, task) in roomTasks where other != key {
            task.cancel()
        }
        await loadRoomList(refresh: true)
    }

    @MainActor
    private func replaceRoomCatalog() {
        catalogGeneration = UUID()
        for task in roomTasks.values {
            task.cancel()
        }
        roomTasks.removeAll()
        roomModels.removeAll()
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
        await activateCurrentCategory()
    }

    // MARK: - 切换子分类

    @MainActor
    func selectSubCategory(index: Int) async {
        guard currentSubCategories.indices.contains(index), index != selectedSubCategoryIndex else { return }
        selectedSubCategoryIndex = index
        await activateCurrentCategory()
    }

    // MARK: - 一次性切换主/子分类

    /// 同时切换主分类与子分类。换了分类就后台刷新，缓存先留在屏幕上。
    @MainActor
    func selectCategory(mainIndex: Int, subIndex: Int) async {
        guard categories.indices.contains(mainIndex) else { return }
        let subList = categories[mainIndex].subList
        guard subList.indices.contains(subIndex) else { return }
        let keyChanged = mainIndex != selectedMainCategoryIndex || subIndex != selectedSubCategoryIndex
        selectedMainCategoryIndex = mainIndex
        selectedSubCategoryIndex = subIndex
        guard keyChanged || roomModels[cacheKey] == nil else { return }
        await activateCurrentCategory()
    }
}
