//
//  BilibiliAccountService.swift
//  AngelLiveCore
//
//  Created by Codex on 2026/2/17.
//

import Foundation

public struct BilibiliAccountUserInfo: Codable, Sendable {
    public let mid: Int?
    public let uname: String?
    public let userid: String?
    public let sign: String?
    public let birthday: String?
    public let sex: String?
    public let rank: String?
    public let face: String?
    public let nickFree: Bool?

    enum CodingKeys: String, CodingKey {
        case mid, uname, userid, sign, birthday, sex, rank, face
        case nickFree = "nick_free"
    }

    public var displayName: String {
        uname ?? "未知用户"
    }
}

public enum BilibiliAccountError: Error, LocalizedError, Sendable {
    case emptyCookie
    case invalidURL
    case cookieExpired(message: String)
    case networkError(message: String)
    case decodingError(message: String)
    case invalidResponse(message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyCookie:
            return "Cookie 为空"
        case .invalidURL:
            return "无效的 URL"
        case .cookieExpired(let message):
            return "登录已失效: \(message)"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .decodingError(let message):
            return "数据解析错误: \(message)"
        case .invalidResponse(let message):
            return "接口返回异常: \(message)"
        }
    }
}

private struct BilibiliAccountResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: BilibiliAccountUserInfo?
}

public actor BilibiliAccountService {
    public static let shared = BilibiliAccountService()

    private init() {}

    public func loadUserInfo(
        cookie: String,
        userAgent: String,
        referer: String? = "https://www.bilibili.com"
    ) async -> Result<BilibiliAccountUserInfo, BilibiliAccountError> {
        guard !cookie.isEmpty else {
            return .failure(.emptyCookie)
        }

        guard let url = URL(string: "https://api.bilibili.com/x/member/web/account") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(BilibiliAccountResponse.self, from: data)

            guard response.code == 0 else {
                let errorMessage = response.message ?? "Cookie 已失效 (code: \(response.code))"
                return .failure(.cookieExpired(message: errorMessage))
            }

            guard let userInfo = response.data else {
                return .failure(.invalidResponse(message: "响应缺少用户数据"))
            }

            return .success(userInfo)
        } catch let error as DecodingError {
            return .failure(.decodingError(message: String(describing: error)))
        } catch {
            return .failure(.networkError(message: error.localizedDescription))
        }
    }
}
