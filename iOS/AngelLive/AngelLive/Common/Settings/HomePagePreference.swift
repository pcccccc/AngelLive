//
//  HomePagePreference.swift
//  AngelLive
//
//  iOS 首页展示偏好。
//

import Foundation

enum HomePagePreference: String, CaseIterable {
    static let storageKey = "SimpleLive.Setting.iOSHomePagePreference"
    static let selectedPluginStorageKey = "SimpleLive.Setting.iOSHomeSelectedPluginId"

    case recommendations
    case favorites

    var displayName: String {
        switch self {
        case .recommendations:
            "推荐"
        case .favorites:
            "收藏"
        }
    }
}
