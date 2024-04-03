//
//  SyncView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/1.
//

import SwiftUI


struct SyncView: View {
    
    @EnvironmentObject var favoriteStore: FavoriteStore
    @StateObject var qrCodeStore = QRCodeStore()
    
    var body: some View {
        VStack {
            Spacer(minLength: 30)
            QRCodeView()
            .environmentObject(qrCodeStore)
            Spacer()
        }
        .frame(width: 1920, height: 1080)
        .onAppear {
            startQRService()
        }
    }
    
    @MainActor func startQRService() {
        qrCodeStore.qrCodeType = .syncServer
        qrCodeStore.favoriteStore = favoriteStore
    }
}

#Preview {
    SyncView()
}
