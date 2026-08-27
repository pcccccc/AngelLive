//
//  HomeView.swift
//  AngelLive
//
//  插件驱动的 iOS 首页：焦点内容、本地收藏和插件直播分区。
//

import AngelLiveCore
import AngelLiveDependencies
import SwiftUI
import UIKit

struct HomeView: View {
    private let usesPersistedPlatformSelection: Bool

    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.presentToast) private var presentToast
    @AppStorage(HomePagePreference.selectedPluginStorageKey, store: .shared)
    private var selectedPluginId = ""

    @State private var viewModel = HomeViewModel()
    @State private var navigationState = LiveRoomNavigationState()
    @State private var homeNavigationModel = HomeNavigationModel()
    @Namespace private var roomTransitionNamespace

    init(usesPersistedPlatformSelection: Bool = true) {
        self.usesPersistedPlatformSelection = usesPersistedPlatformSelection
    }

    var body: some View {
        playerPresentation
            .task(id: HomeFeedRefreshTrigger(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )) {
                viewModel.selectPlatform(pluginId: persistedPluginId)
                async let feedRefresh: Void = viewModel.refresh(
                    installedPluginIds: pluginAvailability.installedPluginIds,
                    availabilityConfirmed: pluginAvailability.hasCheckedAvailability
                )
                async let favoriteRefresh: Void = refreshFavoritesIfNeeded()
                _ = await (feedRefresh, favoriteRefresh)
                viewModel.selectPlatform(pluginId: persistedPluginId)

                if usesPersistedPlatformSelection {
                    let normalizedPluginId = viewModel.selectedPluginId ?? ""
                    if normalizedPluginId != selectedPluginId {
                        selectedPluginId = normalizedPluginId
                    }
                }
            }
            .onChange(of: selectedPluginId) { _, _ in
                if usesPersistedPlatformSelection {
                    viewModel.selectPlatform(pluginId: persistedPluginId)
                }
            }
    }
}

