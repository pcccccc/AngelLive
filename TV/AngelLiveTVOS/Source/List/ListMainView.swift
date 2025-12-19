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

private enum SimpleCellMode {
    case textOnly
    case coverOnly
    case coverAndText
}

struct ListMainView: View {

    @Environment(\.scenePhase) var scenePhase
    @State private var needFullScreenLoading: Bool = false
    @State private var hasSetInitialFocus: Bool = false
    private static let topId = "topIdHere"
    private let useMoveCommandProbe = false
    private let probeUsesScrollView = true
    private let useSimpleListCells = true
    private let useStaticRooms = false
    private let useStableRoomsSnapshot = true
    private let deferRoomListUpdates = true
    private let roomListUpdateDelay: TimeInterval = 0.25
    private let disableSceneRefresh = true
    private let forceFocusOnRoomListChange = true
    private let staticRoomCount = 16
    private let simpleCellMode: SimpleCellMode = .textOnly
    private let simpleCellUsesRemoteImage = false
    @State private var lastMoveDirection: MoveCommandDirection?
    @State private var lastMoveCommandAt: TimeInterval = 0
    @State private var deferredRooms: [LiveModel] = []
    @State private var pendingRoomUpdate: DispatchWorkItem?
    @State private var pendingFocusReset: DispatchWorkItem?
    @State private var stableRooms: [LiveModel] = []

    let liveType: LiveType
    @State private var liveViewModel: LiveViewModel
    @FocusState private var focusState: FocusableField?
    let appViewModel: AppState

