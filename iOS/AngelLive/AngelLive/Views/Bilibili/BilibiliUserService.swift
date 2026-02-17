//
//  BilibiliUserService.swift
//  AngelLive
//
//  Created by pangchong on 11/28/25.
//

import Foundation
import AngelLiveCore

// MARK: - Bilibili API Service

actor BilibiliUserService {
    static let shared = BilibiliUserService()

    private init() {}

    /// 获取用户信息，同时验证 Cookie 是否有效
    func loadUserInfo(cookie: String) async -> Result<BilibiliUserInfo, BilibiliUserError> {
        let result = await BilibiliAccountService.shared.loadUserInfo(
            cookie: cookie,
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            referer: "https://www.bilibili.com"
        )

        switch result {
        case .success(let info):
            return .success(
                BilibiliUserInfo(
                    mid: info.mid,
                    uname: info.uname,
                    userid: info.userid,
                    sign: info.sign,
                    birthday: info.birthday,
                    sex: info.sex,
                    rank: info.rank,
                    face: info.face,
                    nickFree: info.nickFree
                )
            )
        case .failure(let error):
            switch error {
            case .emptyCookie:
                return .failure(.emptyCookie)
            case .invalidURL:
                return .failure(.invalidURL)
            case .cookieExpired(let message):
                return .failure(.cookieExpired(message: message))
            case .networkError(let message):
                let wrappedError = NSError(
                    domain: "BilibiliAccountService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
                return .failure(.networkError(wrappedError))
            case .decodingError(let message), .invalidResponse(let message):
                let wrappedError = NSError(
                    domain: "BilibiliAccountService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
                return .failure(.decodingError(wrappedError))
            }
        }
    }
}
