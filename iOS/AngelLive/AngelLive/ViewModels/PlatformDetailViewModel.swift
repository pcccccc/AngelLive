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
        "\(selectedMainCategoryIndex)-\(selectedSubCategoryIndex)"
    }

    // 加载状态
    var isLoadingCategories = false
    var isLoadingRooms = false

    // 错误状态
    var categoryError: Error?
    var roomError: Error?

    // 分页
    var currentPage = 1
    private let pageSize = 20

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
            print("获取分类列表失败: \(error)")
            categoryError = error
        }
    }

    // MARK: - 获取房间列表

    @MainActor
    func loadRoomList(refresh: Bool = true) async {
        guard let subCategory = currentSubCategory else { return }

        if refresh {
            currentPage = 1
            roomList.removeAll()
            roomError = nil
        }

        isLoadingRooms = true
        defer { isLoadingRooms = false }

        do {
            // 获取 parentBiz (对于 YY 平台可能需要)
            let parentBiz = currentMainCategory?.biz

            let fetchedRooms = try await LiveService.fetchRoomList(
                liveType: platform.liveType,
                category: subCategory,
                parentBiz: parentBiz,
                page: currentPage
            )

            if refresh {
                roomList = fetchedRooms.removingDuplicates()
            } else {
                roomList = roomList.appendingUnique(contentsOf: fetchedRooms)
            }
            // 清除错误状态（加载成功）
            roomError = nil
        } catch {
            // 检查是否是取消错误
            let isCancelled = (error as? AFError)?.isExplicitlyCancelledError ?? false
                || error is CancellationError
                || (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled

            if !isCancelled {
                // 只有非取消错误才设置到 roomError
                print("获取房间列表失败: \(error)")
                roomError = error
            }
        }
    }

    // MARK: - 加载更多

    @MainActor
    func loadMore() async {
        guard !isLoadingRooms else { return }
        currentPage += 1
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
}
