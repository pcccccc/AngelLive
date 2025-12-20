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
    case leftEdge(Int)
}

struct ListMainView: View {

    @Environment(\.scenePhase) var scenePhase
    @State var needFullScreenLoading: Bool = false
    @State private var hasSetInitialFocus: Bool = false
    @State private var showEmptyState: Bool = false
    @State private var pendingEmptyState: DispatchWorkItem?
    @State private var allowSidebarFromLeftEdge: Bool = false
    private static let topId = "topIdHere"
    private let gridColumnCount = 4
    private let gridSpacing: CGFloat = 50
    private let cardWidth: CGFloat = 380
    private let cardHeight: CGFloat = 280
    private let leftEdgeColumnWidth: CGFloat = 60
    private let emptyStateDelay: TimeInterval = 0.35
    private let headerToGridSpacing: CGFloat = 24
    private var leftEdgeCompensation: CGFloat {
        // 额外一列会让网格整体右移，补偿半列宽度让卡片回到居中
        (leftEdgeColumnWidth + gridSpacing) / 2
    }

    var liveType: LiveType
    var liveViewModel: LiveViewModel
    @FocusState var focusState: FocusableField?
    var appViewModel: AppState
    
    init(liveType: LiveType, appViewModel: AppState) {
        self.liveType = liveType
        self.appViewModel = appViewModel
        self.liveViewModel = LiveViewModel(roomListType: .live, liveType: liveType, appViewModel: appViewModel)
    }

