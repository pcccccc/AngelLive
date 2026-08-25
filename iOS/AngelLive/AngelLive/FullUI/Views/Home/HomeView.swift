//
//  HomeView.swift
//  AngelLive
//
//  插件驱动的 iOS 首页：焦点内容、本地收藏和插件直播分区。
//

import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct HomeView: View {
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.presentToast) private var presentToast
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel = HomeViewModel()
    @State private var navigationState = LiveRoomNavigationState()
    @State private var homeHeaderMinY: CGFloat = 0
    @State private var homeSectionPositions: [String: HomeNavigationSectionPosition] = [:]
    @Namespace private var roomTransitionNamespace

    var body: some View {
        playerPresentation
            .task(id: HomeFeedRefreshTrigger(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )) {
                async let feedRefresh: Void = viewModel.refresh(
                    installedPluginIds: pluginAvailability.installedPluginIds,
                    availabilityConfirmed: pluginAvailability.hasCheckedAvailability
                )
                async let favoriteRefresh: Void = refreshFavoritesIfNeeded()
                _ = await (feedRefresh, favoriteRefresh)
            }
    }
}

private extension HomeView {
    @ViewBuilder
    var playerPresentation: some View {
        if #available(iOS 18.0, *) {
            homeNavigation
                .fullScreenCover(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        } else {
            homeNavigation
                .navigationDestination(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        }
    }

    var homeNavigation: some View {
        GeometryReader { geometry in
            NavigationStack {
                homeScrollView(
                    containerWidth: geometry.size.width,
                    topSafeAreaInset: geometry.safeAreaInsets.top
                )
            }
        }
    }

    func homeScrollView(containerWidth: CGFloat, topSafeAreaInset: CGFloat) -> some View {
        let featuredCardWidth = featuredRoomCardWidth(for: containerWidth)
        let compactCardWidth = compactRoomCardWidth(for: containerWidth)
        let navigationTitle = homeNavigationTitle(
            activationY: topSafeAreaInset + HomeNavigationMetrics.barHeight
        )
        let navigationProgress = homeNavigationProgress
        let hasConfiguredHomeSources = !pluginAvailability.installedPluginIds.isEmpty
        let isAwaitingFirstContent = viewModel.bannerEntries.isEmpty
            && viewModel.sectionEntries.isEmpty
            && (
                !pluginAvailability.hasCheckedAvailability
                    || pluginAvailability.isChecking
                    || (hasConfiguredHomeSources && !viewModel.hasRestoredCache)
                    || (hasConfiguredHomeSources && !viewModel.hasLoaded)
            )

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !viewModel.bannerEntries.isEmpty {
                    HomeHeroCarousel(
                        entries: viewModel.bannerEntries,
                        containerWidth: containerWidth,
                        topSafeAreaInset: topSafeAreaInset,
                        onOpenRoom: { room in
                            openRoom(room, rooms: [room], mode: .direct)
                        }
                    )
                    .trackHomeHeaderPosition(updateHomeHeaderPosition)
                } else if isAwaitingFirstContent {
                    HomeHeroLoadingCard(
                        containerWidth: containerWidth,
                        topSafeAreaInset: topSafeAreaInset
                    )
                    .trackHomeHeaderPosition(updateHomeHeaderPosition)
                } else {
                    HomeCompactHeader(
                        platformOptions: viewModel.platformOptions,
                        selectedPluginId: viewModel.selectedPluginId,
                        topSafeAreaInset: topSafeAreaInset,
                        onSelectPlatform: viewModel.selectPlatform
                    )
                    .trackHomeHeaderPosition(updateHomeHeaderPosition)
                }

                if !favoriteModel.roomList.isEmpty {
                    HomeFavoriteSection(
                        rooms: Array(favoriteModel.roomList.prefix(10)),
                        isRefreshing: favoriteModel.isCloudSyncing,
                        cardWidth: featuredCardWidth,
                        namespace: roomTransitionNamespace,
                        onSelect: { room, rooms in
                            openRoom(room, rooms: rooms, mode: .local)
                        }
                    )
                    .padding(.top, -44)
                    .trackHomeNavigationSection(
                        id: HomeNavigationSectionID.favorites,
                        title: "我的收藏",
                        onPositionChange: updateHomeSectionPosition
                    )
                }

                if let firstPluginSection = viewModel.sectionEntries.first,
                   !firstPluginSection.section.items.isEmpty {
                    HomePluginRoomSection(
                        entry: firstPluginSection,
                        cardWidth: featuredCardWidth,
                        namespace: roomTransitionNamespace,
                        onSelect: { room, rooms in
                            openRoom(room, rooms: rooms, mode: .direct)
                        }
                    )
                    .padding(.top, favoriteModel.roomList.isEmpty ? -44 : 0)
                    .trackHomeNavigationSection(
                        id: HomeNavigationSectionID.plugin(firstPluginSection),
                        title: firstPluginSection.section.title,
                        onPositionChange: updateHomeSectionPosition
                    )
                }

                ForEach(viewModel.sectionEntries.dropFirst()) { entry in
                    HomePluginRoomSection(
                        entry: entry,
                        cardWidth: compactCardWidth,
                        namespace: roomTransitionNamespace,
                        onSelect: { room, rooms in
                            openRoom(room, rooms: rooms, mode: .direct)
                        }
                    )
                    .trackHomeNavigationSection(
                        id: HomeNavigationSectionID.plugin(entry),
                        title: entry.section.title,
                        onPositionChange: updateHomeSectionPosition
                    )
                }

                if isAwaitingFirstContent {
                    HomeRoomSectionsLoading(
                        featuredCardWidth: featuredCardWidth,
                        compactCardWidth: compactCardWidth
                    )
                    .padding(.top, favoriteModel.roomList.isEmpty ? -44 : 0)
                }

                if viewModel.hasLoaded,
                   pluginAvailability.hasCheckedAvailability,
                   !pluginAvailability.isChecking,
                   pluginAvailability.installedPluginIds.isEmpty {
                    HomeConfigurationGuide()
                }

                if !viewModel.failedPluginNames.isEmpty {
                    HomeFeedFailureCard(
                        pluginNames: viewModel.failedPluginNames,
                        isRefreshing: viewModel.isRefreshing,
                        retry: refreshHome
                    )
                }
            }
            .padding(.bottom, 128)
        }
        .background(AppConstants.Colors.primaryBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !viewModel.bannerEntries.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    HomePlatformPicker(
                        options: viewModel.platformOptions,
                        selectedPluginId: viewModel.selectedPluginId,
                        presentation: .toolbar,
                        onSelect: viewModel.selectPlatform
                    )
                    .fixedSize()
                }
            }

            ToolbarItem(placement: .principal) {
                Text(navigationTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(navigationProgress)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: navigationTitle)
                    .accessibilityHidden(navigationProgress < 0.5)
            }
        }
        .toolbarBackground(
            AppConstants.Colors.primaryBackground.opacity(
                HomeNavigationMetrics.backgroundOpacity * navigationProgress
            ),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .refreshable {
            await refreshAll()
        }
        .navigationDestination(for: HomeCategoryRoute.self) { route in
            HomeCategoryView(
                route: route,
                navigationState: navigationState,
                namespace: roomTransitionNamespace
            )
        }
    }

    func featuredRoomCardWidth(for containerWidth: CGFloat) -> CGFloat {
        min(max((containerWidth - 52) / 1.72, 164), 300)
    }

    func compactRoomCardWidth(for containerWidth: CGFloat) -> CGFloat {
        min(max((containerWidth - 56) / 2.05, 156), 240)
    }

    var homeNavigationProgress: CGFloat {
        min(max(-homeHeaderMinY / HomeNavigationMetrics.fadeDistance, 0), 1)
    }

    func homeNavigationTitle(activationY: CGFloat) -> String {
        let visibleSectionIDs = Set(
            viewModel.sectionEntries.map(HomeNavigationSectionID.plugin)
                + (favoriteModel.roomList.isEmpty ? [] : [HomeNavigationSectionID.favorites])
        )

        return homeSectionPositions.values
            .filter { visibleSectionIDs.contains($0.id) && $0.minY <= activationY }
            .max(by: { $0.minY < $1.minY })?
            .title ?? "首页"
    }

    func updateHomeHeaderPosition(_ minY: CGFloat) {
        // Positive values are pull-down overscroll. The navigation and picker
        // docking states are both clamped to zero there, so publishing every
        // positive frame would only rebuild the horizontal carousel while its
        // compositor stretch is running, which presents as image jitter.
        let navigationRelevantMinY = min(minY, 0)
        guard abs(homeHeaderMinY - navigationRelevantMinY) >= 0.25 else { return }
        homeHeaderMinY = navigationRelevantMinY
    }

    func updateHomeSectionPosition(id: String, title: String, minY: CGFloat) {
        let position = HomeNavigationSectionPosition(id: id, title: title, minY: minY)
        guard let previous = homeSectionPositions[id] else {
            homeSectionPositions[id] = position
            return
        }
        guard previous.title != title || abs(previous.minY - minY) >= 0.5 else { return }
        homeSectionPositions[id] = position
    }

    var playerPresentedBinding: Binding<Bool> {
        Binding(
            get: { navigationState.showPlayer },
            set: { isPresented in
                if !isPresented { navigationState.dismiss() }
            }
        )
    }

    @ViewBuilder
    var playerDestination: some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
            .modifier(
                ZoomTransitionModifier(
                    sourceID: room.roomId,
                    namespace: roomTransitionNamespace
                )
            )
            .toolbar(.hidden, for: .tabBar)
        }
    }

    func openRoom(_ room: LiveModel, rooms: [LiveModel], mode: HomeRoomOpenMode) {
        switch mode {
        case .direct:
            navigationState.navigate(to: room, categoryRooms: rooms)
        case .local:
            if room.liveState == LiveState.close.rawValue {
                presentToast(ToastValue(icon: Image(systemName: "tv.slash"), message: "主播已下播"))
            } else {
                navigationState.navigate(to: room, categoryRooms: rooms)
            }
        }
    }

    @MainActor
    func refreshFavoritesIfNeeded() async {
        if favoriteModel.shouldSync() {
            await favoriteModel.syncWithActor()
        }
    }

    func refreshHome() {
        Task {
            await viewModel.refresh(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )
        }
    }

    @MainActor
    func refreshAll() async {
        await viewModel.refresh(
            installedPluginIds: pluginAvailability.installedPluginIds,
            availabilityConfirmed: pluginAvailability.hasCheckedAvailability
        )
        await favoriteModel.syncWithActor()
    }
}

