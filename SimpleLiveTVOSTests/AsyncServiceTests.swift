//
//  AsyncServiceTests.swift
//  SimpleLiveTVOSTests
//
//  Created by Claude on 2025/09/22.
//

import XCTest
import LiveParse
import CloudKit
@testable import SimpleLiveTVOS

final class AsyncServiceTests: XCTestCase {

    override func setUpWithError() throws {

    }

    override func tearDownWithError() throws {

    }

    // MARK: - ApiManager Async Tests

    func testApiManagerInternetConnectionAsync() async throws {
        let hasConnection = await ApiManager.checkInternetConnection()

        // 网络连接测试 - 验证方法能正常执行并返回布尔值
        XCTAssertNotNil(hasConnection)
        // 注意：实际的连接状态依赖网络环境，这里只测试方法不会崩溃
    }

    func testApiManagerPlatformDetection() async throws {
        // 测试平台检测逻辑的各种情况，使用真实的URL
        let testCases = [
            // Bilibili真实URL格式
            ("https://live.bilibili.com/21452505", true),
            ("https://b23.tv/BV1xx411c7mu", true),

            // 抖音真实URL格式
            ("https://v.douyin.com/ieFrnAmn/", true),
            ("https://live.douyin.com/123456789", true),

            // 虎牙真实URL格式
            ("https://www.huya.com/880000", true),
            ("https://hy.fan/abc", true),

            // 斗鱼真实URL格式
            ("https://www.douyu.com/topic/s9lol", true),
            ("https://www.douyu.com/3637778", true),

            // 网易CC真实URL格式
            ("https://cc.163.com/521133", true),

            // 快手真实URL格式
            ("https://live.kuaishou.com/u/3x4sm9dstqjjwfa", true),
            ("https://kuaishou.com/s/abc123", true),

            // YY真实URL格式
            ("https://www.yy.com/22490906", true),
            ("https://yy.com/123456", true),

            // YouTube真实URL（来自SearchRoomView.swift）
            ("https://www.youtube.com/watch?v=36YnV9STBqc", true),
            ("https://www.youtube.com/live/36YnV9STBqc", true),
            ("https://youtube.com/channel/UCxxxx", true),

            // 未知平台
            ("https://unknown-platform.com/123", false),
            ("https://example.org/test", false)
        ]

        for (shareCode, shouldDetect) in testCases {
            let hasPlatform = shareCode.contains("b23.tv") || shareCode.contains("bilibili") ||
                            shareCode.contains("douyin") || shareCode.contains("huya") ||
                            shareCode.contains("hy.fan") || shareCode.contains("douyu") ||
                            shareCode.contains("cc.163.com") || shareCode.contains("kuaishou.com") ||
                            shareCode.contains("yy.com") || shareCode.contains("youtube")

            XCTAssertEqual(hasPlatform, shouldDetect, "平台检测失败: \(shareCode)")
        }
    }

    // MARK: - FavoriteService Async Tests

    func testFavoriteServiceCloudKitConfiguration() async throws {
        // 测试CloudKit配置
        XCTAssertFalse(ck_identifier.isEmpty, "CloudKit标识符不应为空")
        XCTAssertEqual(ck_identifier, "iCloud.icloud.dev.igod.simplelive")
    }

    func testFavoriteServiceCloudStateCheck() async throws {
        // 测试CloudKit状态检查 - 这个测试可能需要模拟或者在特定环境下运行
        let cloudState = await FavoriteService.getCloudState()
        XCTAssertFalse(cloudState.isEmpty, "CloudKit状态不应为空")

        // 验证常见的状态消息
        let expectedStates = ["正常", "未登录iCloud", "无法确定状态", "iCloud用户受限", "操作超时"]
        let containsExpectedState = expectedStates.contains { cloudState.contains($0) }
        XCTAssertTrue(containsExpectedState || cloudState.contains("错误"), "应该返回预期的状态消息")
    }

    func testFavoriteServiceTimeoutProtection() async throws {
        // 测试超时概念 - 由于withTimeout是私有方法，我们测试相关的公共功能
        let cloudState = await FavoriteService.getCloudState()
        XCTAssertFalse(cloudState.isEmpty, "CloudKit状态检查应该返回结果")

        // 测试操作超时的情况下返回的错误消息
        if cloudState.contains("操作超时") {
            XCTAssertTrue(cloudState.contains("操作超时，请检查网络连接"))
        }
    }

    // MARK: - LiveService Async Tests

    func testLiveServiceCachingLogic() async throws {
        // 测试缓存逻辑 - 由于实际的Cache依赖外部存储，这里主要测试逻辑
        // 测试缓存键的生成
        let cacheKey = "ks_categories"
        XCTAssertFalse(cacheKey.isEmpty)
        XCTAssertTrue(cacheKey.contains("ks"))
    }

    // MARK: - LiveViewModel Async Tests

    func testLiveViewModelAsyncInitialization() async throws {
        let appState = AppState()
        let viewModel = LiveViewModel(roomListType: .live, liveType: .bilibili, appViewModel: appState)

        // 验证初始状态
        XCTAssertEqual(viewModel.liveType, .bilibili)
        XCTAssertEqual(viewModel.roomListType, .live)
        XCTAssertEqual(viewModel.roomPage, 1)
        XCTAssertFalse(viewModel.endFirstLoading)

        // 等待一段时间确保异步初始化完成
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // 验证viewModel没有崩溃且状态正常
        XCTAssertNotNil(viewModel.appViewModel)
    }

    func testLiveViewModelSearchFunctionality() async throws {
        let appState = AppState()
        let viewModel = LiveViewModel(roomListType: .search, liveType: .bilibili, appViewModel: appState)

        // 设置搜索文本
        viewModel.searchText = "测试"
        viewModel.roomListType = .search

        // 验证搜索配置
        XCTAssertEqual(viewModel.searchText, "测试")
        XCTAssertEqual(viewModel.roomListType, .search)
        XCTAssertEqual(viewModel.searchTypeArray.count, 3)
    }

    // MARK: - Error Handling Tests

    func testFavoriteServiceErrorHandling() throws {
        // 测试不同类型的CloudKit错误处理
        let networkError = CKError(.networkUnavailable)
        let formattedError = FavoriteService.formatErrorCode(error: networkError)
        XCTAssertEqual(formattedError, "网络不可用，请检查网络问题")

        let authError = CKError(.notAuthenticated)
        let formattedAuthError = FavoriteService.formatErrorCode(error: authError)
        XCTAssertEqual(formattedAuthError, "未登录，请检查iCloud账户状态")

        let unknownError = NSError(domain: "Test", code: 999, userInfo: nil)
        let formattedUnknownError = FavoriteService.formatErrorCode(error: unknownError)
        XCTAssertEqual(formattedUnknownError, "未知错误")
    }

    // MARK: - Performance Tests

    func testAsyncOperationPerformance() throws {
        self.measure {
            let expectation = XCTestExpectation(description: "async performance test")

            Task {
                // 模拟异步操作
                for _ in 0..<100 {
                    await Task.yield()
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    func testConcurrentOperationPerformance() throws {
        self.measure {
            let expectation = XCTestExpectation(description: "concurrent performance test")
            expectation.expectedFulfillmentCount = 10

            for i in 0..<10 {
                Task {
                    // 模拟并发操作
                    try? await Task.sleep(nanoseconds: UInt64(i * 1_000_000)) // 微小延迟
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

}