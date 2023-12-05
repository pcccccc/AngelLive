//
//  String+Extension.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/4.
//

import Foundation
import CommonCrypto

extension String {
    var md5: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
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
}
