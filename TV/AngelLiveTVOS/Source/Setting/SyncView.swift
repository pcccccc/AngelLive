//
//  SyncView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/1.
//

import SwiftUI
import AngelLiveDependencies

struct SyncView: View {
    
    @Environment(AppState.self) var appViewModel
    @ObservedObject var playerCoordinator = KSVideoPlayer.Coordinator()
    var qrCodeStore = QRCodeViewModel()
    var playerOption = {
        let option = KSOptions()
        option.isLoopPlay = true
        return option
    }()

    
    var body: some View {
        
        @Bindable var qrCodeVM = qrCodeStore
        
        VStack {
            if qrCodeStore.fullScreenLoading {
                KSVideoPlayer(coordinator: _playerCoordinator, url: Bundle.main.url(forResource: "loading", withExtension: "mp4")!, options: playerOption)
                    .background(Color.black)
                    .onAppear {
                        playerCoordinator.playerLayer?.play()
                    }
                    .ignoresSafeArea()
                    .overlay {
                        VStack {
                            HStack {
                                Spacer()
                                HStack {
                                    VStack(alignment: .leading, spacing: 15) {
                                        Text(qrCodeStore.currentTaskState.description)
                                            .font(.title3)
                                        HStack {
                                            if qrCodeStore.favoriteSyncTaskStart {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text("主播：\(appViewModel.favoriteViewModel.syncProgressInfo.0)")
                                                        .lineLimit(1)
                                                    Text("平台：\(appViewModel.favoriteViewModel.syncProgressInfo.1)")
                                                }
                                                Spacer()
                                                Text(appViewModel.favoriteViewModel.syncProgressInfo.2)
                                                    .foregroundStyle(appViewModel.favoriteViewModel.syncProgressInfo.2 == "失败" ? Color.red : Color.green)
                                            }else {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(qrCodeStore.fullScreenSyncState)
                                                }
                                            }
                                        }
                                        if qrCodeStore.favoriteSyncTaskStart {
                                            ProgressView(value: Float(appViewModel.favoriteViewModel.syncProgressInfo.3) / Float(appViewModel.favoriteViewModel.syncProgressInfo.4), total: 1)
                                                .progressViewStyle(.linear)
                                        }else {
                                            ProgressView(value: qrCodeStore.progress, total: 1)
                                                .progressViewStyle(.linear)
                                        }
                                           
                                    }
                                    .frame(maxWidth: 450)
                                    .padding([.top, .bottom], 30)
                                    .padding([.leading, .trailing], 50)
                                }
                                .background(.thinMaterial)
                                .cornerRadius(10)
                                .padding([.top, .trailing], 30)
                            }
                            Spacer()
                        }
                        .frame(width: 1920, height: 1080)
                    }
            }else {
                VStack {
                    Spacer(minLength: 30)
                    QRCodeView()
                    .environment(qrCodeStore)
                    .environment(appViewModel)
                    Spacer()
                }
                .frame(width: 1920, height: 1080)
                .simpleToast(isPresented: $qrCodeVM.showToast, options: qrCodeVM.toastOptions) {
                    VStack(alignment: .leading) {
                        Label("提示", systemImage: qrCodeVM.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                            .font(.headline.bold())
                        Text(qrCodeVM.toastTitle)
                    }
                    .padding()
                    .background(.black.opacity(0.6))
                    .foregroundColor(Color.white)
                    .cornerRadius(10)
                }
            }
        }
        .task {
            await qrCodeStore.setupSyncServer()
        }
        .onDisappear {
            qrCodeStore.stopSyncServer()
        }
        
    }

}

#Preview {
    SyncView()
        .environment(AppState())
}