private enum HomeRoomOpenMode {
    case direct
    case local
}

private struct HomeFeedRefreshTrigger: Hashable {
    let installedPluginIds: [String]
    let availabilityConfirmed: Bool
}

private enum HomeNavigationMetrics {
    static let barHeight: CGFloat = 44
    static let fadeDistance: CGFloat = 96
    static let backgroundOpacity: CGFloat = 0.96
}

private enum HomeNavigationSectionID {
    static let favorites = "favorites"

    static func plugin(_ entry: HomeSectionEntry) -> String {
        "plugin:\(entry.pluginId):\(entry.id)"
    }
}

private struct HomeNavigationSectionPosition: Equatable {
    let id: String
    let title: String
    let minY: CGFloat
}

private extension View {
    func trackHomeHeaderPosition(
        _ onPositionChange: @escaping (CGFloat) -> Void
    ) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .scrollView(axis: .vertical)).minY
        } action: { minY in
            onPositionChange(minY)
        }
    }

    func trackHomeNavigationSection(
        id: String,
        title: String,
        onPositionChange: @escaping (String, String, CGFloat) -> Void
    ) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .scrollView(axis: .vertical)).minY
        } action: { minY in
            onPositionChange(id, title, minY)
        }
    }
}

private struct HomeRoomPresentation: Identifiable {
    let id: String
    let room: LiveModel
    let detail: String

