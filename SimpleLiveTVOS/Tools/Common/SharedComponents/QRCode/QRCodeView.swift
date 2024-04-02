//
//  QRCodeView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/2.
//

import SwiftUI

struct QRCodeView: View {
    
    @EnvironmentObject var qrCodeStore: QRCodeStore
    var refreshAction: (() -> Void)?
    
    var body: some View {
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
        }
        .frame(width: 1920, height: 1080)
    }
}

#Preview {
    QRCodeView(refreshAction: {})
}