    init(liveType: LiveType, appViewModel: AppState) {
        self.liveType = liveType
        self.appViewModel = appViewModel
        _liveViewModel = State(wrappedValue: LiveViewModel(roomListType: .live, liveType: liveType, appViewModel: appViewModel))
    }
    
    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        Group {
            if useMoveCommandProbe {
                moveCommandProbeView
            } else {
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
                                    let rooms = displayRooms
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
                                        ForEach(rooms.indices, id: \.self) { index in
                                            if useSimpleListCells {
                                                simpleListCell(index: index, room: rooms[index])
                                            } else {
                                                LiveCardView(index: index, externalFocusState: $focusState)
                                                    .environment(liveViewModel)
                                                    .onPlayPauseCommand(perform: {
                                                        liveViewModel.roomPage = 1
                                                        liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
                                                        reader.scrollTo(Self.topId)
                                                    })
                                                    .frame(width: 370, height: 280)
                                            }
                                        }
                                        if !useStaticRooms && liveViewModel.isLoading {
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
                            }
                        }
                    }
                }
            }
        }
        .background(.thinMaterial)
        .onMoveCommand { direction in
            if useMoveCommandProbe {
                lastMoveDirection = direction
            }
            lastMoveCommandAt = Date.timeIntervalSinceReferenceDate
            handleMoveCommand(direction)
        }
        .onChange(of: focusState) { _, newValue in
            guard !useMoveCommandProbe else { return }
            // 当焦点移到主内容时，关闭 sidebar
            switch newValue {
            case .mainContent(let idx):
                if useSimpleListCells {
                    liveViewModel.selectedRoomListIndex = idx
                }
                if liveViewModel.isSidebarExpanded {
                    liveViewModel.isSidebarExpanded = false
                }
            default:
                break
            }
        }
        .onChange(of: liveViewModel.roomList) { _, newValue in
            guard !useMoveCommandProbe else { return }
            guard !useStaticRooms else { return }
            if useStableRoomsSnapshot && stableRooms.isEmpty && !newValue.isEmpty {
                stableRooms = newValue
            }
            if deferRoomListUpdates {
                scheduleRoomListUpdate(newValue)
            }
            if forceFocusOnRoomListChange {
                scheduleFocusResetIfNeeded(newValue)
            } else {
                // 当 roomList 首次加载完成时，设置初始焦点到主内容
                if !hasSetInitialFocus && !newValue.isEmpty {
                    hasSetInitialFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        focusState = .mainContent(0)
                    }
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
            guard !useMoveCommandProbe else { return }
            guard !useStaticRooms else { return }
            guard liveViewModel.isLoading == true else { return }
            liveViewModel.getRoomList(index: 1)
        })
        .onChange(of: scenePhase) { oldValue, newValue in
            guard !useMoveCommandProbe else { return }
            guard !useStaticRooms else { return }
            guard !disableSceneRefresh else { return }
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
            if !useMoveCommandProbe && !displayRooms.isEmpty {
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

    private var moveCommandProbeView: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 24) {
                Text("Move: \(moveCommandLabel(lastMoveDirection))")
                    .font(.title2)
                Text("Focus: \(focusLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if probeUsesScrollView {
                    ScrollView {
                        probeGrid
                    }
                } else {
                    probeGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: liveViewModel.isSidebarExpanded ? 5 : 0)
            .animation(.easeInOut(duration: 0.25), value: liveViewModel.isSidebarExpanded)

            if liveViewModel.isSidebarExpanded {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        liveViewModel.isSidebarExpanded = false
                        focusState = .mainContent(max(0, liveViewModel.selectedRoomListIndex))
                    }
                    .transition(.opacity)
            }

            SidebarView(focusState: $focusState)
                .environment(liveViewModel)
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if focusState == nil {
                focusState = .mainContent(0)
            }
        }
    }

    private var probeGrid: some View {
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
            ForEach(0..<12, id: \.self) { index in
                Button("Item \(index)") { }
                    .buttonStyle(.card)
                    .frame(width: 370, height: 280)
                    .focused($focusState, equals: .mainContent(index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch focusState {
        case .mainContent(let idx):
            if direction == .left && idx % 4 == 0 {
                liveViewModel.isSidebarExpanded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusState = .leftMenu(0, 0)
                }
            }
        case .leftMenu, .leftFavorite:
            if direction == .right {
                liveViewModel.isSidebarExpanded = false
                focusState = .mainContent(max(0, liveViewModel.selectedRoomListIndex))
            }
        default:
            break
        }
    }

    private func simpleListCell(index: Int, room: LiveModel) -> some View {
        return Button {
            // No-op: test focus and move commands only.
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                if simpleCellMode == .coverOnly || simpleCellMode == .coverAndText {
                    simpleCellCover(room: room)
                }
                if simpleCellMode == .textOnly || simpleCellMode == .coverAndText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.userName.isEmpty ? "主播 \(index)" : room.userName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(room.roomTitle.isEmpty ? "房间标题" : room.roomTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.card)
        .frame(width: 370, height: 280)
        .focused($focusState, equals: .mainContent(index))
        .onPlayPauseCommand(perform: {
            guard !useStaticRooms else { return }
            liveViewModel.roomPage = 1
            liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
        })
    }

    @ViewBuilder
    private func simpleCellCover(room: LiveModel) -> some View {
        if simpleCellUsesRemoteImage, let url = URL(string: room.roomCover), !room.roomCover.isEmpty {
            KFImage(url)
                .placeholder {
                    Image("placeholder")
                        .resizable()
                        .scaledToFill()
                }
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .clipped()
        } else {
            Image("placeholder")
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .clipped()
        }
    }

    private var focusLabel: String {
        guard let focusState else { return "none" }
        switch focusState {
        case .leftMenu(let parent, let child):
            return "leftMenu \(parent)-\(child)"
        case .mainContent(let index):
            return "mainContent \(index)"
        case .leftFavorite(let parent, let child):
            return "leftFavorite \(parent)-\(child)"
        }
    }

    private func moveCommandLabel(_ direction: MoveCommandDirection?) -> String {
        switch direction {
        case .up:
            return "up"
        case .down:
            return "down"
        case .left:
            return "left"
        case .right:
            return "right"
        case .none:
            return "none"
        @unknown default:
            return "unknown"
        }
    }

    private var displayRooms: [LiveModel] {
        if useStaticRooms {
            return staticRooms
        }
        if useStableRoomsSnapshot {
            return stableRooms.isEmpty ? liveViewModel.roomList : stableRooms
        }
        if deferRoomListUpdates {
            return deferredRooms.isEmpty ? liveViewModel.roomList : deferredRooms
        }
        return liveViewModel.roomList
    }

    private var staticRooms: [LiveModel] {
        (0..<staticRoomCount).map { index in
            LiveModel(
                userName: "主播 \(index)",
                roomTitle: "标题 \(index)",
                roomCover: "",
                userHeadImg: "",
                liveType: liveType,
                liveState: "1",
                userId: "user-\(index)",
                roomId: "room-\(index)",
                liveWatchedCount: nil
            )
        }
    }

    private func scheduleRoomListUpdate(_ rooms: [LiveModel]) {
        pendingRoomUpdate?.cancel()
        let workItem = DispatchWorkItem { [rooms] in
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastMoveCommandAt >= roomListUpdateDelay {
                deferredRooms = rooms
            } else {
                scheduleRoomListUpdate(rooms)
            }
        }
        pendingRoomUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + roomListUpdateDelay, execute: workItem)
    }

    private func scheduleFocusResetIfNeeded(_ rooms: [LiveModel]) {
        guard !rooms.isEmpty else { return }
        let maxIndex = rooms.count - 1
        let desiredIndex = max(0, min(liveViewModel.selectedRoomListIndex, maxIndex))
        if case .mainContent(let currentIndex) = focusState,
           currentIndex >= 0,
           currentIndex <= maxIndex {
            return
        }

        pendingFocusReset?.cancel()
        let workItem = DispatchWorkItem {
            focusState = .mainContent(desiredIndex)
        }
        pendingFocusReset = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}
