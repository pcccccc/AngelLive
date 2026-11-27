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
    case historyContent(String)
    case leftFavorite(Int, Int)
    case platformInfo
    case platformSearch
    case emptyContent
    case leftTrigger
}

struct ListMainView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) var scenePhase
    @State var needFullScreenLoading: Bool = false
    @State private var hasSetInitialFocus: Bool = false
    @State private var pendingCategoryFocus = false
    @State private var pendingSidebarFocus: FocusableField?
    @State private var showCapabilitySheet: Bool = false
    @State private var showPlatformSearch = false
    @State private var authenticationRecovery: AuthenticationRecoveryRequest?
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
    private let headerToGridSpacing: CGFloat = 24
    private let headerTrailingInset: CGFloat = 80
    // tvOS 的 plain 按钮焦点背景超出 label，动作间距须包含两侧扩展区域。
    private let headerActionSpacing: CGFloat = 80

    private let platform: Platformdescription
    private var liveType: LiveType { platform.liveType }
    @State private var liveViewModel: LiveViewModel
    @FocusState var focusState: FocusableField?
    var appViewModel: AppState
    
    init(platform: Platformdescription, appViewModel: AppState) {
        self.platform = platform
        self.appViewModel = appViewModel
        let model = LiveViewModel(
            roomListType: .live,
            liveType: platform.liveType,
            appViewModel: appViewModel,
            shouldLoadData: false
        )
        model.usesCategoryRoomCache = true
        _liveViewModel = State(initialValue: model)
    }

    private enum RoomGridItem: Hashable {
        case room(Int)
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

        return items
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection, from cardIndex: Int? = nil) {
        logNavigation("move direction=\(direction) cardIndex=\(String(describing: cardIndex)) selectedIndex=\(liveViewModel.selectedRoomListIndex)")
        cancelPendingFocus()

        // 侧栏收起重建时焦点可能暂时为空，卡片闭包仍明确提供事件来源。
        switch focusState ?? cardIndex.map({ FocusableField.mainContent($0) }) {
        case .leftMenu, .leftFavorite:
            if direction == .right {
                closeSidebar()
            }
        case .mainContent(let focusedIndex):
            let index = cardIndex ?? focusedIndex
            if direction == .left && index >= 0 && index % gridColumnCount == 0 {
                openSidebar()
            } else if direction == .up && index < gridColumnCount && canSearchPlatform {
                focusState = .platformSearch
            }
        case .emptyContent, .platformInfo:
            if direction == .left {
                openSidebar()
            } else if direction == .up && focusState == .emptyContent && canSearchPlatform {
                focusState = .platformSearch
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
                    Task { await liveViewModel.refreshDisplayedRooms() }
                    reader.scrollTo(Self.topId)
                })
                .frame(width: 370, height: cardHeight)
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
        .overlay(alignment: .leading) {
            if appViewModel.pluginAvailability.hasAvailablePlugins, !liveViewModel.roomList.isEmpty, !liveViewModel.isSidebarExpanded {
                Label("刷新", systemImage: "playpause.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .trailing) {
            platformHeaderActions
        }
    }

    private var canSearchPlatform: Bool {
        appViewModel.pluginAvailability.hasAvailablePlugins && !RoomSearchKind.platformOptions(for: liveType).isEmpty
    }

    private var platformHeaderActions: some View {
        HStack(spacing: headerActionSpacing) {
            if canSearchPlatform {
                platformSearchButton
            }
            Button {
                showCapabilitySheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(
                        minWidth: canSearchPlatform ? 44 : nil,
                        minHeight: canSearchPlatform ? 44 : nil
                    )
            }
            .buttonStyle(.plain)
            .focused($focusState, equals: .platformInfo)
            .onMoveCommand { direction in
                if direction == .left && canSearchPlatform {
                    cancelPendingFocus()
                    focusState = .platformSearch
                } else {
                    handleMoveCommand(direction)
                }
            }
        }
        .padding(.trailing, headerTrailingInset)
    }

    private var platformSearchButton: some View {
        Button {
            guard !liveViewModel.isSidebarExpanded else { return }
            cancelPendingFocus()
            showPlatformSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .focused($focusState, equals: .platformSearch)
        .accessibilityLabel("搜索当前平台")
        .onMoveCommand { direction in
            if direction == .left && blockingError == nil {
                openSidebar()
            }
        }
    }

    @ViewBuilder
    private var platformSearchOnEmptyContent: some View {
        if canSearchPlatform {
            platformSearchButton
                .padding(.trailing, headerTrailingInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .focusSection()
        }
    }

    private var roomPhase: RoomListDisplayPhase {
        if liveViewModel.dismissedRoomFailure, liveViewModel.roomListPhase == .failure {
            return .empty
        }
        return liveViewModel.roomListPhase
    }

    private var showsLoadMoreFooter: Bool {
        roomPhase == .content && liveViewModel.isLoadingMoreRooms
    }

    private var blockingError: Error? {
        if liveViewModel.hasError, let error = liveViewModel.currentError {
            return error
        }
        return liveViewModel.displayedRoomError
    }

    private var sidebarOwnsFocus: Bool {
        switch focusState {
        case .leftMenu, .leftFavorite:
            return true
        default:
            return false
        }
    }

    private func isSidebarTriggerSource(_ focus: FocusableField?) -> Bool {
        switch focus {
        case .mainContent(let index):
            return liveViewModel.roomList.indices.contains(index) && index % gridColumnCount == 0
        case .emptyContent:
            return roomPhase == .empty
        case .platformInfo, .platformSearch:
            // 初次加载时信息按钮可能先获得焦点，不能据此启用左缘入口。
            return !liveViewModel.roomList.isEmpty
        default:
            return false
        }
    }

    private var canFocusSidebarTrigger: Bool {
        guard !liveViewModel.categories.isEmpty,
              roomPhase == .content || roomPhase == .empty,
              !liveViewModel.isSidebarExpanded || focusState == .leftTrigger,
              blockingError == nil,
              !showCapabilitySheet,
              !showPlatformSearch,
              authenticationRecovery == nil,
              !liveViewModel.showAlert,
              !pendingCategoryFocus,
              pendingSidebarFocus == nil else { return false }
        // 焦点移入透明按钮后，保持可聚焦直到侧栏接管，避免回调前先失焦。
        return focusState == .leftTrigger || isSidebarTriggerSource(focusState)
    }

    private var leftSidebarTrigger: some View {
        Button {
            guard canFocusSidebarTrigger else { return }
            openSidebar()
        } label: {
            Rectangle()
                .fill(Color.clear)
        }
        .frame(width: 1)
        .frame(maxHeight: .infinity)
        .opacity(0.001)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!canFocusSidebarTrigger)
        // 保留透明 label 外层的焦点区域，供左缘方向搜索使用。
        .focusable(canFocusSidebarTrigger)
        .focusEffectDisabled()
        .focused($focusState, equals: .leftTrigger)
        .accessibilityLabel("打开分类")
    }

    private func openSidebar() {
        guard !showPlatformSearch,
              !liveViewModel.isSidebarExpanded,
              !liveViewModel.categories.isEmpty else { return }
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
        switch roomPhase {
        case .content:
            let selectedIndex = liveViewModel.selectedRoomListIndex
            let validIndex = liveViewModel.roomList.indices.contains(selectedIndex) ? selectedIndex : 0
            return .mainContent(validIndex)
        case .empty:
            return .emptyContent
        case .skeleton, .failure:
            return .platformInfo
        }
    }

    private func closeSidebar(restoreContentFocus: Bool = true) {
        logNavigation("closeSidebar target=\(focusAfterSidebarClose)")
        pendingSidebarFocus = restoreContentFocus ? focusAfterSidebarClose : nil
        liveViewModel.isSidebarExpanded = false
    }

    private func handleBackCommand() {
        guard !showPlatformSearch else { return }
        cancelPendingFocus()
        if liveViewModel.isSidebarExpanded {
            closeSidebar()
        } else {
            logNavigation("dismissList")
            dismiss()
        }
    }

    private func logNavigation(_ event: String) {
        let message = "RoomListNavigation \(event) model=\(ObjectIdentifier(liveViewModel)) focus=\(String(describing: focusState)) expanded=\(liveViewModel.isSidebarExpanded) loading=\(liveViewModel.isLoading) pendingCategory=\(pendingCategoryFocus) roomCount=\(liveViewModel.roomList.count) triggerEnabled=\(canFocusSidebarTrigger)"
        Logger.debug(message, category: .ui)
        #if DEBUG
        // 保留非调试器启动后的返回记录，避免设备会话结束时丢失现场。
        os_log("%{public}@", log: Self.navigationLog, type: .default, message)
        #endif
    }

    private var pendingFocusTarget: FocusableField? {
        guard roomPhase != .skeleton,
              roomPhase != .failure,
              blockingError == nil,
              !showPlatformSearch,
              !liveViewModel.isSidebarExpanded else {
            return nil
        }

        if pendingCategoryFocus {
            return roomPhase == .empty ? .emptyContent : .mainContent(0)
        }

        guard !hasSetInitialFocus else { return nil }
        return roomPhase == .empty ? .emptyContent : .mainContent(0)
    }

    private var emptyStateView: some View {
        let isRetrying = liveViewModel.isLoading
        return VStack(spacing: 28) {
            Image(systemName: "video.slash")
                .font(.system(size: 64))
            Text("暂无直播")
                .font(.title2.bold())
            Text("换个分类看看，或稍后再试")
                .foregroundStyle(.secondary)
            Button {
                guard !isRetrying else { return }
                liveViewModel.dismissedRoomFailure = false
                Task { await liveViewModel.refreshDisplayedRooms() }
            } label: {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }
            .accessibilityLabel(isRetrying ? "正在加载" : "重试")
        }
        .padding()
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
                    if roomPhase == .skeleton {
                        TVRoomSkeletonGrid(columns: gridColumns, spacing: gridSpacing)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
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
                    }

                    if showsLoadMoreFooter {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    } else if !liveViewModel.hasMoreRooms && !liveViewModel.roomList.isEmpty {
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
                if roomPhase == .empty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) { platformSearchOnEmptyContent }
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
                  !showPlatformSearch,
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
            showLoginButton: error.showsLoginAction,
            isRetrying: liveViewModel.isLoading,
            onDismiss: {
                liveViewModel.dismissedRoomFailure = true
                liveViewModel.hasError = false
                liveViewModel.currentError = nil
            },
            onRetry: {
                liveViewModel.dismissedRoomFailure = false
                if liveViewModel.categories.isEmpty {
                    Task { await liveViewModel.getCategoryList() }
                } else {
                    Task { await liveViewModel.refreshDisplayedRooms() }
                }
            },
            onLogin: {
                let pluginIDs = SandboxPluginCatalog.platform(for: liveViewModel.liveType).map { [$0.pluginId] } ?? []
                authenticationRecovery = AuthenticationRecoveryRequest(pluginIDs: pluginIDs)
            }
        )
    }

    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        ZStack {
            if let error = blockingError {
                errorView(error)
                    .overlay(alignment: .topTrailing) { platformSearchOnEmptyContent }
            } else {
                listContainerView
            }

            // 菜单真正接到焦点前保留入口，不能在展开瞬间删掉当前焦点源。
            if !liveViewModel.categories.isEmpty &&
                (!liveViewModel.isSidebarExpanded || focusState == .leftTrigger) {
                HStack(spacing: 0) {
                    leftSidebarTrigger
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .ignoresSafeArea()
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
            guard !showPlatformSearch else { return .ignored }
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
            if newValue == .leftTrigger,
               canFocusSidebarTrigger,
               isSidebarTriggerSource(oldValue) {
                openSidebar()
            }
        }
        .onAppear {
            logNavigation("listAppeared")
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
            guard !showPlatformSearch, liveViewModel.isLoading else { return }
            Task { await liveViewModel.refreshDisplayedRooms() }
        })
        .onChange(of: scenePhase) { oldValue, newValue in
            switch newValue {
                case .active:
                    liveViewModel.showToast(true, title: "程序返回前台，正在为您刷新列表", hideAfter: 3)
                    Task { await liveViewModel.refreshDisplayedRooms() }
                case .background:
                    Logger.debug("background。。。。", category: .app)
                case .inactive:
                    Logger.debug("inactive。。。。", category: .app)
                @unknown default:
                    break
            }
        }
        .overlay {
            if !appViewModel.pluginAvailability.hasAvailablePlugins && !liveViewModel.roomList.isEmpty && !liveViewModel.isSidebarExpanded {
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
        .fullScreenCover(item: $authenticationRecovery) { request in
            AccountManagementView(recoveryPluginIDs: request.pluginIDs)
                .frame(maxWidth: 1000)
                .padding(80)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
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
        .fullScreenCover(isPresented: $showPlatformSearch, onDismiss: {
            if canSearchPlatform {
                focusState = .platformSearch
            }
        }) {
            TVPlatformSearchView(platform: platform, appViewModel: appViewModel)
        }
    }
}