    private enum RoomGridItem: Hashable {
        case leftEdge(Int)
        case room(Int)
        case loading(Int)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.fixed(leftEdgeColumnWidth), spacing: gridSpacing),
            GridItem(.fixed(cardWidth), spacing: gridSpacing),
            GridItem(.fixed(cardWidth), spacing: gridSpacing),
            GridItem(.fixed(cardWidth), spacing: gridSpacing),
            GridItem(.fixed(cardWidth), spacing: gridSpacing)
        ]
    }

    private var roomGridItems: [RoomGridItem] {
        let roomCount = liveViewModel.roomList.count
        let rowCount = (roomCount + gridColumnCount - 1) / gridColumnCount
        var items: [RoomGridItem] = []
        items.reserveCapacity(max(1, rowCount) * (gridColumnCount + 1))

        for row in 0..<rowCount {
            items.append(.leftEdge(row))
            let start = row * gridColumnCount
            let end = min(start + gridColumnCount, roomCount)
            for index in start..<end {
                items.append(.room(index))
            }
        }

        if shouldShowLoadingPlaceholder {
            // 补一行：哨兵 + Loading 卡片，避免落到哨兵列上
            let loadingRow = rowCount
            items.append(.leftEdge(loadingRow))
            items.append(.loading(loadingRow))
        }

        return items
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        print("ListMainView handleMoveCommand direction=\(direction) focus=\(String(describing: focusState)) selectedIndex=\(liveViewModel.selectedRoomListIndex)")
        switch focusState {
        case .mainContent:
            // 左侧展开由“哨兵焦点”触发，避免 onMoveCommand 在大列表下不稳定
            break
        case .leftMenu, .leftFavorite:
            if direction == .right {
                liveViewModel.isSidebarExpanded = false
                focusState = .mainContent(max(0, liveViewModel.selectedRoomListIndex))
            }
        default:
            break
        }
    }

    private func leftEdgeSentinel(row: Int) -> some View {
        Button(action: {}) {
            // 透明但可聚焦：仅用于从第一列“再向左”时接管焦点
            Rectangle()
                .fill(Color.clear)
        }
        .frame(width: leftEdgeColumnWidth, height: cardHeight)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .focused($focusState, equals: .leftEdge(row))
        .opacity(0.001)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func roomGridItemView(_ item: RoomGridItem, reader: ScrollViewProxy) -> some View {
        switch item {
        case .leftEdge(let row):
            leftEdgeSentinel(row: row)
        case .room(let index):
            LiveCardView(index: index, externalFocusState: $focusState, onMoveCommand: handleMoveCommand)
                .environment(liveViewModel)
                .onPlayPauseCommand(perform: {
                    liveViewModel.roomPage = 1
                    liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
                    reader.scrollTo(Self.topId)
                })
                .frame(width: 370, height: cardHeight)
        case .loading:
            LoadingView()
                .frame(width: 370, height: cardHeight)
                .cornerRadius(5)
                .shimmering(active: true)
                .redacted(reason: .placeholder)
        }
    }

    private var platformTitleView: some View {
        Text(liveViewModel.livePlatformName)
            .font(.largeTitle)
            .bold()
    }

    private var shouldShowLoadingPlaceholder: Bool {
        liveViewModel.isLoading || (liveViewModel.roomList.isEmpty && !showEmptyState)
    }

    private func updateEmptyState() {
        pendingEmptyState?.cancel()
        pendingEmptyState = nil

        if liveViewModel.isLoading {
            showEmptyState = false
            return
        }

        if liveViewModel.roomList.isEmpty {
            let workItem = DispatchWorkItem {
                showEmptyState = true
            }
            pendingEmptyState = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + emptyStateDelay, execute: workItem)
        } else {
            showEmptyState = false
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("暂无房间")
                .font(.title2.bold())
            Text("请稍后重试或切换分类")
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var roomListView: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: headerToGridSpacing) {
                    platformTitleView
                        .id(Self.topId)
                        .frame(maxWidth: .infinity, alignment: .center)
                    LazyVGrid(
                        columns: gridColumns,
                        alignment: .center,
                        spacing: gridSpacing
                    ) {
                        ForEach(roomGridItems, id: \.self) { item in
                            roomGridItemView(item, reader: reader)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    // 只偏移网格，避免标题跟着偏移
                    .offset(x: -leftEdgeCompensation)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var listContainerView: some View {
        ZStack(alignment: .leading) {
            Group {
            if shouldShowLoadingPlaceholder {
                // roomList 为空时先展示加载态，避免“空列表一闪而过”
                roomListView
            } else if liveViewModel.roomList.isEmpty && showEmptyState {
                // 已提示错误则不会走到这里，空态只在无错误且无加载时展示
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 主内容区域
                    roomListView
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
            if liveViewModel.roomList.count > 0 || liveViewModel.categories.count > 0 {
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

    private func errorView(_ error: Error) -> some View {
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
    }

    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        ZStack {
            if liveViewModel.hasError, let error = liveViewModel.currentError {
                errorView(error)
            } else {
                listContainerView
            }
        }
        .background(.thinMaterial)
        .onChange(of: focusState) { _, newValue in
            // 当焦点移到主内容时，关闭 sidebar
            switch newValue {
            case .mainContent:
                allowSidebarFromLeftEdge = true
                if liveViewModel.isSidebarExpanded {
                    liveViewModel.isSidebarExpanded = false
                }
            case .leftEdge:
                // 左侧哨兵获取焦点 -> 展开 sidebar 并把焦点转交
                guard allowSidebarFromLeftEdge else { return }
                liveViewModel.isSidebarExpanded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusState = .leftMenu(0, 0)
                }
            default:
                break
            }
        }
        .onChange(of: liveViewModel.roomList) { _, newValue in
            updateEmptyState()
            if newValue.isEmpty {
                allowSidebarFromLeftEdge = false
            }
            // 当 roomList 首次加载完成时，设置初始焦点到主内容
            if !hasSetInitialFocus && !newValue.isEmpty {
                hasSetInitialFocus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    focusState = .mainContent(0)
                }
            }
        }
        .onChange(of: liveViewModel.isLoading) { _, _ in
            updateEmptyState()
        }
        .onAppear {
            allowSidebarFromLeftEdge = false
            updateEmptyState()
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
