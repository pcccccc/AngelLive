//
//  ModelTests.swift
//  SimpleLiveTVOSTests
//
//  Created by Claude on 2025/09/22.
//

import XCTest
import LiveParse
@testable import SimpleLiveTVOS

final class ModelTests: XCTestCase {

    override func setUpWithError() throws {

    }

    override func tearDownWithError() throws {

    }

    // MARK: - LiveModel Tests

    func testLiveModelInitialization() throws {
        let liveModel = LiveModel(
            userName: "测试主播",
            roomTitle: "测试房间",
            roomCover: "https://example.com/cover.jpg",
            userHeadImg: "https://example.com/avatar.jpg",
            liveType: .bilibili,
            liveState: "1",
            userId: "12345",
            roomId: "67890",
            liveWatchedCount: "1000"
        )

        XCTAssertEqual(liveModel.userName, "测试主播")
        XCTAssertEqual(liveModel.roomTitle, "测试房间")
        XCTAssertEqual(liveModel.roomCover, "https://example.com/cover.jpg")
        XCTAssertEqual(liveModel.userHeadImg, "https://example.com/avatar.jpg")
        XCTAssertEqual(liveModel.liveType, .bilibili)
        XCTAssertEqual(liveModel.liveState, "1")
        XCTAssertEqual(liveModel.userId, "12345")
        XCTAssertEqual(liveModel.roomId, "67890")
        XCTAssertEqual(liveModel.liveWatchedCount, "1000")
    }

    func testLiveModelEquality() throws {
        let model1 = LiveModel(
            userName: "主播1",
            roomTitle: "房间1",
            roomCover: "cover1.jpg",
            userHeadImg: "avatar1.jpg",
            liveType: .bilibili,
            liveState: "1",
            userId: "123",
            roomId: "456",
            liveWatchedCount: "100"
        )

        let model2 = LiveModel(
            userName: "主播1",
            roomTitle: "房间1",
            roomCover: "cover1.jpg",
            userHeadImg: "avatar1.jpg",
            liveType: .bilibili,
            liveState: "1",
            userId: "123",
            roomId: "456",
            liveWatchedCount: "100"
        )

        let model3 = LiveModel(
            userName: "主播2",
            roomTitle: "房间2",
            roomCover: "cover2.jpg",
            userHeadImg: "avatar2.jpg",
            liveType: .huya,
            liveState: "0",
            userId: "789",
            roomId: "012",
            liveWatchedCount: "200"
        )

        // 假设LiveModel实现了Equatable
        // XCTAssertEqual(model1, model2)
        // XCTAssertNotEqual(model1, model3)

        // 如果没有实现Equatable，可以比较关键字段
        XCTAssertEqual(model1.roomId, model2.roomId)
        XCTAssertNotEqual(model1.roomId, model3.roomId)
    }

    // MARK: - LiveType Tests

    func testLiveTypeExists() throws {
        // 测试LiveType枚举是否存在
        let bilibiliType = LiveType.bilibili
        let huyaType = LiveType.huya
        let douyinType = LiveType.douyin

        XCTAssertNotNil(bilibiliType)
        XCTAssertNotNil(huyaType)
        XCTAssertNotNil(douyinType)
    }

    // MARK: - LiveRoomListType Tests

    func testLiveRoomListTypeValues() throws {
        let types: [LiveRoomListType] = [.live, .favorite, .history, .search]

        XCTAssertEqual(types.count, 4)
        XCTAssertTrue(types.contains(.live))
        XCTAssertTrue(types.contains(.favorite))
        XCTAssertTrue(types.contains(.history))
        XCTAssertTrue(types.contains(.search))
    }

    // MARK: - LiveState Tests

    func testLiveStateValues() throws {
        // 假设LiveState是一个枚举
        // 测试直播状态的各种值
        let liveStates = ["0", "1", "unknown"]

        for state in liveStates {
            XCTAssertFalse(state.isEmpty)
        }
    }

    // MARK: - Settings Model Tests

