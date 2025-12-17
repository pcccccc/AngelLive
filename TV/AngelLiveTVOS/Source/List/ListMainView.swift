////
////  BiliBiliMainView.swift
////  SimpleLiveTVOS
////
////  Created by pangchong on 2023/9/14.
////

import SwiftUI
import GameController
import AngelLiveDependencies

enum FocusableField: Hashable {
    case leftMenu(Int, Int)
    case mainContent(Int)
    case leftFavorite(Int, Int)
}

struct ListMainView: View {

    @Environment(\.scenePhase) var scenePhase
    @State var needFullScreenLoading: Bool = false
    @State private var hasSetInitialFocus: Bool = false
    private static let topId = "topIdHere"

    var liveType: LiveType
    var liveViewModel: LiveViewModel
    @FocusState var focusState: FocusableField?
    var appViewModel: AppState
    
    init(liveType: LiveType, appViewModel: AppState) {
        self.liveType = liveType
        self.appViewModel = appViewModel
        self.liveViewModel = LiveViewModel(roomListType: .live, liveType: liveType, appViewModel: appViewModel)
    }
    
    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        ZStack {
            if liveViewModel.hasError, let error = liveViewModel.currentError {
                ErrorView(
                    title: error.isBilibiliAuthRequired ? "加载失败-请登录B站账号并检查官方页面" : "加载失败",
                    message: error.liveParseMessage,
                    detailMessage: error.liveParseDetail,
                    curlCommand: error.liveParseCurl,
                    showRetry: true,
                    showLoginButton: error.isBilibiliAuthRequired,
                    onDismiss: {
                        liveViewModel.hasError = false
                        liveViewModel.currentError = nil
                    },
                    onRetry: {
                        liveViewModel.hasError = false
                        liveViewModel.currentError = nil
                        liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
                    }
                )
            } else {
                ZStack(alignment: .leading) {
                    // 主内容区域
                    ScrollViewReader { reader in
                        ScrollView {
                            ZStack {
                                Text(liveModel.livePlatformName)
                                    .font(.largeTitle)
                                    .bold()
                            }
                            .id(Self.topId)
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
                                ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                                    LiveCardView(index: index, externalFocusState: $focusState, onLeftEdgeMove: {
                                        // 第一列向左 -> 展开 sidebar
                                        liveViewModel.isSidebarExpanded = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            focusState = .leftMenu(0, 0)
                                        }
                                    })
                                        .environment(liveViewModel)
                                        .onPlayPauseCommand(perform: {
                                            liveViewModel.roomPage = 1
                                            liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
                                            reader.scrollTo(Self.topId)
                                        })
                                        .frame(width: 370, height: 280)
                                }
                                if liveViewModel.isLoading {
                                    LoadingView()
                                        .frame(width: 370, height: 280)
                                        .cornerRadius(5)
                                        .shimmering(active: true)
                                        .redacted(reason: .placeholder)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .blur(radius: liveViewModel.isSidebarExpanded ? 5 : 0)
                    .animation(.easeInOut(duration: 0.25), value: liveViewModel.isSidebarExpanded)
                    
                    // 遮罩层
                    if liveViewModel.isSidebarExpanded {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                liveViewModel.isSidebarExpanded = false
                                focusState = .mainContent(liveViewModel.selectedRoomListIndex)
                            }
                            .transition(.opacity)
                    }
                    
                    // Sidebar
                    if liveModel.roomList.count > 0 || liveModel.categories.count > 0 {
                        SidebarView(focusState: $focusState)
                            .environment(liveViewModel)
                            .zIndex(2)
                            .onMoveCommand { direction in
                                if direction == .right {
                                    liveViewModel.isSidebarExpanded = false
                                    focusState = .mainContent(max(0, liveViewModel.selectedRoomListIndex))
                                }
                            }
                    }
                }
            }
        }
        .background(.thinMaterial)
        .onChange(of: focusState) { _, newValue in
            // 当焦点移到主内容时，关闭 sidebar
            if case .mainContent(_) = newValue, liveViewModel.isSidebarExpanded {
                liveViewModel.isSidebarExpanded = false
            }
        }
        .onChange(of: liveViewModel.roomList) { _, newValue in
            // 当 roomList 首次加载完成时，设置初始焦点到主内容
            if !hasSetInitialFocus && !newValue.isEmpty {
                hasSetInitialFocus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    focusState = .mainContent(0)
                }
            }
        }
        .simpleToast(isPresented: $liveModel.showToast, options: liveModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: liveModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(liveModel.toastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(Color.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            guard liveViewModel.isLoading == true else { return }
            liveViewModel.getRoomList(index: 1)
        })
        .onChange(of: scenePhase) { oldValue, newValue in
            switch newValue {
                case .active:
                    liveViewModel.showToast(true, title: "程序返回前台，正在为您刷新列表", hideAfter: 3)
                    liveViewModel.roomPage = 1
                case .background:
                    print("background。。。。")
                case .inactive:
                    print("inactive。。。。")
                @unknown default:
                    break
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
    }
}