private extension HomeView {
    var persistedPluginId: String? {
        guard usesPersistedPlatformSelection else { return nil }
        return selectedPluginId.isEmpty ? nil : selectedPluginId
    }

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
        NavigationStack {
            GeometryReader { geometry in
                // The bar is a sibling of the feed, not an overlay on top of a
                // view that already ignores the safe area. That keeps exactly
                // one source for the top inset: the bar lays out at the safe
                // area top on its own, and only its background reaches further
                // up behind the status bar.
                ZStack(alignment: .top) {
                    homeScrollView(
                        containerWidth: geometry.size.width,
                        topSafeAreaInset: geometry.safeAreaInsets.top
                    )

                    HomeNavigationOverlay(
                        visibleSectionIDs: visibleSectionIDs,
                        topSafeAreaInset: geometry.safeAreaInsets.top,
                        model: homeNavigationModel
                    )
                }
            }
        }
    }

    var visibleSectionIDs: Set<String> {
        Set(
            viewModel.sectionEntries.map(HomeNavigationSectionID.plugin)
                + (favoriteModel.roomList.isEmpty ? [] : [HomeNavigationSectionID.favorites])
        )
    }

    func homeScrollView(containerWidth: CGFloat, topSafeAreaInset: CGFloat) -> some View {
        let featuredCardWidth = featuredRoomCardWidth(for: containerWidth)
        let compactCardWidth = compactRoomCardWidth(for: containerWidth)
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
                        metrics: homeNavigationModel,
                        onOpenRoom: { room in
                            openRoom(room, rooms: [room], mode: .direct)
                        }
                    )
                } else if isAwaitingFirstContent {
                    HomeHeroLoadingCard(
                        containerWidth: containerWidth,
                        topSafeAreaInset: topSafeAreaInset
                    )
                } else {
                    HomeCompactHeader(
                        topSafeAreaInset: topSafeAreaInset
                    )
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
                    .padding(.top, HomeNavigationMetrics.heroSectionSpacingAdjustment)
                    .trackHomeNavigationSection(
                        id: HomeNavigationSectionID.favorites,
                        title: "我的收藏",
                        onPositionChange: homeNavigationModel.updateSectionPosition
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
                    .padding(
                        .top,
                        favoriteModel.roomList.isEmpty
                            ? HomeNavigationMetrics.heroSectionSpacingAdjustment
                            : 0
                    )
                    .trackHomeNavigationSection(
                        id: HomeNavigationSectionID.plugin(firstPluginSection),
                        title: firstPluginSection.section.title,
                        onPositionChange: homeNavigationModel.updateSectionPosition
                    )
                }

                ForEach(viewModel.sectionEntries.dropFirst()) { entry in
                    HomePluginRoomSection(
                        entry: entry,
                        cardWidth: featuredCardWidth,
                        namespace: roomTransitionNamespace,
                        onSelect: { room, rooms in
                            openRoom(room, rooms: rooms, mode: .direct)
                        }
                    )
                    .trackHomeNavigationSection(
                        id: HomeNavigationSectionID.plugin(entry),
                        title: entry.section.title,
                        onPositionChange: homeNavigationModel.updateSectionPosition
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
            .background(
                HomeScrollOffsetProbe(onChange: homeNavigationModel.updateScrollMetrics)
                    .frame(width: 0, height: 0)
            )
        }
        .background(AppConstants.Colors.primaryBackground)
        // A system toolbar creates a full-width Liquid Glass region on iOS 27
        // even when its background is marked hidden. Keep the home screen's
        // default state genuinely full-bleed and render only the controls we
        // need in a lightweight overlay.
        .toolbar(.hidden, for: .navigationBar)
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
    /// The stack contributes 28 points between the hero and its first rail.
    /// Pull back 20 so the title groups remain distinct without leaving a
    /// large empty band below the banner.
    static let heroSectionSpacingAdjustment: CGFloat = -20
}

private enum HomeNavigationSectionID {
    static let favorites = "favorites"

    static func plugin(_ entry: HomeSectionEntry) -> String {
        "plugin:\(entry.pluginId):\(entry.id)"
    }
}

/// Reports the enclosing scroll view's travel without going through
/// `GeometryProxy`. A proxy measured next to `ignoresSafeArea` anchors to the
/// pre-expansion layout frame, so its resting value silently carries the top
/// safe-area inset; `contentOffset` relative to `adjustedContentInset` is
/// exact and stays correct when the refresh control changes the inset mid
/// gesture.
private struct HomeScrollOffsetProbe: UIViewRepresentable {
    let onChange: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> HomeScrollOffsetProbeView {
        HomeScrollOffsetProbeView(onChange: onChange)
    }

    func updateUIView(_ uiView: HomeScrollOffsetProbeView, context: Context) {
        uiView.onChange = onChange
    }
}

private final class HomeScrollOffsetProbeView: UIView {
    var onChange: (CGFloat, CGFloat) -> Void

    private weak var observedScrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var insetObservation: NSKeyValueObservation?

    init(onChange: @escaping (CGFloat, CGFloat) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            stopObserving()
            return
        }
        startObserving()
    }

    private func startObserving() {
        guard let scrollView = enclosingScrollView(), scrollView !== observedScrollView else {
            return
        }

        stopObserving()
        observedScrollView = scrollView

        offsetObservation = scrollView.observe(
            \.contentOffset,
            options: [.initial, .new]
        ) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.report(for: scrollView)
            }
        }

        // The refresh control installs its own top inset once a pull begins.
        // Without this the reported travel would jump by that inset instead of
        // staying continuous.
        insetObservation = scrollView.observe(
            \.adjustedContentInset,
            options: [.new]
        ) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.report(for: scrollView)
            }
        }
    }

    private func stopObserving() {
        offsetObservation = nil
        insetObservation = nil
        observedScrollView = nil
    }

    private func report(for scrollView: UIScrollView) {
        onChange(
            scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
            -scrollView.contentOffset.y
        )
    }

    private func enclosingScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }
}

private struct HomeNavigationSectionPosition: Equatable {
    let id: String
    let title: String
    let minY: CGFloat
}

@MainActor
@Observable
private final class HomeNavigationModel {
    /// Travel from the feed's resting position: zero at rest, positive while
    /// scrolled up. Measured against `adjustedContentInset` so the bar does not
    /// flicker when the refresh control installs its own inset.
    private(set) var scrollOffset: CGFloat = 0

    /// How far the first content item currently sits below the scroll view's
    /// top edge. This is plain content-to-bounds mapping (`-contentOffset.y`)
    /// and deliberately excludes `adjustedContentInset`: the refresh control
    /// raises that inset mid-gesture, and subtracting it here would under-
    /// stretch the banner by exactly the control's height, leaving a gap.
    private(set) var contentTopOffset: CGFloat = 0

    private(set) var sectionPositions: [String: HomeNavigationSectionPosition] = [:]

    var progress: CGFloat {
        min(max(scrollOffset / HomeNavigationMetrics.fadeDistance, 0), 1)
    }

    var pullDistance: CGFloat {
        max(contentTopOffset, 0)
    }

    func title(visibleSectionIDs: Set<String>, activationY: CGFloat) -> String {
        sectionPositions.values
            .filter { visibleSectionIDs.contains($0.id) && $0.minY <= activationY }
            .max(by: { $0.minY < $1.minY })?
            .title ?? "首页"
    }

    func updateScrollMetrics(offset: CGFloat, contentTop: CGFloat) {
        if abs(scrollOffset - offset) >= 0.5 {
            scrollOffset = offset
        }
        if abs(contentTopOffset - contentTop) >= 0.5 {
            contentTopOffset = contentTop
        }
    }

