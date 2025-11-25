//
//  QRCodeView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI
import AngelLiveDependencies

struct QRCodeView: View {
    
    @Environment(QRCodeViewModel.self) var qrCodeViewModel
    @Environment(AppState.self) var appViewModel
    var refreshAction: (() -> Void)?
    @State var qrcodeUrl = ""

    var body: some View {
        
        @Bindable var qrCodeVM = qrCodeViewModel

        VStack {
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
            if qrCodeVM.qrcodeUrl.count == 0 {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 500, height: 500)
            }else {
                Image(uiImage: Common.generateQRCode(from: qrCodeVM.qrcodeUrl))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 500, height: 500)
            }
            Spacer(minLength: 30)
            Text(qrCodeViewModel.currentState.0 == true ? "您已经收到同步请求，请确认" : qrCodeViewModel.message)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(width: 1920, height: 1080)
        .alert("提示", isPresented: $qrCodeVM.currentState.0) {
            Button("确认", role: .destructive, action: {
                qrCodeVM.currentState.0.toggle()
                Task {
                    await qrCodeViewModel.startSyncTask(appViewModel: appViewModel)
                    await qrCodeViewModel.resetSyncTaskState()
                }
            })
            Button("取消",role: .cancel) {
                qrCodeVM.currentState.0.toggle()
                Task {
                    await qrCodeViewModel.resetSyncTaskState()
                }
            }
        } message: {
            Text(qrCodeViewModel.currentState.1)
        }
    }
}

#Preview {
    QRCodeView(refreshAction: {})
}
