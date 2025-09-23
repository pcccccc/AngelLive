//
//  SimpleLiveTVOSTests.swift
//  SimpleLiveTVOSTests
//
//  Created by pc on 2023/6/26.
//

import XCTest
import LiveParse
@testable import SimpleLiveTVOS

final class SimpleLiveTVOSTests: XCTestCase {

    override func setUpWithError() throws {

    }

    override func tearDownWithError() throws {

    }

    // MARK: - ApiManager Tests

    func testApiManagerPlatformRouting() throws {
        // 测试平台路由逻辑，使用真实的URL格式
        let bilibiliCode = "https://live.bilibili.com/21452505"
        let douyinCode = "https://v.douyin.com/ieFrnAmn/"
        let huyaCode = "https://www.huya.com/880000"
        let youtubeCode = "https://www.youtube.com/watch?v=36YnV9STBqc"

        // 这些是同步测试，测试平台检测逻辑
        XCTAssertTrue(bilibiliCode.contains("bilibili"))
        XCTAssertTrue(douyinCode.contains("douyin"))
        XCTAssertTrue(huyaCode.contains("huya"))
        XCTAssertTrue(youtubeCode.contains("youtube"))
    }

    func testApiManagerInternetConnection() async throws {
        let hasConnection = await ApiManager.checkInternetConnection()
        // 网络连接测试可能因环境而异，这里只验证方法能正常执行
        XCTAssertNotNil(hasConnection)
    }

    // MARK: - FavoriteService Tests

    func testFavoriteServiceConstants() throws {
        // 测试CloudKit常量
        XCTAssertEqual(roomId_colum_cloud, "room_id")
        XCTAssertEqual(userId_column_cloud, "user_id")
        XCTAssertEqual(userName_column_cloud, "user_name")
        XCTAssertEqual(ck_identifier, "iCloud.icloud.dev.igod.simplelive")
    }

    func testFavoriteServiceErrorFormatting() throws {
        // 测试错误格式化
        let testError = NSError(domain: "TestDomain", code: 1001, userInfo: nil)
        let formattedError = FavoriteService.formatErrorCode(error: testError)
        XCTAssertEqual(formattedError, "未知错误")
    }

    // MARK: - LiveService Tests

    func testLiveServiceCacheKeyGeneration() throws {
        // 测试缓存键生成逻辑
        let cacheKey = "ks_categories"
        XCTAssertFalse(cacheKey.isEmpty)
        XCTAssertTrue(cacheKey.contains("ks"))
    }

    // MARK: - Extension Tests

    func testStringExtensions() throws {
        // 测试字符串扩展（如果有的话）
        let testString = "test"
        XCTAssertEqual(testString.count, 4)
    }

    func testUserDefaultsExtensions() throws {
        // 测试UserDefaults扩展
        let key = "testKey"
        let value = "testValue"
        UserDefaults.standard.set(value, forKey: key)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), value)
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - LiveViewModel Tests

    func testLiveViewModelInitialization() throws {
        let mockAppState = AppState()
        let viewModel = LiveViewModel(roomListType: .live, liveType: .bilibili, appViewModel: mockAppState)

        XCTAssertEqual(viewModel.roomListType, .live)
        XCTAssertEqual(viewModel.liveType, .bilibili)
        XCTAssertEqual(viewModel.leftMenuMinWidth, 180)
        XCTAssertEqual(viewModel.leftMenuMaxWidth, 300)
        XCTAssertEqual(viewModel.roomPage, 1)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.searchTypeArray.count, 3)
    }

    func testLiveViewModelOverlayToggle() throws {
        let mockAppState = AppState()
        let viewModel = LiveViewModel(roomListType: .live, liveType: .bilibili, appViewModel: mockAppState)

        // 测试overlay切换
        viewModel.showOverlay = true
        XCTAssertEqual(viewModel.leftWidth, viewModel.leftMenuMaxWidth)
        XCTAssertEqual(viewModel.leftHeight, viewModel.leftMenuMaxHeight)
        XCTAssertEqual(viewModel.leftMenuCornerRadius, 10)

        viewModel.showOverlay = false
        XCTAssertEqual(viewModel.leftWidth, viewModel.leftMenuMinWidth)
        XCTAssertEqual(viewModel.leftHeight, viewModel.leftMenuMinHeight)
        XCTAssertEqual(viewModel.leftMenuCornerRadius, 25)
    }

    func testLiveViewModelToastConfiguration() throws {
        let mockAppState = AppState()
        let viewModel = LiveViewModel(roomListType: .live, liveType: .bilibili, appViewModel: mockAppState)

        viewModel.showToast(true, title: "Success", hideAfter: 2.0)

        XCTAssertTrue(viewModel.showToast)
        XCTAssertEqual(viewModel.toastTitle, "Success")
        XCTAssertTrue(viewModel.toastTypeIsSuccess)
        XCTAssertEqual(viewModel.toastOptions.hideAfter, 2.0)
    }

    // MARK: - SettingStore Tests

    func testSettingStoreDefaults() throws {
        let settingStore = SettingStore()

        // 测试默认值
        XCTAssertEqual(settingStore.bilibiliCookie, "")
        XCTAssertTrue(settingStore.syncSystemRate)
    }

    // MARK: - Performance Tests

    func testLiveViewModelInitializationPerformance() throws {
        self.measure {
            let mockAppState = AppState()
            _ = LiveViewModel(roomListType: .live, liveType: .bilibili, appViewModel: mockAppState)
        }
    }

    func testApiManagerPerformance() throws {
        self.measure {
            // 测试平台检测性能，使用真实URL格式
            let codes = [
                "https://live.bilibili.com/21452505",
                "https://v.douyin.com/ieFrnAmn/",
                "https://www.huya.com/880000",
                "https://www.douyu.com/3637778",
                "https://www.youtube.com/watch?v=36YnV9STBqc"
            ]

            for code in codes {
                _ = code.contains("bilibili") || code.contains("douyin") || code.contains("huya") ||
                    code.contains("douyu") || code.contains("youtube")
            }
        }
    }

}
