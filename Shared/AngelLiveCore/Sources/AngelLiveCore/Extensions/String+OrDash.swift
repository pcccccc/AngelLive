//
//  String+OrDash.swift
//  AngelLiveCore
//
//  空字符串兜底显示 "-"，避免三端到处写 isEmpty 三目。
//

import Foundation

public extension String {
    /// 空字符串时返回 "-"；适用于直播标题、用户名等可能缺失的字段。
    var orDash: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : self
    }
}
