//
//  String+Extension.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/4.
//

import Foundation
import CryptoKit

extension String {
    var md5: String {
        // 保留 MD5 算法以兼容既有接口签名,改用 CryptoKit 的 Insecure.MD5 消除 CC_MD5 弃用警告。
        let digest = Insecure.MD5.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    static func generateRandomString(length: Int) -> String {
        var randomString = ""
        for _ in 0..<length {
            let randomNumber = Int(arc4random_uniform(16))
            let hexString = String(format: "%X", randomNumber)
            randomString += hexString
        }
        return randomString
    }
    
    static func stripHTML(from input: String) -> String {
        guard let data = input.data(using: .utf8) else {
            return input
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        } else {
            return input
        }
    }
    
    func formatWatchedCount() -> String {
        let isNumeric = self.allSatisfy { $0.isNumber }
        if isNumeric {
            let count = Double(self) ?? 0.0
            if count > 10000 {
                return String(format: "%.1f万", count / 10000)
            }else {
                return self
            }
        }else {
            return self
        }
    }
}