    init(id: String? = nil, room: LiveModel, detail: String) {
        self.id = id ?? room.id
        self.room = room
        self.detail = detail
    }
}

private struct HomeFavoriteSection: View {
    let rooms: [LiveModel]
    let isRefreshing: Bool
    let cardWidth: CGFloat
    let namespace: Namespace.ID
    let onSelect: (LiveModel, [LiveModel]) -> Void

    var body: some View {
        HomeHorizontalRoomSection(
            title: "我的收藏",
            subtitle: isRefreshing ? "状态更新中" : nil,
            items: rooms.map { HomeRoomPresentation(room: $0, detail: $0.userName) },
            cardWidth: cardWidth,
            emptyMessage: "收藏常看的直播间，之后可以从这里快速进入",
            emptySystemImage: "heart",
            trailing: {
                NavigationLink {
                    FavoriteView(embeddedInNavigationStack: true)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HomeSeeAllLabel()
                }
            },
            onSelect: { room in onSelect(room, rooms) },
            namespace: namespace
        )
    }
}

private struct HomePluginRoomSection: View {
    let entry: HomeSectionEntry
    let cardWidth: CGFloat
    let namespace: Namespace.ID
    let onSelect: (LiveModel, [LiveModel]) -> Void

    private var rooms: [LiveModel] {
        entry.section.items.map(\.room)
    }

    private var subtitle: String {
        let source = entry.section.personalized
            ? "为你推荐 · 来自 \(entry.pluginDisplayName)"
            : "来自 \(entry.pluginDisplayName)"
        guard let subtitle = entry.section.subtitle, !subtitle.isEmpty else {
            return source
        }
        return "\(subtitle) · \(source)"
    }

    private var route: HomeCategoryRoute? {
        entry.section.seeAllTarget.map {
            HomeCategoryRoute(
                pluginId: entry.pluginId,
                liveType: entry.liveType,
                category: $0,
                fallbackTitle: entry.section.title
            )
        }
    }

    var body: some View {
        HomeHorizontalRoomSection(
            title: entry.section.title,
            subtitle: subtitle,
            items: entry.section.items.map {
                HomeRoomPresentation(
                    id: $0.id,
                    room: $0.room,
                    detail: $0.reason ?? $0.room.userName
                )
            },
            cardWidth: cardWidth,
            trailing: {
                if let route {
                    NavigationLink(value: route) {
                        HomeSeeAllLabel()
                    }
                }
            },
            onSelect: { room in onSelect(room, rooms) },
            namespace: namespace
        )
    }
}

private struct HomeHorizontalRoomSection<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let items: [HomeRoomPresentation]
    let cardWidth: CGFloat
    let emptyMessage: String?
    let emptySystemImage: String
    let trailing: Trailing
    let onSelect: (LiveModel) -> Void
    let namespace: Namespace.ID

    init(
        title: String,
        subtitle: String?,
        items: [HomeRoomPresentation],
        cardWidth: CGFloat,
        emptyMessage: String? = nil,
        emptySystemImage: String = "rectangle.stack",
        @ViewBuilder trailing: () -> Trailing,
        onSelect: @escaping (LiveModel) -> Void,
        namespace: Namespace.ID
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.cardWidth = cardWidth
        self.emptyMessage = emptyMessage
        self.emptySystemImage = emptySystemImage
        self.trailing = trailing()
        self.onSelect = onSelect
        self.namespace = namespace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HomeSectionHeader(title: title, subtitle: subtitle) {
                trailing
            }

            if items.isEmpty, let emptyMessage {
                HomeEmptyRail(message: emptyMessage, systemImage: emptySystemImage)
            } else {
                roomScroll
            }
        }
    }

    private var roomScroll: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: AppConstants.Spacing.md) {
                ForEach(items) { item in
                    Button {
                        onSelect(item.room)
                    } label: {
                        LiveRoomCard(
                            room: item.room,
                            width: cardWidth,
                            liveCheckMode: .none,
                            subtitle: item.detail,
                            disableTapGesture: true
                        )
                        .environment(\.roomTransitionNamespace, namespace)
                    }
                    .buttonStyle(HomeCardButtonStyle())
                    .accessibilityLabel("\(item.room.roomTitle)，\(item.room.userName)")
                    .accessibilityHint("打开播放页")
                }
            }
            .padding(.horizontal, AppConstants.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppConstants.Spacing.md) {
            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppConstants.Colors.primaryText)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppConstants.Spacing.sm)
            trailing
        }
        .padding(.horizontal, AppConstants.Spacing.xl)
    }
}

