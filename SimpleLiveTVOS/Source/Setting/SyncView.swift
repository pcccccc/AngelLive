//
//  SyncView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/1.
//

import SwiftUI
import KSPlayer


struct SyncView: View {
    
    @Environment(SimpleLiveViewModel.self) var appViewModel
    @StateObject var qrCodeStore = QRCodeStore()
    
    var body: some View {
        VStack {
            Spacer(minLength: 30)
            QRCodeView()
            .environmentObject(qrCodeStore)
//            KSVideoPlayer(coordinator: qrCodeStore.playerCoordinator, url: Bundle.main.url(forResource: "loading", withExtension: "mp4")!, options: .init())
//                .background(Color.black)
//                .onAppear {
//                    qrCodeStore.playerLayer?.play()
//                }
//                .ignoresSafeArea()
//                .zIndex(1)
            Spacer()
        }
        .frame(width: 1920, height: 1080)
        .onAppear {
            startQRService()
        }
    }
    
    @MainActor func startQRService() {
        qrCodeStore.qrCodeType = .syncServer
        qrCodeStore.favoriteModel = appViewModel.appFavoriteModel
    }
}

#Preview {
    SyncView()
        .environment(SimpleLiveViewModel())
}
