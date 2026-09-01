import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

/// tvOS 的插件驱动首页。共享层负责内容、缓存和聚合，当前文件只拥有电视端布局、焦点和播放呈现。
struct TVHomeView: View {
    private let appViewModel: AppState

    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = PluginHomeFeedModel()
    @State private var playback: TVHomePlaybackCoordinator
    @State private var navigationPath: [PluginHomeCategoryRoute] = []
    @State private var selectedBannerID: String?
    @State private var heroHasFocus = false
    @State private var presentedInfoEntry: HomeBannerEntry?

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        _playback = State(initialValue: TVHomePlaybackCoordinator(appViewModel: appViewModel))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        heroStage(containerSize: geometry.size)

                        ForEach(remainingRails) { rail in
                            TVHomeRoomRail(
                                rail: rail,
                                appViewModel: appViewModel,
                                onSeeAll: openCategory
                            )
                            .padding(.top, 26)
                        }

                        if !model.failedPluginNames.isEmpty {
                            TVHomeFailureCard(
                                pluginNames: model.failedPluginNames,
                                isRefreshing: model.isRefreshing,
                                retry: refreshHome
                            )
                            .padding(.horizontal, TVHomeMetrics.horizontalMargin)
                            .padding(.top, 32)
                        }

                        Color.clear.frame(height: 120)
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .background(Color.black)
                .ignoresSafeArea()
            }
            .navigationDestination(for: PluginHomeCategoryRoute.self) { route in
                TVHomeCategoryView(route: route, appViewModel: appViewModel)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tvHomePlaybackPresentation(playback)
        .overlay {
            if let entry = presentedInfoEntry {
                TVHomeBannerInfoOverlay(entry: entry) {
                    presentedInfoEntry = nil
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .task(id: refreshTrigger) {
            async let homeRefresh: Void = model.refresh(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )
            async let favoriteRefresh: Void = refreshFavoritesIfNeeded()
            _ = await (homeRefresh, favoriteRefresh)
            normalizeBannerSelection()
        }
        .onChange(of: model.bannerEntries.map(\.id)) { _, _ in
            normalizeBannerSelection()
        }
        .task(id: autoplayTrigger) {
            await runAutoplayIfNeeded()
        }
    }
}

private extension TVHomeView {
    var refreshTrigger: TVHomeRefreshTrigger {
        TVHomeRefreshTrigger(
            installedPluginIds: pluginAvailability.installedPluginIds,
            availabilityConfirmed: pluginAvailability.hasCheckedAvailability,
            catalogRevision: pluginAvailability.catalogRevision
        )
    }

    var autoplayTrigger: TVHomeAutoplayTrigger {
        TVHomeAutoplayTrigger(
            bannerIDs: model.bannerEntries.map(\.id),
            selectedBannerID: selectedBannerID,
            scenePhase: scenePhase,
            reduceMotion: reduceMotion,
            heroHasFocus: heroHasFocus,
            isPresentingInfo: presentedInfoEntry != nil
        )
    }

    var activeBanner: HomeBannerEntry? {
        model.bannerEntries.first(where: { $0.id == selectedBannerID })
            ?? model.bannerEntries.first
    }

    var isAwaitingFirstContent: Bool {
        let hasConfiguredSources = !pluginAvailability.installedPluginIds.isEmpty
        return model.bannerEntries.isEmpty
            && model.sectionEntries.isEmpty
            && (
                !pluginAvailability.hasCheckedAvailability
                    || pluginAvailability.isChecking
                    || (hasConfiguredSources && !model.hasRestoredCache)
                    || (hasConfiguredSources && !model.hasLoaded)
            )
    }

    var favoriteRail: TVHomeRailData? {
        let rooms = Array(appViewModel.favoriteViewModel.roomList.prefix(10))
        guard !rooms.isEmpty else { return nil }
        return TVHomeRailData(
            id: "favorites",
            title: "我的收藏",
            subtitle: appViewModel.favoriteViewModel.isFavoriteStatusRefreshing ? "直播状态更新中" : nil,
            rooms: rooms,
            route: nil,
            playbackMode: .favorite
        )
    }

    var pluginRails: [TVHomeRailData] {
        model.sectionEntries.map { entry in
            let source = entry.section.personalized
                ? "为你推荐 · 来自 \(entry.pluginDisplayName)"
                : "来自 \(entry.pluginDisplayName)"
            let subtitle = entry.section.subtitle.flatMap { text in
                text.isEmpty ? nil : "\(text) · \(source)"
            } ?? source
            let route = entry.section.seeAllTarget.map {
                PluginHomeCategoryRoute(
                    pluginId: entry.pluginId,
                    liveType: entry.liveType,
                    category: $0,
                    fallbackTitle: entry.section.title
                )
            }
            return TVHomeRailData(
                id: entry.id,
                title: entry.section.title,
                subtitle: subtitle,
                rooms: entry.section.items.map(\.room),
                route: route,
                playbackMode: .direct
            )
        }
    }

    var primaryRail: TVHomeRailData? {
        favoriteRail ?? pluginRails.first
    }

    var remainingRails: [TVHomeRailData] {
        if favoriteRail != nil {
            return pluginRails
        }
        return Array(pluginRails.dropFirst())
    }

    func heroStage(containerSize: CGSize) -> some View {
        let heroContentHeight = min(max(containerSize.height * 0.92, 900), 980)
        let stageHeight = heroContentHeight + (primaryRail == nil ? 0 : TVHomeMetrics.railHeight)
        return ZStack(alignment: .topLeading) {
            TVHomeHeroBackdrop(entry: activeBanner)
                .frame(width: containerSize.width, height: stageHeight)

            VStack(alignment: .leading, spacing: 0) {
                if let activeBanner {
                    TVHomeHeroContent(
                        entry: activeBanner,
                        onPrimaryAction: { openHeroTarget(activeBanner) },
                        onInfo: { presentedInfoEntry = activeBanner },
                        onFocusChanged: { heroHasFocus = $0 }
                    )
                    .frame(
                        width: containerSize.width,
                        height: heroContentHeight,
                        alignment: .topLeading
                    )
                } else if isAwaitingFirstContent {
                    TVHomeHeroLoadingContent()
                        .frame(
                            width: containerSize.width,
                            height: heroContentHeight,
                            alignment: .topLeading
                        )
                } else {
                    TVHomeEmptyHeroContent(
                        isRefreshing: model.isRefreshing,
                        retry: refreshHome
                    )
                    .frame(
                        width: containerSize.width,
                        height: heroContentHeight,
                        alignment: .topLeading
                    )
                }

                if let primaryRail {
                    TVHomeRoomRail(
                        rail: primaryRail,
                        appViewModel: appViewModel,
                        onSeeAll: openCategory
                    )
                }
            }
            .frame(width: containerSize.width, alignment: .topLeading)

            if let activeBanner, model.bannerEntries.count > 1 {
                TVHomePageIndicator(
                    entries: model.bannerEntries,
                    selectedID: activeBanner.id
                )
                .frame(width: containerSize.width, alignment: .center)
                .padding(.top, heroContentHeight + 12)
                .allowsHitTesting(false)
                .zIndex(2)
            }
        }
        .frame(
            width: containerSize.width,
            height: stageHeight,
            alignment: .topLeading
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.38), value: activeBanner?.id)
    }

    func openHeroTarget(_ entry: HomeBannerEntry) {
        switch entry.banner.target {
        case .room(let room):
            playback.open(room: room, rooms: [room], mode: .direct)
        case .category(let category):
            navigationPath.append(
                PluginHomeCategoryRoute(
                    pluginId: entry.pluginId,
                    liveType: entry.liveType,
                    category: category,
                    fallbackTitle: entry.banner.title
                )
            )
        }
    }

    func openCategory(_ route: PluginHomeCategoryRoute) {
        navigationPath.append(route)
    }

    @MainActor
    func refreshFavoritesIfNeeded() async {
        if appViewModel.favoriteViewModel.shouldSync() {
            await appViewModel.favoriteViewModel.syncWithActor()
        }
    }

    func refreshHome() {
        Task {
            await model.refresh(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )
        }
    }

    func normalizeBannerSelection() {
        guard !model.bannerEntries.isEmpty else {
            selectedBannerID = nil
            return
        }
        if !model.bannerEntries.contains(where: { $0.id == selectedBannerID }) {
            selectedBannerID = model.bannerEntries[0].id
        }
    }

    @MainActor
    func runAutoplayIfNeeded() async {
        guard model.bannerEntries.count > 1,
              scenePhase == .active,
              !reduceMotion,
              !heroHasFocus,
              presentedInfoEntry == nil else { return }
        do {
            try await Task.sleep(for: .seconds(7))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let currentIndex = model.bannerEntries.firstIndex(where: { $0.id == selectedBannerID }) ?? 0
        selectedBannerID = model.bannerEntries[(currentIndex + 1) % model.bannerEntries.count].id
    }
}

private struct TVHomeHeroBackdrop: View {
    let entry: HomeBannerEntry?

    private var roomCoverURL: URL? {
        guard let entry, case .room(let room) = entry.banner.target, !room.roomCover.isEmpty else {
            return nil
        }
        return URL(string: room.roomCover)
    }

    var body: some View {
        ZStack {
            Color.black

            if let roomCoverURL {
                KFImage(roomCoverURL)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }

            if let imageURL = entry?.banner.imageURL {
                KFImage(imageURL)
                    .placeholder { Color.clear }
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.92), location: 0),
                    .init(color: .black.opacity(0.62), location: 0.26),
                    .init(color: .black.opacity(0.12), location: 0.62),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.48),
                    .init(color: .black.opacity(0.48), location: 0.76),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct TVHomeHeroContent: View {
    enum FocusedControl: Hashable {
        case primary
        case info
    }

    let entry: HomeBannerEntry
    let onPrimaryAction: () -> Void
    let onInfo: () -> Void
    let onFocusChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focusedControl: FocusedControl?
    @Namespace private var focusScope

    private var primaryTitle: String {
        switch entry.banner.target {
        case .room: "立即观看"
        case .category: "查看分类"
        }
    }

    private var primarySymbol: String {
        switch entry.banner.target {
        case .room: "play.fill"
        case .category: "rectangle.grid.2x2.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("来自")
                    .foregroundStyle(.white.opacity(0.62))
                Text(entry.pluginDisplayName)
                    .foregroundStyle(.purple.opacity(0.96))
            }
            .font(.system(size: 26, weight: .medium))

            Text(entry.banner.title.isEmpty ? entry.pluginDisplayName : entry.banner.title)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.top, 24)

            if let subtitle = entry.banner.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(2)
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.top, 18)
            }

            HStack(spacing: 48) {
                Button(action: onPrimaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 173, height: 41)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.white.opacity(reduceTransparency ? 0.92 : 0.82))
                .focused($focusedControl, equals: .primary)
                .prefersDefaultFocus(true, in: focusScope)
                .accessibilityLabel(primaryTitle)

                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 41, height: 41)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(.white)
                .focused($focusedControl, equals: .info)
                .accessibilityLabel("内容详情")
            }
            .padding(.top, 76)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TVHomeMetrics.horizontalMargin)
        .padding(.top, 390)
        .focusScope(focusScope)
        .task {
            guard focusedControl == nil else { return }
            await Task.yield()
            focusedControl = .primary
        }
        .onChange(of: focusedControl) { _, value in
            onFocusChanged(value != nil)
        }
    }
}

