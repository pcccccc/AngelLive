//
//  QRCodeView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI
import SimpleToast

struct QRCodeView: View {
    
    @EnvironmentObject var qrCodeStore: QRCodeStore
    var refreshAction: (() -> Void)?
    
    var body: some View {
        VStack {
            if qrCodeStore.showFullScreenLoading == false {
                Spacer(minLength: 30)
                Button {
                    if refreshAction != nil {
                        refreshAction!()
                    }
                } label: {
                    HStack {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                Spacer(minLength: 30)
                if qrCodeStore.qrcode_url.count == 0 {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 500, height: 500)
                }else {
                    Image(uiImage: Common.generateQRCode(from: qrCodeStore.qrcode_url))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 500, height: 500)
                }
                Spacer(minLength: 30)
                Text(qrCodeStore.message)
                    .multilineTextAlignment(.center)
                Spacer()
            }else {
                FullScreenLoadingView(loadingText: $qrCodeStore.showFullScreenLoadingText)
            }
        }
        .frame(width: 1920, height: 1080)
        .onDisappear {
            qrCodeStore.closeServer()
        }
        .alert("提示", isPresented: $qrCodeStore.showAlert) {
            Button("确认", role: .destructive, action: {
                Task {
                    await qrCodeStore.beginSync()
                }
                qrCodeStore.showAlert.toggle()
            })
            Button("取消",role: .cancel) {
                qrCodeStore.showAlert.toggle()
            }
        } message: {
            Text("收到\(qrCodeStore.syncTypeString)请求，该请求\(qrCodeStore.needOverlay == true ? "将会" : "不会")覆盖您目前已有记录，是否继续。")
        }
        .simpleToast(isPresented: $qrCodeStore.showToast, options: qrCodeStore.toastOptions) {
            Label(qrCodeStore.toastTitle, systemImage: qrCodeStore.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                .padding()
                .background(qrCodeStore.toastTypeIsSuccess ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
}

#Preview {
    QRCodeView(refreshAction: {})
}
