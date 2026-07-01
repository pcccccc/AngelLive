//
//  Data+Extension.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/23.
//

import Foundation
import AngelLiveDependencies

extension Data {
    func _4BytesToInt() -> Int {
        var value: UInt32 = 0
        let data = NSData(bytes: [UInt8](self), length: self.count)
        data.getBytes(&value, length: self.count) // 把data以字节方式拷贝给value？
        value = UInt32(bigEndian: value)
        return Int(value)
    }
    
    func _2BytesToInt() -> Int {
        var value: UInt16 = 0
        let data = NSData(bytes: [UInt8](self), length: self.count)
        data.getBytes(&value, length: self.count) // 把data以字节方式拷贝给value？
        value = UInt16(bigEndian: value)
        return Int(value)
    }
    
    static func decompressGzipData(data: Data) -> Data? {
        // 改用 GzipSwift(经 AngelLiveDependencies 转出)解压,替代手写 zlib 里
        // 用 &buffer / 临时 NSData 取指针导致的悬垂指针写法。
        return try? data.gunzipped()
    }

}


 