    func updateSectionPosition(id: String, title: String, minY: CGFloat) {
        let position = HomeNavigationSectionPosition(id: id, title: title, minY: minY)
        guard let previous = sectionPositions[id] else {
            sectionPositions[id] = position
            return
        }
        guard previous.title != title || abs(previous.minY - minY) >= 4 else { return }
        sectionPositions[id] = position
    }
}

private extension View {
    func trackHomeNavigationSection(
        id: String,
        title: String,
        onPositionChange: @escaping (String, String, CGFloat) -> Void
    ) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
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
    let metrics: HomeNavigationModel
    let onOpenRoom: (LiveModel) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPageID: String?
    @State private var loopCorrectionTask: Task<Void, Never>?
    @State private var layoutCorrectionTask: Task<Void, Never>?
    @State private var layoutGeneration = 0
    @State private var autoplayProgress: CGFloat = 1

    private let pageInset: CGFloat = 0
    private let cardSpacing: CGFloat = 0
    private let autoplayInterval: TimeInterval = 6

    private var viewportWidth: CGFloat {
        max(containerWidth, 280)
    }

    private var cardWidth: CGFloat {
        viewportWidth
    }

    private var cardHeight: CGFloat {
        min(max(viewportWidth * 0.9, 336), 500)
    }

    private var viewportSize: CGSize {
        CGSize(width: viewportWidth, height: cardHeight)
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

        ZStack(alignment: .bottomTrailing) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(loopPages) { page in
                        heroPage(for: page.entry)
                            // Bind every page to the horizontal scroll
                            // viewport. Explicit widths can leave the content
                            // offset expressed in the pre-rotation page size,
                            // which strands iPad between two pages.
                            .containerRelativeFrame(.horizontal)
                            .frame(height: cardHeight)
                            .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $selectedPageID, anchor: .center)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .frame(width: viewportWidth, height: cardHeight)
            .background(AppConstants.Colors.primaryBackground)

            if entries.count > 1 {
                HomeHeroPageIndicator(
                    entries: entries,
                    selectedID: selectedBannerID,
                    progress: autoplayProgress
                )
                    .padding(.trailing, AppConstants.Spacing.xxl)
                    .padding(.bottom, AppConstants.Spacing.xxl)
            }
        }
        .frame(height: cardHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        // Stretch only on the vertical axis. The bottom anchor cancels the
        // scroll view's positive bounce exactly, keeping the visual top at the
        // screen edge without enlarging every offscreen carousel page.
        .scaleEffect(
            x: 1,
            y: pullDownEnabled
                ? 1 + metrics.pullDistance / max(resolvedCardHeight, 1)
                : 1,
            anchor: .bottom
        )
        .onAppear(perform: normalizeSelection)
        .onChange(of: entries.map(\.id)) { _, _ in normalizeSelection() }
        .onChange(of: selectedPageID) { _, newValue in
            scheduleLoopCorrection(for: newValue)
        }
        .onChange(of: viewportSize) { oldSize, newSize in
            guard abs(oldSize.width - newSize.width) > 0.5
                    || abs(oldSize.height - newSize.height) > 0.5
            else { return }
            scheduleLayoutCorrection()
        }
        .onDisappear {
            loopCorrectionTask?.cancel()
            layoutCorrectionTask?.cancel()
        }
        .task(id: autoplayTaskID) {
            await runAutoplayIfNeeded()
        }
    }

