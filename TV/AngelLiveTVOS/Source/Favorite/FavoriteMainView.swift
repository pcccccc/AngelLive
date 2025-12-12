//
//  FavoriteMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct FavoriteMainView: View {
    
    @FocusState var focusState: Int?
    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(AppState.self) var appViewModel
    @Environment(\.scenePhase) var scenePhase
    @State var timer: Timer?
    @State var second = 0
    @State var firstLoad = true
    
    var body: some View {
        
        @Bindable var appModel = appViewModel
        
        VStack {
            if appViewModel.favoriteViewModel.cloudKitReady {
                if appViewModel.favoriteViewModel.groupedRoomList.isEmpty && appViewModel.favoriteViewModel.isLoading == false {
                    if appViewModel.favoriteViewModel.roomList.isEmpty {
                        if appViewModel.favoriteViewModel.cloudReturnError {
                            ErrorView(
                                title: "iCloud同步失败",
                                message: appViewModel.favoriteViewModel.cloudKitStateString,
                                showDismiss: false,
                                showRetry: true,
                                onDismiss: {},
                                onRetry: {
                                    getViewStateAndFavoriteList()
                                }
                            )
                        }else {
                            Text("暂无收藏")
                                .font(.title3)
                        }
                    }else {
                        Text(appViewModel.favoriteViewModel.cloudKitStateString)
                            .font(.title3)
                        Button {
                            getViewStateAndFavoriteList()
                        } label: {
                            Label("刷新", systemImage: "arrow.counterclockwise")
                                .font(.headline.bold())
                        }
                    }
                }else {
                    ScrollView(.vertical) {
                        // 按直播状态分组展示：正在直播用竖向列表，其他用横向列表
                        ForEach(appViewModel.favoriteViewModel.groupedRoomList, id: \.id) { section in
                            if section.title == "正在直播" {
                                // 正在直播 - 竖向网格布局
                                VStack(alignment: .leading, spacing: 20) {
                                    // Section Header
                                    FavoriteSectionHeader(title: section.title, count: section.roomList.count, isLive: true)
                                        .padding(.leading, 50)

                                    LazyVGrid(
                                        columns: [
                                            GridItem(.fixed(380), spacing: 50),
                                            GridItem(.fixed(380), spacing: 50),
                                            GridItem(.fixed(380), spacing: 50),
                                            GridItem(.fixed(380), spacing: 50)
                                        ],
                                        alignment: .center,
                                        spacing: 50
                                    ) {
                                        ForEach(section.roomList.indices, id: \.self) { index in
                                            LiveCardView(index: index, currentLiveModel: section.roomList[index])
                                                .environment(liveViewModel)
                                                .environment(appViewModel)
                                                .frame(width: 370, height: 280)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .padding(.bottom, 40)
                                .focusSection()
                            } else {
                                // 其他状态（已下播、回放/轮播、未知状态） - 横向滚动列表
                                VStack(alignment: .leading, spacing: 20) {
                                    // Section Header
                                    FavoriteSectionHeader(title: section.title, count: section.roomList.count, isLive: false)
                                        .padding(.leading, 50)

                                    ScrollView(.horizontal) {
                                        LazyHGrid(rows: [GridItem(.fixed(280), spacing: 50, alignment: .leading)], spacing: 50) {
                                            ForEach(section.roomList.indices, id: \.self) { index in
                                                LiveCardView(index: index, currentLiveModel: section.roomList[index])
                                                    .environment(liveViewModel)
                                                    .environment(appViewModel)
                                                    .frame(width: 370, height: 280)
                                            }
                                        }
                                        .safeAreaPadding([.leading, .trailing], 50)
                                        .padding(.vertical, 30) // 为焦点放大效果留出空间
                                    }
                                    .padding(.top, -30) // 抵消上方多余的 padding
                                }
                                .padding(.bottom, 20)
                                .focusSection()
                            }
                        }
                        if appViewModel.favoriteViewModel.isLoading {
                            HStack {
                                LoadingView()
                                    .frame(width: 370, height: 280)
                                    .cornerRadius(5)
                                    .shimmering(active: true)
                                    .redacted(reason: .placeholder)
                                Spacer()
                            }
                            .padding(.leading, 50)
                        }
                    }
                }
            }else {
                ErrorView(
                    title: "iCloud未就绪",
                    message: appViewModel.favoriteViewModel.cloudKitStateString,
                    showDismiss: false,
                    showRetry: true,
                    onDismiss: {},
                    onRetry: {
                        getViewStateAndFavoriteList()
                    }
                )
            }
        }
        .overlay {
            if appViewModel.favoriteViewModel.roomList.count > 0 && appViewModel.favoriteViewModel.cloudKitReady {
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
        .simpleToast(isPresented: $appModel.favoriteViewModel.showToast, options: appViewModel.favoriteViewModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: appModel.favoriteViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(appModel.favoriteViewModel.toastTitle)
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
                    
                    self.timer?.invalidate()
                    self.timer = nil
                    if second > 300 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                            getViewStateAndFavoriteList()
                        })
                    }
                case .background:
                    print("background。。。。")
                case .inactive:
                    print("inactive。。。。")
                    startTimer()
                @unknown default:
                    break
            }
        }
        .onAppear {
            if firstLoad {
                getViewStateAndFavoriteList()
                firstLoad = false
            }
            appViewModel.favoriteViewModel.refreshView()
            if appViewModel.favoriteViewModel.cloudKitReady == true && appViewModel.favoriteViewModel.roomList.count > 0 {
                liveViewModel.roomList = appViewModel.favoriteViewModel.roomList
            }
        }
    }
}


//MARK: Events
extension FavoriteMainView {
    private func getViewStateAndFavoriteList() {
        Task {
            guard appViewModel.favoriteViewModel.isLoading == false else { return }
            await appViewModel.favoriteViewModel.syncWithActor()
            liveViewModel.roomList = appViewModel.favoriteViewModel.roomList
            self.second = 0
            TopShelfManager.notifyContentChanged()
        }
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            second += 1
        }
        timer?.fire()
    }
}

// MARK: - Section Header
struct FavoriteSectionHeader: View {
    let title: String
    let count: Int
    let isLive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 颜色指示条
            RoundedRectangle(cornerRadius: 3)
                .fill(isLive ? Color.green : Color.gray)
                .frame(width: 6, height: 28)

            // 标题
            Text(title)
                .font(.title2.bold())

            // 数量标签
            Text("\(count)")
                .font(.system(size: 22, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                )

            Spacer()
        }
    }
}
