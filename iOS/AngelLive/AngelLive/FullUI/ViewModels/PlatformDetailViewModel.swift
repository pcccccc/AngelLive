//
//  PlatformDetailViewModel.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import Alamofire
import Foundation
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies

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

    private var roomModels: [String: CategoryRoomListModel] = [:]
    @ObservationIgnored private var roomTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeRoomKey: String?

    var roomList: [LiveModel] {
        rooms(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
    }

    private func cacheKey(mainCategoryIndex: Int, subCategoryIndex: Int) -> String {
        "\(mainCategoryIndex)-\(subCategoryIndex)"
    }

    func rooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> [LiveModel] {
        roomModels[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]?.rooms ?? []
    }

    // 加载状态
    var isLoadingCategories = false
    @ObservationIgnored private var catalogRequestID = UUID()
    @ObservationIgnored private var catalogGeneration = UUID()

    var isLoadingRooms: Bool {
        isLoadingRooms(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
    }

    // 错误状态
    var categoryError: Error?

    var roomError: Error? {
        roomError(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
    }

    var hasMoreRooms: Bool {
        canLoadMoreRooms(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
    }

    func canLoadMoreRooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> Bool {
        roomModels[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]?.hasMore ?? true
    }

    func isLoadingRooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> Bool {
        roomModels[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]?.isLoading ?? false
    }

    func isLoadingMoreRooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> Bool {
        roomModels[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]?.isLoadingMore ?? false
    }

    func roomError(mainCategoryIndex: Int, subCategoryIndex: Int) -> Error? {
        let model = roomModels[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]
        guard model?.phase == .failure else { return nil }
        return model?.error
    }

    func roomListPhase(mainCategoryIndex: Int, subCategoryIndex: Int) -> RoomListDisplayPhase {
        roomModels[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]?.phase ?? .skeleton
    }

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
            catalogGeneration = UUID()
            categories = fetchedCategories
            cancelAllRoomLoads()
            roomModels.removeAll()
            activeRoomKey = nil

            // 自动加载第一个分类的房间列表
            if !categories.isEmpty {
                selectedMainCategoryIndex = 0
                if !currentSubCategories.isEmpty {
                    selectedSubCategoryIndex = 0
                    activeRoomKey = cacheKey(mainCategoryIndex: 0, subCategoryIndex: 0)
                    await loadRoomList()
                }
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            Logger.warning("获取分类列表失败: \(error)", category: .network)
            categoryError = error
        }
    }

    // MARK: - 获取房间列表

    @MainActor
    func loadRoomList(refresh: Bool = true) async {
        await loadRoomList(
            mainCategoryIndex: selectedMainCategoryIndex,
            subCategoryIndex: selectedSubCategoryIndex,
            refresh: refresh
        )
    }

    /// 切到这个分类：取消其它分类仍在进行的请求，有缓存就先显示再刷新。
    @MainActor
    func activateCategory(mainCategoryIndex: Int, subCategoryIndex: Int) async {
        let key = cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
        let isNewSelection = activeRoomKey != key
        activeRoomKey = key
        if isNewSelection {
            cancelRoomLoads(except: key)
        }
        let currentTask = roomTasks[key]
        let keepsInFlightLoad = currentTask?.isCancelled == false
            && isLoadingRooms(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
        if isNewSelection {
            // 这个分类自己的请求还在飞（例如首屏）时接着用，不重新开始。
            guard !keepsInFlightLoad else { return }
            await loadRoomList(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
            return
        }
        let phase = roomListPhase(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
        guard phase == .skeleton, !keepsInFlightLoad else { return }
        await loadRoomList(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
    }

    @MainActor
    func loadRoomList(mainCategoryIndex: Int, subCategoryIndex: Int, refresh: Bool = true) async {
        guard categories.indices.contains(mainCategoryIndex) else { return }
        let mainCategory = categories[mainCategoryIndex]
        guard mainCategory.subList.indices.contains(subCategoryIndex) else { return }

        let generation = catalogGeneration
        let requestKey = cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
        let subCategory = mainCategory.subList[subCategoryIndex]
        let parentBiz = mainCategory.biz
        let liveType = platform.liveType
        if roomModels[requestKey] == nil {
            roomModels[requestKey] = CategoryRoomListModel { page in
                do {
                    return try await LiveService.fetchRoomList(
                        liveType: liveType,
                        category: subCategory,
                        parentBiz: parentBiz,
                        page: page
                    )
                } catch {
                    if (error as? AFError)?.isExplicitlyCancelledError == true {
                        throw CancellationError()
                    }
                    if let parseError = error as? LiveParseError,
                       parseError.detail.contains("返回结果为空") {
                        return []
                    }
                    throw error
                }
            }
        }

        let previous = roomTasks[requestKey]
        previous?.cancel()
        await previous?.value
        guard !Task.isCancelled, catalogGeneration == generation else { return }
        guard let model = roomModels[requestKey] else { return }

        let task = Task { @MainActor in
            await model.load(refresh: refresh)
        }
        roomTasks[requestKey] = task
        await task.value
        guard catalogGeneration == generation else { return }
    }

    // MARK: - 加载更多

    @MainActor
    func loadMore() async {
        _ = await loadMoreRooms(
            mainCategoryIndex: selectedMainCategoryIndex,
            subCategoryIndex: selectedSubCategoryIndex
        )
    }

    @MainActor
    @discardableResult
    func loadMoreRooms(mainCategoryIndex: Int, subCategoryIndex: Int) async -> [LiveModel] {
        let requestKey = cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
        guard canLoadMoreRooms(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex),
              !isLoadingRooms(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex) else {
            return roomModels[requestKey]?.rooms ?? []
        }
        await loadRoomList(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex, refresh: false)
        return roomModels[requestKey]?.rooms ?? []
    }

    // MARK: - 切换主分类

    @MainActor
    func selectMainCategory(index: Int) async {
        guard index != selectedMainCategoryIndex,
              categories.indices.contains(index) else { return }

        selectedMainCategoryIndex = index
        selectedSubCategoryIndex = 0
        await activateCategory(mainCategoryIndex: index, subCategoryIndex: 0)
    }

    // MARK: - 切换子分类

    @MainActor
    func selectSubCategory(index: Int) async {
        guard currentSubCategories.indices.contains(index) else { return }
        selectedSubCategoryIndex = index
        await activateCategory(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: index)
    }

    @MainActor
    private func cancelRoomLoads(except key: String) {
        for (other, task) in roomTasks where other != key {
            task.cancel()
        }
    }

    @MainActor
    private func cancelAllRoomLoads() {
        for task in roomTasks.values {
            task.cancel()
        }
        roomTasks.removeAll()
    }
}