private struct HomeEmptyRail: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppConstants.Colors.tertiaryText)
                .frame(width: 34, height: 34)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppConstants.Spacing.xl)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeSeeAllLabel: View {
    var body: some View {
        HStack(spacing: AppConstants.Spacing.xs) {
            Text("全部")
            Image(systemName: "chevron.right")
                .font(.caption.bold())
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppConstants.Colors.secondaryText)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeHeroCarousel: View {
    let entries: [HomeBannerEntry]
    let containerWidth: CGFloat
    let topSafeAreaInset: CGFloat
    let onOpenRoom: (LiveModel) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPageID: String?
    @State private var loopCorrectionTask: Task<Void, Never>?

    private let pageInset: CGFloat = 0
    private let cardSpacing: CGFloat = 0

    private var viewportWidth: CGFloat {
        max(containerWidth, 280)
    }

    private var cardWidth: CGFloat {
        viewportWidth
    }

    private var cardHeight: CGFloat {
        min(max(viewportWidth * 0.9, 336), 500)
    }

    private var loopPages: [HomeHeroLoopPage] {
        guard entries.count > 1,
              let first = entries.first,
              let last = entries.last else {
            return entries.map(HomeHeroLoopPage.real)
        }
        return [HomeHeroLoopPage.leadingClone(last)]
            + entries.map(HomeHeroLoopPage.real)
            + [HomeHeroLoopPage.trailingClone(first)]
    }

    private var selectedBannerID: String? {
        guard let selectedPageID else { return nil }
        return loopPages.first(where: { $0.id == selectedPageID })?.entry.id
    }

    var body: some View {
        let resolvedCardHeight = cardHeight
        let pullDownEnabled = !reduceMotion

        ZStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                HStack(spacing: cardSpacing) {
                    ForEach(loopPages) { page in
                        heroPage(for: page.entry)
                            .frame(width: cardWidth, height: cardHeight)
                            .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $selectedPageID)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .frame(width: viewportWidth, height: cardHeight)
            .background(AppConstants.Colors.primaryBackground)

            if entries.count > 1 {
                HomeHeroPageIndicator(entries: entries, selectedID: selectedBannerID)
                    .padding(.bottom, 54)
            }
        }
        .frame(height: cardHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .visualEffect { content, proxy in
            content.scaleEffect(
                pullScale(
                    for: proxy,
                    cardHeight: resolvedCardHeight,
                    pullDownEnabled: pullDownEnabled
                ),
                anchor: .bottom
            )
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: entries.map(\.id)) { _, _ in normalizeSelection() }
        .onChange(of: selectedPageID) { _, newValue in
            scheduleLoopCorrection(for: newValue)
        }
        .onDisappear {
            loopCorrectionTask?.cancel()
        }
        .task(id: autoplayTaskID) {
            await runAutoplayIfNeeded()
        }
    }

    private var autoplayTaskID: String {
        "\(entries.map(\.id).joined(separator: "|"))::\(selectedPageID ?? "")::\(scenePhase)::\(reduceMotion)"
    }

    nonisolated private func pullScale(
        for proxy: GeometryProxy,
        cardHeight: CGFloat,
        pullDownEnabled: Bool
    ) -> CGFloat {
        guard pullDownEnabled else { return 1 }
        let pullDistance = max(
            proxy.frame(in: .scrollView(axis: .vertical)).minY,
            0
        )
        // Scaling from the bottom edge by exactly pullDistance / height keeps
        // the transformed top edge at y == 0 for the full overscroll range.
        // Capping the scale would reintroduce a gap once the pull exceeded the
        // cap, which made an aggressively pulled banner appear detached.
        return 1 + pullDistance / max(cardHeight, 1)
    }

    private func normalizeSelection() {
        loopCorrectionTask?.cancel()
        guard !entries.isEmpty else {
            selectedPageID = nil
            return
        }

        if let selectedBannerID,
           entries.contains(where: { $0.id == selectedBannerID }) {
            selectedPageID = HomeHeroLoopPage.realID(for: selectedBannerID)
        } else {
            selectedPageID = HomeHeroLoopPage.realID(for: entries[0].id)
        }
    }

    private func scheduleLoopCorrection(for pageID: String?) {
        loopCorrectionTask?.cancel()
        guard entries.count > 1, let pageID else { return }

        let destinationID: String?
        if pageID == HomeHeroLoopPage.leadingCloneID(for: entries.last?.id ?? "") {
            destinationID = entries.last.map { HomeHeroLoopPage.realID(for: $0.id) }
        } else if pageID == HomeHeroLoopPage.trailingCloneID(for: entries.first?.id ?? "") {
            destinationID = entries.first.map { HomeHeroLoopPage.realID(for: $0.id) }
        } else {
            destinationID = nil
        }

        guard let destinationID else { return }
        loopCorrectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(480))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedPageID = destinationID
            }
        }
    }

    @MainActor
    private func runAutoplayIfNeeded() async {
        guard entries.count > 1, scenePhase == .active, !reduceMotion else { return }

        do {
            try await Task.sleep(for: .seconds(6))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        let pages = loopPages
        guard let currentIndex = pages.firstIndex(where: { $0.id == selectedPageID }) else {
            normalizeSelection()
            return
        }
        let nextIndex = pages.index(after: currentIndex) == pages.endIndex
            ? pages.index(after: pages.startIndex)
            : pages.index(after: currentIndex)
        withAnimation(.smooth(duration: 0.45)) {
            selectedPageID = pages[nextIndex].id
        }
    }

    @ViewBuilder
    private func heroPage(for entry: HomeBannerEntry) -> some View {
        heroDestination(for: entry)
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
    }

    @ViewBuilder
    private func heroDestination(for entry: HomeBannerEntry) -> some View {
        switch entry.banner.target {
        case .room(let room):
            Button { onOpenRoom(room) } label: {
                HomeHeroCard(
                    entry: entry,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    pageInset: pageInset,
                    cardSpacing: cardSpacing,
                    topSafeAreaInset: topSafeAreaInset
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开播放页")
        case .category(let category):
            NavigationLink(
                value: HomeCategoryRoute(
                    pluginId: entry.pluginId,
                    liveType: entry.liveType,
                    category: category,
                    fallbackTitle: entry.banner.title
                )
            ) {
                HomeHeroCard(
                    entry: entry,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    pageInset: pageInset,
                    cardSpacing: cardSpacing,
                    topSafeAreaInset: topSafeAreaInset
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开分类")
        }
    }
}

private struct HomeHeroLoopPage: Identifiable {
    let id: String
    let entry: HomeBannerEntry

    static func real(_ entry: HomeBannerEntry) -> Self {
        Self(id: realID(for: entry.id), entry: entry)
    }

    static func leadingClone(_ entry: HomeBannerEntry) -> Self {
        Self(id: leadingCloneID(for: entry.id), entry: entry)
    }

    static func trailingClone(_ entry: HomeBannerEntry) -> Self {
        Self(id: trailingCloneID(for: entry.id), entry: entry)
    }

    static func realID(for bannerID: String) -> String {
        "home-hero-real::\(bannerID)"
    }

    static func leadingCloneID(for bannerID: String) -> String {
        "home-hero-leading::\(bannerID)"
    }

    static func trailingCloneID(for bannerID: String) -> String {
        "home-hero-trailing::\(bannerID)"
    }
}

private struct HomeHeroCard: View {
    let entry: HomeBannerEntry
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let pageInset: CGFloat
    let cardSpacing: CGFloat
    let topSafeAreaInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The page remains fixed at the viewport width. Only its bitmap moves,
        // driven by the page's position in the horizontal scroll view. A small
        // uniform zoom supplies safe overscan for a full-width immersive banner.
        let imageScale: CGFloat = reduceMotion ? 1 : 1.1
        let parallaxTravel = cardWidth * (imageScale - 1) / 2

        ZStack {
            HomeHeroRemoteImage(
                url: preferredImageURL,
                fallbackURL: fallbackImageURL,
                targetSize: CGSize(width: cardWidth, height: cardHeight),
                presentationScale: imageScale
            )
                .frame(width: cardWidth, height: cardHeight)
                .visualEffect { content, proxy in
                    content
                        .scaleEffect(imageScale)
                        .offset(
                            x: parallaxOffset(
                                for: proxy,
                                pageInset: pageInset,
                                pageStride: cardWidth + cardSpacing,
                                travel: parallaxTravel
                            )
                        )
                }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.28), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .black.opacity(0.12), location: 0.56),
                    .init(color: .black.opacity(0.32), location: 0.68),
                    .init(color: AppConstants.Colors.primaryBackground.opacity(0.18), location: 0.76),
                    .init(color: AppConstants.Colors.primaryBackground.opacity(0.72), location: 0.9),
                    .init(color: AppConstants.Colors.primaryBackground, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 6) {
                Spacer(minLength: max(cardHeight * 0.45, 150))
                Text(heroTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .shadow(color: .black.opacity(0.46), radius: 10, y: 3)

                if let streamerName {
                    HomeHeroStreamerIdentity(
                        name: streamerName,
                        avatarURL: streamerAvatarURL
                    )
                } else if let heroSubtitle {
                    Text(heroSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }

                Spacer()
                    .frame(height: max(cardHeight * 0.18, 62))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppConstants.Spacing.xxl)

        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var heroTitle: String {
        if case .room(let room) = entry.banner.target,
           !room.roomTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return room.roomTitle
        }
        return entry.banner.title
    }

    private var streamerName: String? {
        guard case .room(let room) = entry.banner.target else { return nil }
        let value = room.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var streamerAvatarURL: URL? {
        guard case .room(let room) = entry.banner.target else { return nil }
        return URL(string: room.userHeadImg)
    }

    private var heroSubtitle: String? {
        let value = entry.banner.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private var accessibilityDescription: String {
        if let streamerName {
            return "\(heroTitle)，主播 \(streamerName)"
        }
        return [heroTitle, heroSubtitle]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    /// Room feeds often expose a full-resolution live cover while their
    /// promotional banner field is only a small web thumbnail. Prefer the room
    /// cover and retain the promotional artwork as a network fallback.
    private var preferredImageURL: URL? {
        guard case .room(let room) = entry.banner.target,
              !room.roomCover.isEmpty,
              let roomCoverURL = URL(string: room.roomCover)
        else {
            return entry.banner.imageURL
        }

        return roomCoverURL
    }

    private var fallbackImageURL: URL? {
        guard preferredImageURL != entry.banner.imageURL else { return nil }
        return entry.banner.imageURL
    }

    nonisolated private func parallaxOffset(
        for proxy: GeometryProxy,
        pageInset: CGFloat,
        pageStride: CGFloat,
        travel: CGFloat
    ) -> CGFloat {
        let pageMinX = proxy.frame(
            in: .scrollView(axis: .horizontal)
        ).minX - pageInset
        let pageProgress = min(
            max(pageMinX / max(pageStride, 1), -1),
            1
        )
        return -pageProgress * travel
    }
}

private struct HomeHeroStreamerIdentity: View {
    let name: String
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            KFImage(avatarURL)
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 64, height: 64)))
                .placeholder {
                    Circle()
                        .fill(.white.opacity(0.16))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                }
                .fade(duration: 0.16)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.42), lineWidth: 0.5)
                }

            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .shadow(color: .black.opacity(0.34), radius: 6, y: 2)
    }
}

private enum HomePlatformPickerPresentation: Equatable {
    case content
    case toolbar
}

private struct HomePlatformPicker: View {
    let options: [HomePlatformOption]
    let selectedPluginId: String?
    var presentation: HomePlatformPickerPresentation = .content
    let onSelect: (String?) -> Void

    private var selectedOption: HomePlatformOption? {
        guard let selectedPluginId else { return nil }
        return options.first { $0.pluginId == selectedPluginId }
    }

    private var selectedName: String {
        selectedOption?.displayName
            ?? options.first.map { options.count == 1 ? $0.displayName : "全部平台" }
            ?? "平台"
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *), presentation == .toolbar {
                platformMenu
                    .buttonStyle(.plain)
            } else {
                platformMenu
            }
        }
        .menuOrder(.fixed)
        .accessibilityLabel("切换直播平台，当前为\(selectedName)")
        .accessibilityHint("显示所有支持首页的平台")
    }

    private var platformMenu: some View {
        Menu {
            if options.count > 1 {
                Button { onSelect(nil) } label: {
                    Label {
                        Text("全部平台")
                    } icon: {
                        HomePlatformIconStack(options: options, iconSize: 18)
                    }
                }
                Divider()
            }

            ForEach(options) { option in
                Button { onSelect(option.pluginId) } label: {
                    Label {
                        Text(option.displayName)
                    } icon: {
                        HomePlatformIcon(option: option, size: 18)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let selectedOption {
                    HomePlatformIcon(option: selectedOption, size: 24)
                } else {
                    HomePlatformIconStack(options: options, iconSize: 22)
                }

                Text(selectedName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 7)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .homePlatformPickerLabelBackground()
        }
    }
}

private struct HomePlatformIcon: View {
    let option: HomePlatformOption
    let size: CGFloat

    var body: some View {
        Group {
            if let image = PlatformIconProvider.tabImage(for: option.liveType) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Circle()
                    .fill(.secondary.opacity(0.16))
                    .overlay {
                        Text(String(option.displayName.prefix(1)))
                            .font(.system(size: size * 0.46, weight: .bold))
                            .foregroundStyle(.primary)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct HomePlatformIconStack: View {
    let options: [HomePlatformOption]
    let iconSize: CGFloat

    private var visibleOptions: [HomePlatformOption] {
        Array(options.prefix(3))
    }

    var body: some View {
        HStack(spacing: -iconSize * 0.28) {
            ForEach(visibleOptions) { option in
                HomePlatformIcon(option: option, size: iconSize)
                    .background(.background, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.58), lineWidth: 0.75)
                    }
            }
        }
        .frame(minWidth: iconSize)
        .accessibilityHidden(true)
    }
}

private struct HomeHeroRemoteImage: View {
    let url: URL?
    let fallbackURL: URL?
    let targetSize: CGSize
    let presentationScale: CGFloat

    @Environment(\.displayScale) private var displayScale

    /// Kingfisher's downsampler uses the largest requested dimension. Banner
    /// sources are normally 16:9, while the immersive hero is much taller, so
    /// size the decode for the vertical crop instead of just the view width.
    /// The extra presentation scale preserves detail during parallax overscan.
    private var downsamplingSize: CGSize {
        let expectedLandscapeAspectRatio: CGFloat = 16 / 9
        let requiredSourceWidth = targetSize.height
            * expectedLandscapeAspectRatio
            * presentationScale
        let maximumPointDimension = max(
            targetSize.width * presentationScale,
            requiredSourceWidth
        )

        return CGSize(width: maximumPointDimension, height: maximumPointDimension)
    }

    var body: some View {
        if let url {
            KFImage(url)
                .setProcessor(DownsamplingImageProcessor(size: downsamplingSize))
                .scaleFactor(displayScale)
                .cacheOriginalImage()
                .alternativeSources(fallbackURL.map { [.network($0)] })
                .placeholder { placeholder }
                .fade(duration: 0.2)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .overlay {
                Image(systemName: "sparkles.tv.fill")
                    .font(.title2)
                    .foregroundStyle(AppConstants.Colors.placeholderText)
            }
    }
}

private struct HomeHeroPageIndicator: View {
    let entries: [HomeBannerEntry]
    let selectedID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(entries) { entry in
                Capsule()
                    .fill(
                        entry.id == selectedID
                            ? Color.white.opacity(0.96)
                            : Color.white.opacity(0.42)
                    )
                    .frame(width: entry.id == selectedID ? 18 : 5, height: 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .homeHeroGlassEffect()
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selectedID)
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func homePlatformPickerLabelBackground() -> some View {
        if #available(iOS 26.0, *) {
            // The toolbar supplies the single Liquid Glass container. Outside
            // the toolbar, Menu supplies its own interactive presentation.
            self
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func homeHeroGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}

private struct HomeHeroLoadingCard: View {
    let containerWidth: CGFloat
    let topSafeAreaInset: CGFloat

    private var viewportWidth: CGFloat {
        max(containerWidth, 280)
    }

    private var cardHeight: CGFloat {
        min(max(viewportWidth * 0.9, 336), 500)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppConstants.Colors.secondaryBackground,
                    AppConstants.Colors.tertiaryBackground,
                    AppConstants.Colors.primaryBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.secondary.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: cardHeight * 0.78
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.58),
                    .init(color: AppConstants.Colors.primaryBackground.opacity(0.74), location: 0.88),
                    .init(color: AppConstants.Colors.primaryBackground, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 116, height: 44)
                    Spacer(minLength: 0)
                }
                .padding(.top, topSafeAreaInset + AppConstants.Spacing.sm)
                .padding(.horizontal, AppConstants.Spacing.xl)

                Spacer(minLength: cardHeight * 0.36)

                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: min(viewportWidth * 0.58, 260), height: 28)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: min(viewportWidth * 0.34, 150), height: 14)

                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(Color.secondary.opacity(index == 0 ? 0.24 : 0.12))
                                .frame(width: index == 0 ? 22 : 7, height: 7)
                        }
                    }
                    .padding(.top, 12)
                }

                Spacer(minLength: cardHeight * 0.14)
            }
            .shimmering()
        }
        .frame(width: viewportWidth, height: cardHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在恢复首页内容")
    }
}

