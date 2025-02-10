//
//  FavoriteMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse
import Shimmer
import TipKit

struct FavoriteMainView: View {
    
    @FocusState var focusState: Int?
    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(SimpleLiveViewModel.self) var appViewModel
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        
        @Bindable var appModel = appViewModel
        
        VStack {
            if appViewModel.appFavoriteModel.cloudKitReady {
                if appViewModel.appFavoriteModel.roomList.isEmpty && appViewModel.appFavoriteModel.isLoading == false {
                    Text(appViewModel.appFavoriteModel.cloudKitStateString)
                        .font(.title3)
                    Button {
                        getViewStateAndFavoriteList()
                    } label: {
                        Label("刷新", systemImage: "arrow.counterclockwise")
                            .font(.headline.bold())
                    }
                }else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60)], spacing: 60) {
                            ForEach(appViewModel.appFavoriteModel.roomList.indices, id: \.self) { index in
                                LiveCardView(index: index)
                                    .environment(liveViewModel)
                                    .environment(appViewModel)
                                    .frame(width: 370, height: 240)
                            }
                            if appViewModel.appFavoriteModel.isLoading {
                                LoadingView()
                                    .frame(width: 370, height: 275)
                                    .cornerRadius(5)
                                    .shimmering(active: true)
                                    .redacted(reason: .placeholder)
                            }
                        }
                        .safeAreaPadding(.top, 15)
                    }
                }
            }else {
                Text(appViewModel.appFavoriteModel.cloudKitStateString)
                    .font(.title3)
                Button {
                    getViewStateAndFavoriteList()
                } label: {
                    Label("刷新", systemImage: "arrow.counterclockwise")
                        .font(.headline.bold())
                }
            }
        }
        .overlay {
            if liveViewModel.roomList.count > 0 {
                VStack {
                    Spacer()
                    HStack {
                        ZStack {
                            HStack(spacing: 10) {
                                Image(systemName: "playpause.circle")
                                Text("刷新")
                            }
                            .frame(width: 190, height: 60)
                            .background(Color("hintBackgroundColor", bundle: .main).opacity(0.4))
                            .font(.callout.bold())
                            .cornerRadius(8)
                        }
                        .frame(width: 200, height: 100)
                        Spacer()
                    }
                }
            }
        }
        .simpleToast(isPresented: $appModel.appFavoriteModel.showToast, options: appViewModel.appFavoriteModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: appModel.appFavoriteModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(appModel.appFavoriteModel.toastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(Color.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            getViewStateAndFavoriteList()
        })
        .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.favoriteRefresh)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                getViewStateAndFavoriteList()
            })
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            switch newValue {
                case .active:
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                    getViewStateAndFavoriteList()
                })
                case .background:
                    print("background。。。。")
                case .inactive:
                    print("inactive。。。。")
                @unknown default:
                    break
            }
        }
    }
    
    func getViewStateAndFavoriteList() {
        Task {
            await appViewModel.appFavoriteModel.syncWithActor()
            liveViewModel.roomList = appViewModel.appFavoriteModel.roomList
        }
    }
}
