//
//  Common.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/14.
//

import Foundation
import CoreImage.CIFilterBuiltins
import UIKit
import AngelLiveDependencies

struct SimpleLiveNotificationNames {
    static let playerEndPlay = Notification.Name("SimpleLive.Player.End.Play")
    static let favoriteRefresh = Notification.Name("SimpleLive.Favorite.Refresh")
    static let navigateToSettings = Notification.Name("SimpleLive.Navigate.ToSettings")
}

class Common {
    
    /**
     字典转换成Data
     
     - Parameters: jsonDic
     
     - Returns: Data or Nil
     */
    public class func jsonToData(jsonDic:Dictionary<String, Any>) -> Data? {
        if (!JSONSerialization.isValidJSONObject(jsonDic)) {
            
            print("is not a valid json object")
            
            return nil
        }
        //利用自带的json库转换成Data
        //如果设置options为JSONSerialization.WritingOptions.prettyPrinted，则打印格式更好阅读
        let data = try? JSONSerialization.data(withJSONObject: jsonDic, options: [])
        //Data转换成String打印输出
        let str = String(data:data!, encoding: String.Encoding.utf8)
        //输出json字符串
        print("Json Str:\(str!)")
        return data
    }
    
    
    /**
     生成二维码
     
     - Parameters: String
     
     - Returns: 二维码图片
     */
    public class func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        if let outputImage = filter.outputImage?.transformed(by: transform) {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    
    public class func getWiFiIPAddress() -> String? {
        var address: String?
        // Get list of all interfaces on the local machine:
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {

                // Check if interface is en0 which is the Wi-Fi connection on the iPhone
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)

        return address
    }

    public class func hostName() -> String? {
        let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXHOSTNAMELEN))
        let ret = gethostname(ptr, Int(MAXHOSTNAMELEN))
        var name: String?
        if ret == 0 {
            name = String(cString: ptr)
        }
        ptr.deallocate()
        return name
    }

    class func getImage(_ liveType: LiveType) -> String {
        switch liveType {
            case .bilibili:
                return "live_card_bili"
            case .douyu:
                return "live_card_douyu"
            case .huya:
                return "live_card_huya"
            case .douyin:
                return "live_card_douyin"
            case .yy:
                return "live_card_yy"
            case .cc:
                return "live_card_cc"
            case .ks:
                return "live_card_ks"
            case .soop:
                return "live_card_soop"
        }
    }
}