private struct TVHomePageIndicator: View {
    let entries: [HomeBannerEntry]
    let selectedID: String

    private var visibleEntries: [HomeBannerEntry] {
        guard entries.count > 7,
              let selectedIndex = entries.firstIndex(where: { $0.id == selectedID }) else {
            return entries
        }
        let start = min(max(selectedIndex - 3, 0), entries.count - 7)
        return Array(entries[start..<(start + 7)])
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(visibleEntries) { entry in
                Capsule()
                    .fill(.white.opacity(entry.id == selectedID ? 0.92 : 0.38))
                    .frame(width: entry.id == selectedID ? 38 : 10, height: 10)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: selectedID)
        .accessibilityElement()
        .accessibilityLabel("焦点内容")
        .accessibilityValue(pageDescription)
    }

    private var pageDescription: String {
        let index = entries.firstIndex(where: { $0.id == selectedID }).map { $0 + 1 } ?? 1
        return "第 \(index) 项，共 \(entries.count) 项"
    }
}

private struct TVHomeRoomRail: View {
    let rail: TVHomeRailData
    let appViewModel: AppState
    let onSeeAll: (PluginHomeCategoryRoute) -> Void

    @State private var liveViewModel: LiveViewModel

    init(
        rail: TVHomeRailData,
        appViewModel: AppState,
        onSeeAll: @escaping (PluginHomeCategoryRoute) -> Void
    ) {
        self.rail = rail
        self.appViewModel = appViewModel
        self.onSeeAll = onSeeAll

        let roomListType: LiveRoomListType = rail.playbackMode == .favorite ? .favorite : .live
        let viewModel = LiveViewModel(
            roomListType: roomListType,
            liveType: rail.rooms.first?.liveType ?? .placeholder,
            appViewModel: appViewModel,
            shouldLoadData: false
        )
        viewModel.roomList = rail.rooms
        _liveViewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                Text(rail.title)
                    .font(.system(size: 28, weight: .bold))

                Spacer()

                if let route = rail.route {
                    Button {
                        onSeeAll(route)
                    } label: {
                        Label("查看全部", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityHint("打开完整分类")
                }
            }
            .padding(.horizontal, TVHomeMetrics.horizontalMargin)

            ScrollView(.horizontal) {
                LazyHStack(spacing: TVHomeMetrics.cardSpacing) {
                    ForEach(Array(rail.rooms.enumerated()), id: \.element.id) { index, room in
                        LiveCardView(
                            index: index,
                            currentLiveModel: room,
                            cardWidth: TVHomeMetrics.cardWidth,
                            coverHeight: TVHomeMetrics.cardCoverHeight
                        )
                            .environment(liveViewModel)
                            .environment(appViewModel)
                            .frame(
                                width: TVHomeMetrics.cardWidth,
                                height: TVHomeMetrics.cardHeight
                            )
                    }
                }
                .padding(.horizontal, TVHomeMetrics.horizontalMargin)
            }
            .scrollClipDisabled()
        }
        .frame(height: TVHomeMetrics.railHeight, alignment: .top)
        .focusSection()
        .onChange(of: rail.rooms.map(\.id)) { _, _ in
            liveViewModel.roomList = rail.rooms
        }
    }
}