private struct HomeCompactHeader: View {
    let platformOptions: [HomePlatformOption]
    let selectedPluginId: String?
    let topSafeAreaInset: CGFloat
    let onSelectPlatform: (String?) -> Void

    var body: some View {
        HStack {
            if platformOptions.isEmpty {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                    Text("首页")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppConstants.Colors.primaryText)
                    Text("你的直播与播放入口")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
            } else {
                HomePlatformPicker(
                    options: platformOptions,
                    selectedPluginId: selectedPluginId,
                    onSelect: onSelectPlatform
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topSafeAreaInset + AppConstants.Spacing.sm)
        .padding(.horizontal, AppConstants.Spacing.xl)
        .padding(.bottom, AppConstants.Spacing.md)
        .background(AppConstants.Colors.primaryBackground)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeRoomSectionsLoading: View {
    let featuredCardWidth: CGFloat
    let compactCardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HomeRoomSectionLoading(cardWidth: featuredCardWidth)
            HomeRoomSectionLoading(cardWidth: compactCardWidth)
        }
        .accessibilityHidden(true)
    }
}

private struct HomeRoomSectionLoading: View {
    let cardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 96, height: 22)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 132, height: 12)
            }
            .padding(.horizontal, AppConstants.Spacing.xl)
            .shimmering()

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AppConstants.Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        LiveRoomCardSkeleton(width: cardWidth)
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.xl)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
    }
}

