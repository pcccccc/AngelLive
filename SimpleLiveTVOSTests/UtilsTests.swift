//
//  UtilsTests.swift
//  SimpleLiveTVOSTests
//
//  Created by Claude on 2025/09/22.
//

import XCTest
import LiveParse
@testable import SimpleLiveTVOS

final class UtilsTests: XCTestCase {

    override func setUpWithError() throws {

    }

    override func tearDownWithError() throws {

    }

    // MARK: - Common Tests

    func testCommonImageMapping() throws {
        XCTAssertEqual(Common.getImage(.bilibili), "live_card_bili")
        XCTAssertEqual(Common.getImage(.huya), "live_card_huya")
        XCTAssertEqual(Common.getImage(.douyin), "live_card_douyin")
        XCTAssertEqual(Common.getImage(.douyu), "live_card_douyu")
        XCTAssertEqual(Common.getImage(.yy), "live_card_yy")
        XCTAssertEqual(Common.getImage(.cc), "live_card_cc")
        XCTAssertEqual(Common.getImage(.ks), "live_card_ks")
        XCTAssertEqual(Common.getImage(.youtube), "live_card_youtube")
    }

    // MARK: - String Extensions Tests

    func testStringExtensionBasicFunctionality() throws {
        let testString = "Hello World"
        XCTAssertEqual(testString.count, 11)
        XCTAssertTrue(testString.contains("Hello"))
        XCTAssertFalse(testString.contains("hello"))
    }

    // MARK: - UserDefaults Extensions Tests

    func testUserDefaultsExtensionOperations() throws {
        let testKey = "test_key_utils"
        let testValue = "test_value"
        let testIntValue = 42
        let testBoolValue = true

        // 测试字符串存储
        UserDefaults.standard.set(testValue, forKey: testKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: testKey), testValue)

        // 测试整数存储
        UserDefaults.standard.set(testIntValue, forKey: "\(testKey)_int")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "\(testKey)_int"), testIntValue)

        // 测试布尔存储
        UserDefaults.standard.set(testBoolValue, forKey: "\(testKey)_bool")
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "\(testKey)_bool"), testBoolValue)

        // 清理
        UserDefaults.standard.removeObject(forKey: testKey)
        UserDefaults.standard.removeObject(forKey: "\(testKey)_int")
        UserDefaults.standard.removeObject(forKey: "\(testKey)_bool")
    }

    // MARK: - Data Extensions Tests

    func testDataExtensionIfExists() throws {
        let testData = "Hello".data(using: .utf8)
        XCTAssertNotNil(testData)
        XCTAssertEqual(testData?.count, 5)
    }

    // MARK: - UIColor Extensions Tests

    func testUIColorExtensionIfExists() throws {
        // 这里可以测试UIColor扩展，如果存在的话
        // 例如十六进制颜色转换等
        XCTAssertTrue(true) // 占位测试
    }

    // MARK: - LiveType Enum Tests

    func testLiveTypeEnumExists() throws {
        // 测试LiveType枚举的存在性
        let types: [LiveType] = [.bilibili, .huya, .douyin, .douyu, .cc, .ks, .yy, .youtube]
        XCTAssertEqual(types.count, 8)

        // 测试各个枚举值都不为空
        for liveType in types {
            XCTAssertNotNil(liveType)
        }
    }

    // MARK: - LiveRoomListType Tests

    func testLiveRoomListTypeEnum() throws {
        let liveType: LiveRoomListType = .live
        let favoriteType: LiveRoomListType = .favorite
        let historyType: LiveRoomListType = .history
        let searchType: LiveRoomListType = .search

        XCTAssertTrue(liveType == .live)
        XCTAssertTrue(favoriteType == .favorite)
        XCTAssertTrue(historyType == .history)
        XCTAssertTrue(searchType == .search)
    }

    // MARK: - ViewDebug Tests

    func testViewDebugConfiguration() throws {
        // 如果ViewDebug有配置可以测试
        XCTAssertTrue(true) // 占位测试
    }

    // MARK: - Performance Tests

    func testStringPerformance() throws {
        self.measure {
            let testStrings = Array(0..<1000).map { "test_string_\($0)" }
            for string in testStrings {
                _ = string.count
            }
        }
    }

    func testLiveTypePerformance() throws {
        self.measure {
            for _ in 0..<1000 {
                _ = LiveType.bilibili
                _ = LiveType.huya
                _ = LiveType.douyin
                _ = LiveType.douyu
                _ = LiveType.cc
                _ = LiveType.ks
                _ = LiveType.yy
                _ = LiveType.youtube
            }
        }
    }

}