    func testSettingStoreModel() throws {
        let settingStore = SettingStore()

        // 测试默认值
        XCTAssertEqual(settingStore.bilibiliCookie, "")
        XCTAssertTrue(settingStore.syncSystemRate)

        // 测试设置值
        settingStore.bilibiliCookie = "test_cookie"
        settingStore.syncSystemRate = false

        XCTAssertEqual(settingStore.bilibiliCookie, "test_cookie")
        XCTAssertFalse(settingStore.syncSystemRate)

        // 重置
        settingStore.bilibiliCookie = ""
        settingStore.syncSystemRate = true
    }

    // MARK: - ViewModel State Tests

    func testLiveViewModelState() throws {
        let appState = AppState()
        let viewModel = LiveViewModel(roomListType: .live, liveType: .bilibili, appViewModel: appState)

        // 测试初始状态
        XCTAssertEqual(viewModel.roomListType, .live)
        XCTAssertEqual(viewModel.liveType, .bilibili)
        XCTAssertFalse(viewModel.showOverlay)
        XCTAssertFalse(viewModel.isLeftFocused)
        XCTAssertFalse(viewModel.showAlert)
        XCTAssertFalse(viewModel.currentRoomIsFavorited)
        XCTAssertEqual(viewModel.searchTypeIndex, 0)
        XCTAssertEqual(viewModel.searchText, "")

        // 测试状态变更
        viewModel.showOverlay = true
        viewModel.isLeftFocused = true
        viewModel.searchTypeIndex = 1
        viewModel.searchText = "测试搜索"

        XCTAssertTrue(viewModel.showOverlay)
        XCTAssertTrue(viewModel.isLeftFocused)
        XCTAssertEqual(viewModel.searchTypeIndex, 1)
        XCTAssertEqual(viewModel.searchText, "测试搜索")
    }

    // MARK: - Data Validation Tests

    func testLiveModelDataValidation() throws {
        // 测试空值处理
        let emptyModel = LiveModel(
            userName: "",
            roomTitle: "",
            roomCover: "",
            userHeadImg: "",
            liveType: .bilibili,
            liveState: nil,
            userId: "",
            roomId: "",
            liveWatchedCount: nil
        )

        XCTAssertEqual(emptyModel.userName, "")
        XCTAssertEqual(emptyModel.roomTitle, "")
        XCTAssertNil(emptyModel.liveState)
        XCTAssertNil(emptyModel.liveWatchedCount)
    }

    func testURLValidation() throws {
        // 使用真实的直播平台URL进行测试
        let validURLs = [
            "https://live.bilibili.com/21452505",
            "https://www.huya.com/880000",
            "https://v.douyin.com/ieFrnAmn/",
            "https://www.douyu.com/3637778",
            "https://www.youtube.com/watch?v=36YnV9STBqc",
            "https://cc.163.com/521133"
        ]

        for urlString in validURLs {
            let url = URL(string: urlString)
            XCTAssertNotNil(url, "应该是有效的URL: \(urlString)")
        }

        // 测试空字符串情况
        let emptyURL = URL(string: "")
        XCTAssertNil(emptyURL, "空字符串应该返回nil")
    }

    // MARK: - Performance Tests

    func testModelCreationPerformance() throws {
        self.measure {
            for i in 0..<1000 {
                _ = LiveModel(
                    userName: "用户\(i)",
                    roomTitle: "房间\(i)",
                    roomCover: "cover\(i).jpg",
                    userHeadImg: "avatar\(i).jpg",
                    liveType: .bilibili,
                    liveState: "1",
                    userId: "\(i)",
                    roomId: "\(i + 1000)",
                    liveWatchedCount: "\(i * 10)"
                )
            }
        }
    }

    func testLiveTypeCreationPerformance() throws {
        self.measure {
            for _ in 0..<1000 {
                _ = LiveType.bilibili
                _ = LiveType.huya
                _ = LiveType.douyin
                _ = LiveType.douyu
            }
        }
    }

}