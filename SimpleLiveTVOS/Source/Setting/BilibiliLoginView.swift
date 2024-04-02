//
//  BilibiliLoginView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/21.
//

import SwiftUI
import LiveParse

struct BilibiliLoginView: View {
    
    @State private var qrcode_url = ""
    @State private var message = "请打开哔哩哔哩APP扫描二维码"
    @State private var qrcode_key = ""
    @State private var timer: Timer?
    @EnvironmentObject var settingStore: SettingStore
    @StateObject var qrCodeStore = QRCodeStore()
    
    
    var body: some View {
        VStack {
            Spacer(minLength: 30)
            QRCodeView {
                Task {
                    qrCodeStore.message = "请打开哔哩哔哩APP扫描二维码"
                    await getQRCode()
                }
            }
            .environmentObject(qrCodeStore)
            Spacer()
        }
        .frame(width: 1920, height: 1080)
        .task {
            await getQRCode()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task {
                    await self.getQRCodeScanState()
                }
            }
        }
        .onDisappear {
        }
    }
    
    func getQRCode() async {
        do {
            let dataReq = try await Bilibili.getQRCodeUrl()
            if dataReq.code == 0 {
                qrCodeStore.qrcode_key = dataReq.data.qrcode_key!
                qrCodeStore.qrcode_url = dataReq.data.url ?? ""
                timer?.fire()
            }else {
                qrCodeStore.message = dataReq.message
            }
        }catch {
            print(error)
        }
    }
    
    func getQRCodeScanState() async {
        Task {
            do {
                let dataReq = try await Bilibili.getQRCodeState(qrcode_key: qrCodeStore.qrcode_key)
                if qrCodeStore.message == "授权成功，请退出页面" {
                    return;
                } 
                if dataReq.0.data.code == 86090 {
                    qrCodeStore.message = "扫描成功，请操作手机进行授权"
                }else if dataReq.0.data.code == 86038 {
                    qrCodeStore.message = "二维码已经过期，请刷新再试"
                }else if dataReq.0.data.code == 0 {
                    qrCodeStore.message = "授权成功，请退出页面"
                    settingStore.bilibiliCookie = dataReq.1
                    timer?.invalidate()
                }else if dataReq.0.data.code == 86101 {
                    qrCodeStore.message = "请打开哔哩哔哩APP扫描二维码:等待扫码"
                }
            }catch {
                timer?.invalidate()
            }
        }
    }
}

#Preview {
    BilibiliLoginView()
}
