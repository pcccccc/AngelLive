//
//  BilibiliUserInfo.swift
//  AngelLiveMacOS
//
//  Created by Claude on 11/29/25.
//

import Foundation

// MARK: - Bilibili User Info Model

struct BilibiliUserInfo: Codable {
    let mid: Int?
    let uname: String?
    let userid: String?
    let sign: String?
    let birthday: String?
    let sex: String?
    let rank: String?
    let face: String?
    let nickFree: Bool?

    enum CodingKeys: String, CodingKey {
        case mid, uname, userid, sign, birthday, sex, rank, face
        case nickFree = "nick_free"
    }

    var displayName: String {
        uname ?? "未知用户"
    }
}

// MARK: - API Response

struct BilibiliUserInfoResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: BilibiliUserInfo?

    enum CodingKeys: String, CodingKey {
        case code, message, ttl, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl)
        data = try container.decodeIfPresent(BilibiliUserInfo.self, forKey: .data)
    }
}

// MARK: - Error Types

enum BilibiliUserError: Error, LocalizedError {
    case emptyCookie
    case invalidURL
    case cookieExpired(message: String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .emptyCookie:
            return "Cookie 为空"
        case .invalidURL:
            return "无效的 URL"
        case .cookieExpired(let message):
            return "登录已失效: \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .decodingError:
            return "数据解析错误"
        }
    }
}