private struct HomeRemoteImage: View {
    let url: URL?
    let symbolName: String

    var body: some View {
        Group {
            if let url {
                KFImage(url)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 960, height: 540)))
                    .placeholder { placeholder }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .overlay {
                Image(systemName: symbolName)
                    .font(.title2)
                    .foregroundStyle(AppConstants.Colors.placeholderText)
            }
    }
}

private struct HomeFeedFailureCard: View {
    let pluginNames: [String]
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(AppConstants.Colors.warning)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text("部分首页内容暂不可用")
                    .font(.subheadline.weight(.semibold))
                Text(pluginNames.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Button("重试", action: retry)
                .disabled(isRefreshing)
                .frame(minHeight: 44)
        }
        .padding(AppConstants.Spacing.lg)
        .background(
            AppConstants.Colors.secondaryBackground,
            in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
        )
        .padding(.horizontal, AppConstants.Spacing.xl)
    }
}

private struct HomeConfigurationGuide: View {
    var body: some View {
        VStack(spacing: AppConstants.Spacing.lg) {
            Image(systemName: "square.stack.3d.up.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            VStack(spacing: AppConstants.Spacing.xs) {
                Text("配置你的首页")
                    .font(.headline)
                Text("添加内容源后，首页会展示它们提供的焦点内容和直播分区。")
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            NavigationLink {
                AdaptivePlatformView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                Text("前往配置")
                    .font(.headline)
                    .frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(AppConstants.Spacing.xxl)
        .background(
            AppConstants.Colors.secondaryBackground,
            in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl)
        )
        .padding(.horizontal, AppConstants.Spacing.xl)
    }
}

private struct HomeCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.18),
                value: configuration.isPressed
            )
    }
}

