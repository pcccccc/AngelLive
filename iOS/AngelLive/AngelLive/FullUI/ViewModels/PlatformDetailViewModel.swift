//
//  PlatformDetailViewModel.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import Foundation
import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies
import Alamofire

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

    // 房间列表 - 使用字典按分类索引缓存
    var roomListCache: [String: [LiveModel]] = [:]

    var roomList: [LiveModel] {
        get {
            let key = cacheKey
            return roomListCache[key] ?? []
        }
        set {
            let key = cacheKey
            roomListCache[key] = newValue
        }
    }

    private var cacheKey: String {
        cacheKey(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
    }

    private func cacheKey(mainCategoryIndex: Int, subCategoryIndex: Int) -> String {
        "\(mainCategoryIndex)-\(subCategoryIndex)"
    }

    func rooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> [LiveModel] {
        roomListCache[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)] ?? []
    }

    // 加载状态
    var isLoadingCategories = false
    private var loadingRoomKeys: Set<String> = []

    var isLoadingRooms: Bool {
        isLoadingRooms(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
    }

    // 错误状态
    var categoryError: Error?
    private var roomErrors: [String: Error] = [:]

    var roomError: Error? {
        get { roomError(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex) }
        set {
            let key = cacheKey(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
            roomErrors[key] = newValue
        }
    }

    // 分页
    private var currentPages: [String: Int] = [:]
    private let pageSize = 20
    private var hasMoreRoomsByKey: [String: Bool] = [:]

    var currentPage: Int {
        get { currentPage(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex) }
        set {
            let key = cacheKey(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
            currentPages[key] = newValue
        }
    }

    var hasMoreRooms: Bool {
        get { canLoadMoreRooms(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex) }
        set {
            let key = cacheKey(mainCategoryIndex: selectedMainCategoryIndex, subCategoryIndex: selectedSubCategoryIndex)
            hasMoreRoomsByKey[key] = newValue
        }
    }

    func currentPage(mainCategoryIndex: Int, subCategoryIndex: Int) -> Int {
        currentPages[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)] ?? 1
    }

    func canLoadMoreRooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> Bool {
        hasMoreRoomsByKey[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)] ?? true
    }

    func isLoadingRooms(mainCategoryIndex: Int, subCategoryIndex: Int) -> Bool {
        loadingRoomKeys.contains(cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex))
    }

    func roomError(mainCategoryIndex: Int, subCategoryIndex: Int) -> Error? {
        roomErrors[cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)]
    }

    init(platform: Platformdescription) {
        self.platform = platform
    }

    // MARK: - 获取分类列表

    @MainActor
    func loadCategories() async {
        isLoadingCategories = true
        categoryError = nil
        defer { isLoadingCategories = false }

        do {
            let fetchedCategories = try await LiveService.fetchCategoryList(liveType: platform.liveType)
            categories = fetchedCategories

            // 自动加载第一个分类的房间列表
            if !categories.isEmpty {
                selectedMainCategoryIndex = 0
                if !currentSubCategories.isEmpty {
                    selectedSubCategoryIndex = 0
                    await loadRoomList()
                }
            }
        } catch {
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

    @MainActor
    func loadRoomList(mainCategoryIndex: Int, subCategoryIndex: Int, refresh: Bool = true) async {
        guard categories.indices.contains(mainCategoryIndex) else { return }
        let mainCategory = categories[mainCategoryIndex]
        guard mainCategory.subList.indices.contains(subCategoryIndex) else { return }

        let subCategory = mainCategory.subList[subCategoryIndex]
        let requestKey = cacheKey(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex)
        guard !loadingRoomKeys.contains(requestKey) else { return }

        if refresh {
            currentPages[requestKey] = 1
            hasMoreRoomsByKey[requestKey] = true
            roomListCache[requestKey] = []
            roomErrors[requestKey] = nil
        }

        let requestPage = currentPages[requestKey] ?? 1
        loadingRoomKeys.insert(requestKey)
        defer { loadingRoomKeys.remove(requestKey) }

        do {
            // 获取 parentBiz (对于 YY 平台可能需要)
            let parentBiz = mainCategory.biz

            let fetchedRooms = try await LiveService.fetchRoomList(
                liveType: platform.liveType,
                category: subCategory,
                parentBiz: parentBiz,
                page: requestPage
            )

            hasMoreRoomsByKey[requestKey] = !fetchedRooms.isEmpty

            if refresh {
                roomListCache[requestKey] = fetchedRooms.removingDuplicates()
            } else {
                let currentRooms = roomListCache[requestKey] ?? []
                roomListCache[requestKey] = currentRooms.appendingUnique(contentsOf: fetchedRooms)
            }
            // 清除错误状态（加载成功）
            roomErrors[requestKey] = nil
        } catch {
            if !refresh {
                currentPages[requestKey] = max(1, requestPage - 1)
            }

            // 检查是否是取消错误
            let isCancelled = (error as? AFError)?.isExplicitlyCancelledError ?? false
                || error is CancellationError
                || (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled

            if isCancelled {
                return
            }

            // 插件抛 "返回结果为空" 不算错误:分页到底 / 当前分类无房间。
            // 不挂 roomError,只置 hasMoreRooms=false;首页刷新场景 roomList 已在 refresh 入口清空。
            if let liveParseError = error as? LiveParseError,
               liveParseError.detail.contains("返回结果为空") {
                hasMoreRoomsByKey[requestKey] = false
                return
            }

            Logger.warning("获取房间列表失败: \(error)", category: .network)
            roomErrors[requestKey] = error
        }
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
        guard !loadingRoomKeys.contains(requestKey),
              canLoadMoreRooms(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex) else {
            return roomListCache[requestKey] ?? []
        }

        currentPages[requestKey] = (currentPages[requestKey] ?? 1) + 1
        await loadRoomList(mainCategoryIndex: mainCategoryIndex, subCategoryIndex: subCategoryIndex, refresh: false)
        return roomListCache[requestKey] ?? []
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
}
