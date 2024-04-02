//
//  QRCodeStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI

enum QRCodeType {
    case bilibiliLogin
    case syncServer
}

class QRCodeStore: ObservableObject {
    @Published var qrcode_url = "" {
        didSet {
            generateQRCode()
        }
    }
    @Published var message = ""
    @Published var qrcode_key = ""
    @Published var qrCodeImage: UIImage?
    @Published var qrCodeType: QRCodeType? = .syncServer {
        didSet {
            if qrCodeType == .syncServer {
                message = "服务启动成功，请使用Simple Live手机版选中\(Common.hostName() ?? "")或扫描屏幕二维码\n或在客户端地址框内输入：\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
                qrcode_url = "\(Common.getWiFiIPAddress() ?? ""):\(httpPort)"
                syncManager = SyncManager()
                udpManager = UDPListener()
            }
        }
    }
    
    @Published var syncManager: SyncManager?
    @Published var udpManager: UDPListener?
    
    func generateQRCode() {
        qrCodeImage = Common.generateQRCode(from: qrcode_url)
    }
    
    deinit {
        syncManager?.closeServer()
        udpManager?.closeServer()
    }
    
}