struct HomeCategoryRoute: Hashable {
    let pluginId: String
    let liveType: LiveType
    let categoryID: String
    let parentID: String
    let title: String
    let icon: String
    let biz: String?

    init(
        pluginId: String,
        liveType: LiveType,
        category: LiveCategoryModel,
        fallbackTitle: String
    ) {
        self.pluginId = pluginId
        self.liveType = liveType
        categoryID = category.id
        parentID = category.parentId
        title = category.title.isEmpty ? fallbackTitle : category.title
        icon = category.icon
        biz = category.biz
    }
}

private struct HomeCategoryView: View {
    let route: HomeCategoryRoute
    let navigationState: LiveRoomNavigationState
    let namespace: Namespace.ID
    @State private var model: HomeCategoryViewModel

    init(
        route: HomeCategoryRoute,
        navigationState: LiveRoomNavigationState,
        namespace: Namespace.ID
    ) {
        self.route = route
        self.navigationState = navigationState
        self.namespace = namespace
        _model = State(initialValue: HomeCategoryViewModel(route: route))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 154, maximum: 280), spacing: AppConstants.Spacing.lg)],
                spacing: AppConstants.Spacing.xl
            ) {
                ForEach(model.rooms) { room in
                    Button {
                        navigationState.navigate(to: room, categoryRooms: model.rooms)
                    } label: {
                        LiveRoomCard(
                            room: room,
                            width: model.cardWidth,
                            liveCheckMode: .none,
                            disableTapGesture: true
                        )
                        .environment(\.roomTransitionNamespace, namespace)
                    }
                    .buttonStyle(HomeCardButtonStyle())
                    .onAppear {
                        loadMoreIfNeeded(after: room)
                    }
                }
            }
            .padding(AppConstants.Spacing.xl)

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(AppConstants.Spacing.xl)
            } else if model.rooms.isEmpty {
                ContentUnavailableView(
                    "暂无直播间",
                    systemImage: "rectangle.stack.badge.questionmark",
                    description: Text(model.errorMessage ?? "当前分类暂时没有可显示的内容。")
                )
                .padding(.vertical, 80)
            }
        }
        .background(AppConstants.Colors.groupedBackground)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await model.load(refresh: true) }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            model.updateCardWidth(containerWidth: width)
        }
        .task { await model.load(refresh: true) }
    }

    private func loadMoreIfNeeded(after room: LiveModel) {
        guard room.id == model.rooms.last?.id else { return }
        Task { await model.loadMore() }
    }
}