private struct TVHomeHeroLoadingContent: View {
    @Namespace private var focusScope

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(width: 180, height: 64)
            Spacer()
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.16))
                .frame(width: 640, height: 64)
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.10))
                .frame(width: 420, height: 34)
            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 230, height: 72)
            Spacer().frame(height: 54)
        }
        .padding(.horizontal, TVHomeMetrics.horizontalMargin)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .redacted(reason: .placeholder)
        .accessibilityLabel("首页内容加载中")
        .focusable()
        .prefersDefaultFocus(true, in: focusScope)
        .focusScope(focusScope)
    }
}

private struct TVHomeEmptyHeroContent: View {
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("首页内容暂不可用")
                .font(.largeTitle.weight(.bold))
            Text("内容由已安装插件提供，你仍可从收藏或平台页面继续浏览。")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button(action: retry) {
                if isRefreshing {
                    ProgressView()
                        .frame(width: 180, height: 64)
                } else {
                    Label("重新加载", systemImage: "arrow.clockwise")
                        .frame(width: 180, height: 64)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(isRefreshing)
            Spacer()
        }
        .padding(.horizontal, TVHomeMetrics.horizontalMargin)
    }
}

private struct TVHomeFailureCard: View {
    let pluginNames: [String]
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("部分内容加载失败")
                    .font(.headline)
                Text(pluginNames.joined(separator: "、"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("重试", action: retry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(isRefreshing)
        }
        .padding(28)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct TVHomeBannerInfoOverlay: View {
    let entry: HomeBannerEntry
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("来自 \(entry.pluginDisplayName)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(entry.banner.title)
                    .font(.largeTitle.weight(.bold))
                if let subtitle = entry.banner.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                if let badge = entry.banner.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Button("返回", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 12)
            }
            .padding(54)
            .frame(width: 920, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .onExitCommand(perform: dismiss)
    }
}

private struct TVHomeCategoryView: View {
    let route: PluginHomeCategoryRoute
    private let appViewModel: AppState

    @State private var model: PluginHomeCategoryModel
    @State private var liveViewModel: LiveViewModel

    init(route: PluginHomeCategoryRoute, appViewModel: AppState) {
        self.route = route
        self.appViewModel = appViewModel
        _model = State(initialValue: PluginHomeCategoryModel(route: route))
        _liveViewModel = State(
            initialValue: LiveViewModel(
                roomListType: .live,
                liveType: route.liveType,
                appViewModel: appViewModel,
                shouldLoadData: false
            )
        )
    }

    private let columns = Array(
        repeating: GridItem(.fixed(380), spacing: 50),
        count: 4
    )

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                Text(route.title)
                    .font(.largeTitle.weight(.bold))
                    .padding(.horizontal, TVHomeMetrics.horizontalMargin)

                if let errorMessage = model.errorMessage, model.rooms.isEmpty {
                    VStack(spacing: 22) {
                        Text(errorMessage)
                            .font(.title3)
                        Button("重新加载") {
                            Task { await model.load(refresh: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 440)
                } else {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 52) {
                        ForEach(Array(model.rooms.enumerated()), id: \.element.id) { index, room in
                            LiveCardView(index: index, currentLiveModel: room)
                                .environment(liveViewModel)
                                .environment(appViewModel)
                                .frame(width: 370, height: 280)
                            .task {
                                if index >= model.rooms.count - 4 {
                                    await model.loadMore()
                                }
                            }
                        }

                        if model.isLoading {
                            ProgressView()
                                .scaleEffect(1.6)
                                .frame(width: 370, height: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, TVHomeMetrics.horizontalMargin)
                    .focusSection()
                }

                Color.clear.frame(height: 100)
            }
            .padding(.top, 50)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationTitle(route.title)
        .task {
            if model.rooms.isEmpty {
                await model.load(refresh: true)
            }
        }
        .onChange(of: model.rooms.map(\.id)) { _, _ in
            liveViewModel.roomList = model.rooms
        }
    }
}

@MainActor
@Observable
private final class TVHomePlaybackCoordinator {
    private let appViewModel: AppState

    var roomInfoViewModel: RoomInfoViewModel?
    var isPresented = false
    var showToast = false
    var toastTitle = ""
    var toastSuccess = false
    var toastOptions = SimpleToastOptions(alignment: .topLeading, hideAfter: 1.8)

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
    }

    func open(room: LiveModel, rooms: [LiveModel], mode: TVHomePlaybackMode) {
        if mode == .favorite, !PlatformHostBehavior.isPlayableRoom(room) {
            validateFavoriteAndOpen(room: room, rooms: rooms)
            return
        }
        present(room: room, rooms: rooms, mode: mode)
    }

    private func validateFavoriteAndOpen(room: LiveModel, rooms: [LiveModel]) {
        Task {
            do {
                let state = try await ApiManager.getCurrentRoomLiveState(
                    roomId: room.roomId,
                    userId: room.userId,
                    liveType: room.liveType
                )
                var updatedRoom = room
                updatedRoom.liveState = state.rawValue
                guard PlatformHostBehavior.isPlayableRoom(updatedRoom) else {
                    show(success: false, title: "主播已经下播")
                    return
                }
                let updatedRooms = rooms.map { $0 == room ? updatedRoom : $0 }
                present(room: updatedRoom, rooms: updatedRooms, mode: .favorite)
            } catch {
                show(success: false, title: "状态获取失败，请稍后再试")
            }
        }
    }

    private func present(room: LiveModel, rooms: [LiveModel], mode: TVHomePlaybackMode) {
        if !appViewModel.historyViewModel.watchList.contains(room) {
            appViewModel.historyViewModel.watchList.insert(room, at: 0)
        }
        let roomType: LiveRoomListType = mode == .favorite ? .favorite : .live
        let infoModel = RoomInfoViewModel(
            currentRoom: room,
            appViewModel: appViewModel,
            enterFromLive: mode == .direct,
            roomType: roomType
        )
        infoModel.roomList = rooms
        roomInfoViewModel = infoModel
        isPresented = true
    }

    private func show(success: Bool, title: String) {
        toastSuccess = success
        toastTitle = title
        showToast = true
    }
}

private struct TVHomePlaybackPresentationModifier: ViewModifier {
    let coordinator: TVHomePlaybackCoordinator

    func body(content: Content) -> some View {
        @Bindable var coordinator = coordinator

        content
            .fullScreenCover(isPresented: $coordinator.isPresented) {
                if let roomInfoViewModel = coordinator.roomInfoViewModel {
                    DetailPlayerView { isPresented, _ in
                        coordinator.isPresented = isPresented
                    }
                    .environment(roomInfoViewModel)
                    .environment(roomInfoViewModel.appViewModel)
                    .ignoresSafeArea()
                    .frame(width: 1920, height: 1080)
                }
            }
            .simpleToast(isPresented: $coordinator.showToast, options: coordinator.toastOptions) {
                Label(
                    coordinator.toastTitle,
                    systemImage: coordinator.toastSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.headline)
                .padding(20)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
    }
}

private extension View {
    func tvHomePlaybackPresentation(_ coordinator: TVHomePlaybackCoordinator) -> some View {
        modifier(TVHomePlaybackPresentationModifier(coordinator: coordinator))
    }
}

private enum TVHomeMetrics {
    static let horizontalMargin: CGFloat = 92
    static let railHeight: CGFloat = 438
    static let cardWidth: CGFloat = 420
    static let cardCoverHeight: CGFloat = 236
    static let cardHeight: CGFloat = 316
    static let cardSpacing: CGFloat = 36
}

private enum TVHomePlaybackMode: Equatable {
    case direct
    case favorite
}

private struct TVHomeRailData: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let rooms: [LiveModel]
    let route: PluginHomeCategoryRoute?
    let playbackMode: TVHomePlaybackMode
}

private struct TVHomeRefreshTrigger: Hashable {
    let installedPluginIds: [String]
    let availabilityConfirmed: Bool
    let catalogRevision: UInt
}

private struct TVHomeAutoplayTrigger: Hashable {
    let bannerIDs: [String]
    let selectedBannerID: String?
    let scenePhase: ScenePhase
    let reduceMotion: Bool
    let heroHasFocus: Bool
    let isPresentingInfo: Bool
}
