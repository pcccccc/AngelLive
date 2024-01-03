//
//  BilibiliLoginView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/21.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import LiveParse

struct BilibiliLoginView: View {
    
    @State private var qrcode_url = ""
    @State private var message = "请打开哔哩哔哩APP扫描二维码"
    @State private var qrcode_key = ""
    @State private var timer: Timer?
    
    
    var body: some View {
        VStack {
            Spacer(minLength: 30)
            Button {
                Task {
                    message = "请打开哔哩哔哩APP扫描二维码"
                    await getQRCode()
                }
            } label: {
                HStack {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            Spacer(minLength: 30)
            if qrcode_url.count == 0 {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 500, height: 500)
            }else {
                Image(uiImage: generateQRCode(from: qrcode_url))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 500, height: 500)
            }
            Spacer(minLength: 30)
            Text(message)
            Spacer()
        }
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
                qrcode_key = dataReq.data.qrcode_key!
                qrcode_url = dataReq.data.url ?? ""
                timer?.fire()
            }else {
                message = dataReq.message
            }
        }catch {
            print(error)
        }
    }
    
    func getQRCodeScanState() async {
        
        Task {
            do {
                let dataReq = try await Bilibili.getQRCodeState(qrcode_key: qrcode_key)
                if message == "授权成功，请退出页面" {
                    return;
                } 
                if dataReq.data.code == 86090 {
                    message = "扫描成功，请操作手机进行授权"
                }else if dataReq.data.code == 86038 {
                    message = "二维码已经过期，请刷新再试"
                
                }else if dataReq.data.code == 0 {
                    message = "授权成功，请退出页面"
                    timer?.invalidate()
                }else if dataReq.data.code == 86101 {
                    message = "请打开哔哩哔哩APP扫描二维码:等待扫码"
                }
            }catch {
                timer?.invalidate()
            }
        }
    }
    
    func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        let transform = CGAffineTransform(scaleX: 3, y: 3)
        if let outputImage = filter.outputImage?.transformed(by: transform) {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }

}

#Preview {
    BilibiliLoginView()
}