@MainActor
@Observable
private final class HomeCategoryViewModel {
    private(set) var rooms: [LiveModel] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private(set) var cardWidth: CGFloat = 170

    @ObservationIgnored private let route: HomeCategoryRoute
    @ObservationIgnored private var page = 1

    init(route: HomeCategoryRoute) {
        self.route = route
    }

    func updateCardWidth(containerWidth: CGFloat) {
        let usableWidth = max(154, containerWidth - AppConstants.Spacing.xl * 2)
        let columnCount = max(1, Int((usableWidth + AppConstants.Spacing.lg) / 190))
        let spacing = AppConstants.Spacing.lg * CGFloat(max(0, columnCount - 1))
        cardWidth = min(280, (usableWidth - spacing) / CGFloat(columnCount))
    }

    func load(refresh: Bool) async {
        guard !isLoading else { return }
        if refresh {
            page = 1
            hasMore = true
            errorMessage = nil
        } else if !hasMore {
            return
        }

        guard let platform = LiveParseJSPlatformManager.platform(forPluginId: route.pluginId) else {
            errorMessage = "对应内容源已不可用。"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let context: [String: Any] = [
                "category": [
                    "id": route.categoryID,
                    "parentId": route.parentID,
                    "title": route.title,
                    "icon": route.icon,
                    "biz": route.biz ?? ""
                ]
            ]
            let fetched = try await LiveParseJSPlatformManager.getRoomList(
                platform: platform,
                id: route.categoryID,
                parentId: route.parentID,
                page: page,
                context: context
            )
            hasMore = !fetched.isEmpty
            if refresh {
                rooms = fetched.removingDuplicates()
            } else {
                rooms = rooms.appendingUnique(contentsOf: fetched)
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        page += 1
        await load(refresh: false)
        if errorMessage != nil {
            page = max(1, page - 1)
        }
    }
}
