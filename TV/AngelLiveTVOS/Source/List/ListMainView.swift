import SwiftUI
import GameController
import AngelLiveDependencies
import AngelLiveCore
#if DEBUG
import os
#endif

enum FocusableField: Hashable {
    case leftMenu(Int, Int)
    case mainContent(Int)
    case leftFavorite(Int, Int)
    case platformInfo
    case emptyContent
}

struct ListMainView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) var scenePhase
    @State var needFullScreenLoading: Bool = false
    @State private var hasSetInitialFocus: Bool = false
    @State private var pendingCategoryFocus = false
    @State private var pendingSidebarFocus: FocusableField?
    @State private var showEmptyState: Bool = false
    @State private var pendingEmptyState: DispatchWorkItem?
    @State private var showCapabilitySheet: Bool = false
    @State private var hasStartedInitialLoad = false
    private static let topId = "topIdHere"
    #if DEBUG
    private static let navigationLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "AngelLiveTVOS",
        category: "RoomListNavigation"
    )
    #endif
    private let gridColumnCount = 4
    private let gridSpacing: CGFloat = 50
    private let cardWidth: CGFloat = 380
    private let cardHeight: CGFloat = 280
    private let emptyStateDelay: TimeInterval = 0.35
    private let headerToGridSpacing: CGFloat = 24

    var liveType: LiveType
    @State private var liveViewModel: LiveViewModel
    @FocusState var focusState: FocusableField?
    var appViewModel: AppState
    
    init(liveType: LiveType, appViewModel: AppState) {
        self.liveType = liveType
        self.appViewModel = appViewModel
        _liveViewModel = State(
            initialValue: LiveViewModel(
                roomListType: .live,
                liveType: liveType,
                appViewModel: appViewModel,
                shouldLoadData: false
            )
        )
    }

    private enum RoomGridItem: Hashable {
        case room(Int)
        case loading(Int)
    }

    private var gridColumns: [GridItem] {
        [
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
        items.reserveCapacity(max(1, rowCount) * gridColumnCount)

        for row in 0..<rowCount {
            let start = row * gridColumnCount
            let end = min(start + gridColumnCount, roomCount)
            for index in start..<end {
                items.append(.room(index))
            }
        }

        if shouldShowLoadingPlaceholder {
            // 补一行 Loading 卡片
            let loadingRow = rowCount
            items.append(.loading(loadingRow))
        }

        return items
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection, from cardIndex: Int? = nil) {
        logNavigation("move direction=\(direction) cardIndex=\(String(describing: cardIndex)) selectedIndex=\(liveViewModel.selectedRoomListIndex)")
        cancelPendingFocus()

        switch focusState {
        case .leftMenu, .leftFavorite:
            if direction == .right {
                closeSidebar()
            }
        case .mainContent(let focusedIndex):
            let index = cardIndex ?? focusedIndex
            if direction == .left && index >= 0 && index % gridColumnCount == 0 {
                openSidebar()
            }
        case .emptyContent, .platformInfo:
            if direction == .left {
                openSidebar()
            }
        default:
            break
        }
    }

    @ViewBuilder
    private func roomGridItemView(_ item: RoomGridItem, reader: ScrollViewProxy) -> some View {
        switch item {
        case .room(let index):
            LiveCardView(
                index: index,
                externalFocusState: $focusState,
                onMoveCommand: { direction in
                    handleMoveCommand(direction, from: index)
                }
            )
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
        HStack {
            Spacer()
            Text(liveViewModel.livePlatformName)
                .font(.largeTitle)
                .bold()
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button {
                showCapabilitySheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 80)
            .focused($focusState, equals: .platformInfo)
            .onMoveCommand { direction in
                handleMoveCommand(direction)
            }
        }
    }

    private var shouldShowLoadingPlaceholder: Bool {
        (liveViewModel.isLoading || (liveViewModel.roomList.isEmpty && !showEmptyState)) && liveViewModel.hasMoreRooms
    }

    private var sidebarOwnsFocus: Bool {
        switch focusState {
        case .leftMenu, .leftFavorite:
            return true
        default:
            return false
        }
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

    private func openSidebar() {
        guard !liveViewModel.isSidebarExpanded, !liveViewModel.categories.isEmpty else { return }
        logNavigation("openSidebar")
        cancelPendingFocus()
        liveViewModel.isSidebarExpanded = true
    }

    private func selectCategory(parentIndex: Int, subIndex: Int) {
        guard liveViewModel.selectCategory(parentIndex: parentIndex, subIndex: subIndex) else { return }

        cancelPendingFocus()
        pendingCategoryFocus = true
        closeSidebar(restoreContentFocus: false)
    }

    private func cancelPendingFocus() {
        pendingCategoryFocus = false
        pendingSidebarFocus = nil
        hasSetInitialFocus = true
    }

    private var focusAfterSidebarClose: FocusableField {
        guard !liveViewModel.roomList.isEmpty else {
            return showEmptyState && !liveViewModel.isLoading ? .emptyContent : .platformInfo
        }
        let selectedIndex = liveViewModel.selectedRoomListIndex
        let validIndex = liveViewModel.roomList.indices.contains(selectedIndex) ? selectedIndex : 0
        return .mainContent(validIndex)
    }

    private func closeSidebar(restoreContentFocus: Bool = true) {
        logNavigation("closeSidebar target=\(focusAfterSidebarClose)")
        pendingSidebarFocus = restoreContentFocus ? focusAfterSidebarClose : nil
        liveViewModel.isSidebarExpanded = false
    }

    private func handleBackCommand() {
        cancelPendingFocus()
        if liveViewModel.isSidebarExpanded {
            closeSidebar()
        } else {
            logNavigation("dismissList")
            dismiss()
        }
    }

    private func logNavigation(_ event: String) {
        let message = "RoomListNavigation \(event) model=\(ObjectIdentifier(liveViewModel)) focus=\(String(describing: focusState)) expanded=\(liveViewModel.isSidebarExpanded) loading=\(liveViewModel.isLoading) pendingCategory=\(pendingCategoryFocus)"
        Logger.debug(message, category: .ui)
        #if DEBUG
        // 保留非调试器启动后的返回记录，避免设备会话结束时丢失现场。
        os_log("%{public}@", log: Self.navigationLog, type: .default, message)
        #endif
    }

    private var pendingFocusTarget: FocusableField? {
        guard !liveViewModel.isLoading,
              !liveViewModel.hasError,
              !liveViewModel.isSidebarExpanded else {
            return nil
        }

        if pendingCategoryFocus {
            if liveViewModel.roomList.isEmpty {
                return showEmptyState ? .emptyContent : nil
            }
            return .mainContent(0)
        }

        guard !hasSetInitialFocus else { return nil }
        if !liveViewModel.roomList.isEmpty {
            return .mainContent(0)
        }
        return showEmptyState ? .emptyContent : nil
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("暂无房间")
                .font(.title2.bold())
            Text("请稍后重试或切换分类")
                .foregroundStyle(.secondary)
        }
        .padding()
        .focusable()
        .focusEffectDisabled()
        .focused($focusState, equals: .emptyContent)
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
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

                    if !liveViewModel.hasMoreRooms && !liveViewModel.roomList.isEmpty {
                        Text("已经到底了")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var listContainerView: some View {
        ZStack(alignment: .leading) {
            Group {
                if liveViewModel.roomList.isEmpty && showEmptyState && !liveViewModel.isLoading {
                    // 已确认为空态时才显示空态视图
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 其他情况都显示列表（包括加载中、有数据）
                    roomListView
                }
            }
            // 菜单接到焦点之前保留原卡片，确保快速“左 → 返回”仍有命令接收者。
            // 焦点进入菜单后，再将背景排除出遥控器的焦点搜索。
            .disabled(liveViewModel.isSidebarExpanded && sidebarOwnsFocus)
            .blur(radius: liveViewModel.isSidebarExpanded ? 5 : 0)
            .animation(.easeInOut(duration: 0.25), value: liveViewModel.isSidebarExpanded)

            // 遮罩层
            if liveViewModel.isSidebarExpanded {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            logNavigation("dimmingTap")
                            cancelPendingFocus()
                            closeSidebar()
                        }
                    .transition(.opacity)
            }

            // Sidebar
            if liveViewModel.roomList.count > 0 || liveViewModel.categories.count > 0 {
                SidebarView(
                    focusState: $focusState,
                    onSelectCategory: selectCategory,
                    onExitSidebar: {
                        logNavigation("sidebarExitCommand")
                        cancelPendingFocus()
                        closeSidebar()
                    }
                )
                    .environment(liveViewModel)
                    .zIndex(2)
                    .onMoveCommand { direction in
                        cancelPendingFocus()
                        if direction == .right {
                            closeSidebar()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: pendingSidebarFocus) {
            guard let target = pendingSidebarFocus,
                  !liveViewModel.isSidebarExpanded,
                  !Task.isCancelled else { return }
            // 等背景在新视图树中重新启用，再请求恢复焦点。
            focusState = target
            pendingSidebarFocus = nil
        }
        .task(id: pendingFocusTarget) {
            guard let target = pendingFocusTarget else { return }
            guard !Task.isCancelled else { return }
            focusState = target
            pendingCategoryFocus = false
            hasSetInitialFocus = true
        }
    }

    private func errorView(_ error: Error) -> some View {
        let authTitle: String = {
            if error.isAuthRequired {
                let platformName = LiveParseTools.getLivePlatformName(liveViewModel.liveType)
                return "加载失败-请登录\(platformName)账号"
            }
            return "加载失败"
        }()

        return ErrorView(
            title: authTitle,
            message: error.liveParseMessage,
            detailMessage: error.liveParseDetail,
            curlCommand: error.liveParseCurl,
            showRetry: true,
            showLoginButton: error.isAuthRequired,
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
        .interactiveDismissDisabled()
        .task {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            await liveViewModel.getCategoryList()
        }
        .onExitCommand {
            logNavigation("exitCommand")
            handleBackCommand()
        }
        .onKeyPress(.escape, phases: .all) { press in
            logNavigation("escape phase=\(press.phase)")
            // Escape 不一定转换为遥控器的 Exit 命令。消费整个按键，
            // 松开时只返回一层，避免按下时收起菜单、松开时又退出页面。
            if press.phase == .up {
                handleBackCommand()
            }
            return .handled
        }
        .onChange(of: focusState) { oldValue, newValue in
            logNavigation("focusChanged from=\(String(describing: oldValue)) to=\(String(describing: newValue))")
        }
        .onChange(of: liveViewModel.roomList) { _, _ in
            updateEmptyState()
        }
        .onChange(of: liveViewModel.isLoading) { _, _ in
            updateEmptyState()
        }
        .onAppear {
            logNavigation("listAppeared")
            updateEmptyState()
        }
        .onDisappear {
            logNavigation("listDisappeared")
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
                    Logger.debug("background。。。。", category: .app)
                case .inactive:
                    Logger.debug("inactive。。。。", category: .app)
                @unknown default:
                    break
            }
        }
        .overlay {
            if !liveViewModel.roomList.isEmpty && !liveViewModel.isSidebarExpanded {
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
        .fullScreenCover(isPresented: $showCapabilitySheet) {
            TVPlatformCapabilitySheet(liveType: liveType)
                .environment(appViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    showCapabilitySheet = false
                }
        }
    }
}