    private var autoplayTaskID: String {
        "\(entries.map(\.id).joined(separator: "|"))::\(selectedBannerID ?? "")::\(scenePhase)::\(reduceMotion)::\(layoutGeneration)"
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

    private func scheduleLayoutCorrection() {
        layoutCorrectionTask?.cancel()
        loopCorrectionTask?.cancel()

        layoutCorrectionTask = Task { @MainActor in
            // Rotation and Stage Manager resizing can publish a short series
            // of intermediate sizes. Re-anchor only after that burst settles.
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled, !entries.isEmpty else { return }

            let bannerID = selectedBannerID.flatMap { selectedID in
                entries.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? entries[0].id
            let destinationID = HomeHeroLoopPage.realID(for: bannerID)

            // Clearing and restoring the scroll-position binding forces
            // SwiftUI to resolve the target using the new viewport width.
            // Both writes are non-animated so rotation never exposes a
            // corrective horizontal slide.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedPageID = nil
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            var restoreTransaction = Transaction()
            restoreTransaction.disablesAnimations = true
            withTransaction(restoreTransaction) {
                selectedPageID = destinationID
                layoutGeneration &+= 1
            }
        }
    }

    @MainActor
    private func runAutoplayIfNeeded() async {
        let canAutoplay = entries.count > 1 && scenePhase == .active && !reduceMotion
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            autoplayProgress = canAutoplay ? 0 : 1
        }

        guard canAutoplay else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.linear(duration: autoplayInterval)) {
            autoplayProgress = 1
        }

        do {
            try await Task.sleep(for: .seconds(autoplayInterval))
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
                    topSafeAreaInset: topSafeAreaInset,
                    reservesPageIndicatorSpace: entries.count > 1
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
                    topSafeAreaInset: topSafeAreaInset,
                    reservesPageIndicatorSpace: entries.count > 1
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
    let reservesPageIndicatorSpace: Bool

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
                    .init(color: .clear, location: 0.54),
                    .init(color: AppConstants.Colors.primaryBackground.opacity(0.12), location: 0.60),
                    .init(color: AppConstants.Colors.primaryBackground.opacity(0.58), location: 0.73),
                    .init(color: AppConstants.Colors.primaryBackground.opacity(0.94), location: 0.86),
                    .init(color: AppConstants.Colors.primaryBackground, location: 0.96),
                    .init(color: AppConstants.Colors.primaryBackground, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer(minLength: 0)
                HomeHeroContent(
                    title: heroTitle,
                    reservesPageIndicatorSpace: reservesPageIndicatorSpace
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppConstants.Spacing.xl)
            .padding(.bottom, AppConstants.Spacing.xxl)

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

private struct HomeHeroContent: View {
    let title: String
    let reservesPageIndicatorSpace: Bool

    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .foregroundStyle(AppConstants.Colors.primaryText)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .padding(.trailing, reservesPageIndicatorSpace ? 72 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeNavigationOverlay: View {
    let visibleSectionIDs: Set<String>
    let topSafeAreaInset: CGFloat
    let model: HomeNavigationModel

    var body: some View {
        let progress = model.progress
        let title = model.title(
            visibleSectionIDs: visibleSectionIDs,
            activationY: topSafeAreaInset + HomeNavigationMetrics.barHeight
        )

        // No manual top inset: the bar is laid out inside the safe area by its
        // container. Only its background reaches behind the status bar.
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .opacity(progress)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: title)
            .accessibilityHidden(progress < 0.5)
            .frame(maxWidth: .infinity)
            .frame(height: HomeNavigationMetrics.barHeight)
            // Liquid Glass rather than a solid slab: the feed stays visible through
            // the bar, and the glass is what keeps the title legible over whatever
            // scrolls underneath it. Fading the layer with `progress` keeps the
            // resting state genuinely full-bleed.
            .background(alignment: .top) {
                Color.clear
                    .homeNavigationBarGlass()
                    .opacity(progress)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
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
    let progress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maximumVisibleIndicators = 5

    private var selectedIndex: Int {
        entries.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    private var visibleEntries: ArraySlice<HomeBannerEntry> {
        guard entries.count > maximumVisibleIndicators else {
            return entries[...]
        }

        let halfWindow = maximumVisibleIndicators / 2
        let maximumStart = entries.count - maximumVisibleIndicators
        let start = min(max(selectedIndex - halfWindow, 0), maximumStart)
        return entries[start..<(start + maximumVisibleIndicators)]
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(visibleEntries) { entry in
                HomeHeroPageProgressCapsule(
                    isSelected: entry.id == selectedID,
                    progress: entry.id == selectedID ? progress : 0
                )
            }
        }
        .frame(height: 28)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selectedID)
        .accessibilityHidden(true)
    }
}

private struct HomeHeroPageProgressCapsule: View {
    let isSelected: Bool
    let progress: CGFloat

    private let capsuleWidth: CGFloat = 18
    private let capsuleHeight: CGFloat = 5

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var fillWidth: CGFloat {
        guard isSelected else { return 0 }
        return capsuleHeight
            + (capsuleWidth - capsuleHeight) * clampedProgress
    }

    var body: some View {
        RoundedRectangle(
            cornerRadius: capsuleHeight / 2,
            style: .continuous
        )
            .fill(AppConstants.Colors.tertiaryText)
            .overlay(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: capsuleHeight / 2,
                    style: .continuous
                )
                    .fill(AppConstants.Colors.primaryText)
                    .frame(width: fillWidth, height: capsuleHeight)
            }
            .frame(
                width: isSelected ? capsuleWidth : capsuleHeight,
                height: capsuleHeight
            )
    }
}

private extension View {
    @ViewBuilder
    func homeNavigationBarGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect)
        } else {
            self.background(.ultraThinMaterial)
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
    let topSafeAreaInset: CGFloat

    var body: some View {
        HStack {
            // The picker lives in the persistent home overlay even when there
            // are no installed home-feed plugins. Preserve its vertical rhythm
            // without maintaining a second control that can drift out of sync.
            Color.clear
                .frame(height: HomeNavigationMetrics.barHeight)
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
