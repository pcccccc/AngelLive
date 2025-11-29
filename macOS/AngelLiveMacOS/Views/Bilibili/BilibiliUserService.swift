//
//  BilibiliUserService.swift
//  AngelLiveMacOS
//
//  Created by Claude on 11/29/25.
//

import Foundation

// MARK: - Bilibili API Service

actor BilibiliUserService {
    static let shared = BilibiliUserService()

    private init() {}

    /// 获取用户信息，同时验证 Cookie 是否有效
    func loadUserInfo(cookie: String) async -> Result<BilibiliUserInfo, BilibiliUserError> {
        guard !cookie.isEmpty else {
            return .failure(.emptyCookie)
        }

        guard let url = URL(string: "https://api.bilibili.com/x/member/web/account") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[BilibiliUserService] API Response: \(jsonString.prefix(500))")
            }
            #endif

            let response = try JSONDecoder().decode(BilibiliUserInfoResponse.self, from: data)

            if response.code == 0, let userInfo = response.data {
                return .success(userInfo)
            } else {
                let errorMsg = response.message ?? "Cookie 已失效 (code: \(response.code))"
                return .failure(.cookieExpired(message: errorMsg))
            }
        } catch let error as DecodingError {
            print("[BilibiliUserService] Decoding error: \(error)")
            return .failure(.decodingError(error))
        } catch {
            print("[BilibiliUserService] Network error: \(error)")
            return .failure(.networkError(error))
        }
    }
}
