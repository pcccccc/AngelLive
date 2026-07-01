//
//  String+Extension.swift
//  testparse
//
//  Created by pc on 2023/12/14.
//

import Foundation
import CryptoKit

extension String {
    var md5: String {
        // 保留 MD5 算法以兼容既有接口签名,改用 CryptoKit 的 Insecure.MD5 消除 CC_MD5 弃用警告。
        let digest = Insecure.MD5.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    static func stripHTML(from input: String) -> String {
        let pattern = "<[^>]+>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: input.utf16.count)
        return regex?.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "") ?? input
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
    func getUrlStringWithShareCode() -> String {
        let urlPattern = "(http|https)://[\\w-]+(\\.[\\w-]+)+([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?"
        do {
            let regex = try NSRegularExpression(pattern: urlPattern, options: [])
            let nsString = self as NSString
            let results = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
            let urls = results.map { nsString.substring(with: $0.range) }
            return urls.last ?? ""
        } catch {
            return ""
        }
    }
    
    public static func convertUnicodeEscapes(in string: String) -> String {
        let pattern = #"\\u([0-9A-Fa-f]{4})"#
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
            let mutableInput = NSMutableString(string: string)
            
            // 查找所有匹配项
            let matches = regex.matches(in: string, options: [], range: nsRange)
            
            // 从最后一个匹配项开始替换，以保持索引正确
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: string) {
                    let hexCode = String(string[range])
                    if let unicodeScalar = UnicodeScalar(UInt32(hexCode, radix: 16)!) {
                        let character = String(unicodeScalar)
                        mutableInput.replaceCharacters(in: match.range, with: character)
                    }
                }
            }
            return mutableInput as String
        } catch {
            return string
        }
    }
}
