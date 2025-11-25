//
//  Data+Extension.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/23.
//

import Foundation
import zlib

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
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var decompressedData = Data()
        
        let source = UnsafeMutablePointer<Bytef>(mutating: (data as NSData).bytes.bindMemory(to: Bytef.self, capacity: data.count))
        let destination = UnsafeMutablePointer<Bytef>(mutating: &buffer)
        
        var zStream = z_stream()
        zStream.next_in = source
        zStream.avail_in = UInt32(data.count)
        zStream.next_out = destination
        zStream.avail_out = UInt32(bufferSize)
        
        let result = inflateInit2_(&zStream, MAX_WBITS + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if result != Z_OK {
            return nil
        }
        
        while true {
            let inflateResult = inflate(&zStream, Z_SYNC_FLUSH)
            if inflateResult == Z_STREAM_END {
                break
            }
            
            if inflateResult != Z_OK {
                inflateEnd(&zStream)
                return nil
            }
            
            if zStream.avail_out == 0 {
                decompressedData.append(buffer, count: bufferSize)
                zStream.next_out = destination
                zStream.avail_out = UInt32(bufferSize)
            }
        }
        
        inflateEnd(&zStream)
        
        if zStream.avail_out < bufferSize {
            decompressedData.append(buffer, count: bufferSize - Int(zStream.avail_out))
        }
        
        return decompressedData
    }

}


 
