//
//  QRCodeView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI
import SimpleToast

struct QRCodeView: View {
    
    @Environment(QRCodeViewModel.self) var qrCodeViewModel
    var refreshAction: (() -> Void)?

    var body: some View {
        
        @Bindable var qrCodeVM = qrCodeViewModel

        VStack {
            if qrCodeViewModel.showFullScreenLoading == false {
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
                if qrCodeViewModel.qrcode_url.count == 0 {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 500, height: 500)
                }else {
                    Image(uiImage: Common.generateQRCode(from: qrCodeViewModel.qrcode_url))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 500, height: 500)
                }
                Spacer(minLength: 30)
                Text(qrCodeViewModel.message)
                    .multilineTextAlignment(.center)
                Spacer()
            }else {
                FullScreenLoadingView(loadingText: $qrCodeVM.showFullScreenLoadingText)
            }
        }
        .frame(width: 1920, height: 1080)
        .onDisappear {
            qrCodeViewModel.closeServer()
        }
        .alert("提示", isPresented: $qrCodeVM.showAlert) {
            Button("确认", role: .destructive, action: {
                Task {
                    await qrCodeViewModel.beginSync()
                }
                qrCodeViewModel.showAlert.toggle()
            })
            Button("取消",role: .cancel) {
                qrCodeViewModel.showAlert.toggle()
            }
        } message: {
            Text("收到\(qrCodeViewModel.syncTypeString)请求，该请求\(qrCodeViewModel.needOverlay == true ? "将会" : "不会")覆盖您目前已有记录，是否继续。")
        }
        .simpleToast(isPresented: $qrCodeVM.showToast, options: qrCodeViewModel.toastOptions) {
            Label(qrCodeViewModel.toastTitle, systemImage: qrCodeViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                .padding()
                .background(qrCodeViewModel.toastTypeIsSuccess ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
}

#Preview {
    QRCodeView(refreshAction: {})
}
