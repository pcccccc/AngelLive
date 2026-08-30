//
//  MacHomeView.swift
//  AngelLiveMacOS
//
//  插件驱动的 macOS 首页。内容层次沿用 iPad：首页焦点、收藏和插件推荐分区。
//

import AngelLiveCore
import Kingfisher
import SwiftUI
internal import Shimmer

struct MacHomeRefreshAction {
    let perform: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        perform()
    }
}

private struct MacHomeRefreshFocusedKey: FocusedValueKey {
    typealias Value = MacHomeRefreshAction
}

extension FocusedValues {
    var macHomeRefreshAction: MacHomeRefreshAction? {
        get { self[MacHomeRefreshFocusedKey.self] }
        set { self[MacHomeRefreshFocusedKey.self] = newValue }
    }
}

private struct MacHomeRefreshRegistration: ViewModifier {
    let isSelected: Bool
    let action: MacHomeRefreshAction

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.focusedSceneValue(\.macHomeRefreshAction, action)
        } else {
            content
        }
    }
}

struct MacHomeView: View {
    let isSelected: Bool
    let onShowFavorites: () -> Void

    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.openWindow) private var openWindow

    @State private var model = PluginHomeFeedModel()

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width - 48, 320)
            let cardWidth = min(max(contentWidth / 4.2, 190), 260)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    hero(contentWidth: contentWidth)

                    if !favoriteModel.roomList.isEmpty {
                        MacHomeRoomRail(
                            title: "我的收藏",
                            subtitle: favoriteModel.isFavoriteStatusRefreshing ? "状态更新中" : nil,
                            rooms: Array(favoriteModel.roomList.prefix(10)),
                            cardWidth: cardWidth,
                            trailingTitle: "查看全部",
                            trailingAction: onShowFavorites,
                            openMode: .favorite
                        )
                    }

                    ForEach(model.sectionEntries) { entry in
                        MacHomePluginSection(entry: entry, cardWidth: cardWidth)
                    }

                    if isAwaitingFirstContent {
                        MacHomeLoadingSections(cardWidth: cardWidth)
                            .shimmering()
                    }

                    if model.hasLoaded,
                       model.bannerEntries.isEmpty,
                       model.sectionEntries.isEmpty,
                       favoriteModel.roomList.isEmpty {
                        ErrorView.empty(
                            title: "暂无首页推荐",
                            message: "已安装的内容源暂未返回推荐内容，请稍后刷新。",
                            symbolName: "rectangle.stack",
                            tint: .secondary
                        )
                        .frame(minHeight: 320)
                    }

                    if !model.failedPluginNames.isEmpty {
                        MacHomeFailureCard(
                            pluginNames: model.failedPluginNames,
                            isRefreshing: model.isRefreshing,
                            retry: refreshHome
                        )
                    }
                }
                .padding(24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppConstants.Colors.primaryBackground)
        }
        .navigationTitle("首页")
        .toolbar {
            ToolbarItem {
                Button(action: refreshAll) {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise")
                }
                .help("刷新首页")
                .disabled(model.isRefreshing)
            }
        }
        .navigationDestination(for: PluginHomeCategoryRoute.self) { route in
            MacHomeCategoryView(route: route)
        }
        .modifier(
            MacHomeRefreshRegistration(
                isSelected: isSelected,
                action: MacHomeRefreshAction(perform: refreshAll)
            )
        )
        .task(id: MacHomeRefreshTrigger(
            installedPluginIds: pluginAvailability.installedPluginIds,
            availabilityConfirmed: pluginAvailability.hasCheckedAvailability,
            catalogRevision: pluginAvailability.catalogRevision
        )) {
            model.selectPlatform(pluginId: nil)
            await model.refresh(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )
            await refreshFavoritesIfNeeded()
        }
    }

    @ViewBuilder
    private func hero(contentWidth: CGFloat) -> some View {
        if !model.bannerEntries.isEmpty {
            MacHomeHeroCarousel(entries: model.bannerEntries, width: contentWidth)
        } else if isAwaitingFirstContent {
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl)
                .fill(Color.gray.opacity(0.24))
                .frame(width: contentWidth, height: min(max(contentWidth * 0.42, 280), 480))
                .shimmering()
        }
    }

    private var isAwaitingFirstContent: Bool {
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

    @MainActor
    private func refreshFavoritesIfNeeded() async {
        if favoriteModel.shouldSync() {
            await favoriteModel.syncWithActor()
        }
    }

    private func refreshHome() {
        Task {
            await model.refresh(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )
        }
    }

    private func refreshAll() {
        Task {
            await model.refresh(
                installedPluginIds: pluginAvailability.installedPluginIds,
                availabilityConfirmed: pluginAvailability.hasCheckedAvailability
            )
            await favoriteModel.syncWithActor()
        }
    }
}

private struct MacHomeRefreshTrigger: Hashable {
    let installedPluginIds: [String]
    let availabilityConfirmed: Bool
    let catalogRevision: UInt
}

private enum MacHomeRoomOpenMode: Equatable {
    case direct
    case favorite
}

private struct MacHomePluginSection: View {
    let entry: HomeSectionEntry
    let cardWidth: CGFloat

    private var subtitle: String {
        let source = entry.section.personalized
            ? "为你推荐 · 来自 \(entry.pluginDisplayName)"
            : "来自 \(entry.pluginDisplayName)"
        guard let text = entry.section.subtitle, !text.isEmpty else { return source }
        return "\(text) · \(source)"
    }

    private var route: PluginHomeCategoryRoute? {
        entry.section.seeAllTarget.map {
            PluginHomeCategoryRoute(
                pluginId: entry.pluginId,
                liveType: entry.liveType,
                category: $0,
                fallbackTitle: entry.section.title
            )
        }
    }

    var body: some View {
        MacHomeRoomRail(
            title: entry.section.title,
            subtitle: subtitle,
            rooms: entry.section.items.map(\.room),
            cardWidth: cardWidth,
            route: route,
            openMode: .direct
        )
    }
}

private struct MacHomeRoomRail: View {
    let title: String
    let subtitle: String?
    let rooms: [LiveModel]
    let cardWidth: CGFloat
    var trailingTitle: String?
    var trailingAction: (() -> Void)?
    var route: PluginHomeCategoryRoute?
    let openMode: MacHomeRoomOpenMode

    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.bold())
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let route {
                    NavigationLink(value: route) {
                        Label("查看全部", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else if let trailingTitle, let trailingAction {
                    Button(trailingTitle, action: trailingAction)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(rooms) { room in
                        Button {
                            open(room)
                        } label: {
                            LiveRoomCard(room: room)
                                .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .enableMacHorizontalWheelScroll()
        }
    }

    private func open(_ room: LiveModel) {
        if openMode == .favorite, room.liveState == LiveState.close.rawValue {
            toastManager.show(icon: "tv.slash", message: "主播已下播")
        } else {
            fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
        }
    }
}

private struct MacHomeHeroCarousel: View {
    let entries: [HomeBannerEntry]
    let width: CGFloat

    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?

    private var height: CGFloat { min(max(width * 0.42, 280), 480) }

    var body: some View {
        ZStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(entries) { entry in
                        destination(for: entry)
                            .containerRelativeFrame(.horizontal)
                            .frame(height: height)
                            .id(entry.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedID, anchor: .center)
            .scrollIndicators(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))

            if entries.count > 1 {
                HStack {
                    carouselButton(systemImage: "chevron.left", action: showPrevious)
                    Spacer()
                    carouselButton(systemImage: "chevron.right", action: showNext)
                }
                .padding(.horizontal, 14)

                HStack(spacing: 6) {
                    ForEach(entries) { entry in
                        Capsule()
                            .fill(entry.id == selectedID ? Color.white : Color.white.opacity(0.45))
                            .frame(width: entry.id == selectedID ? 22 : 7, height: 7)
                    }
                }
                .padding(10)
                .background(.black.opacity(0.25), in: Capsule())
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 14)
            }
        }
        .frame(width: width, height: height)
        .onAppear(perform: normalizeSelection)
        .onChange(of: entries.map(\.id)) { _, _ in normalizeSelection() }
        .task(id: "\(entries.map(\.id).joined(separator: "|"))::\(selectedID ?? "")::\(scenePhase)::\(reduceMotion)") {
            guard entries.count > 1, scenePhase == .active, !reduceMotion else { return }
            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            showNext()
        }
    }

    private func carouselButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.bold())
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(for entry: HomeBannerEntry) -> some View {
        switch entry.banner.target {
        case .room(let room):
            Button {
                fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
            } label: {
                MacHomeHeroCard(entry: entry)
            }
            .buttonStyle(.plain)
        case .category(let category):
            NavigationLink(value: PluginHomeCategoryRoute(
                pluginId: entry.pluginId,
                liveType: entry.liveType,
                category: category,
                fallbackTitle: entry.banner.title
            )) {
                MacHomeHeroCard(entry: entry)
            }
            .buttonStyle(.plain)
        }
    }

    private func normalizeSelection() {
        guard !entries.isEmpty else {
            selectedID = nil
            return
        }
        if !entries.contains(where: { $0.id == selectedID }) {
            selectedID = entries[0].id
        }
    }

    private func showPrevious() {
        moveSelection(offset: -1)
    }

    private func showNext() {
        moveSelection(offset: 1)
    }

    private func moveSelection(offset: Int) {
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex(where: { $0.id == selectedID }) ?? 0
        let index = (current + offset + entries.count) % entries.count
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            selectedID = entries[index].id
        }
    }
}

private struct MacHomeHeroCard: View {
    let entry: HomeBannerEntry

    private var primaryURL: URL? {
        entry.banner.imageURL ?? room.flatMap { URL(string: $0.roomCover) }
    }

    private var room: LiveModel? {
        guard case .room(let room) = entry.banner.target else { return nil }
        return room
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let primaryURL {
                    KFImage(primaryURL)
                        .placeholder { placeholder }
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                if let badge = entry.banner.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Text(entry.banner.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                if let subtitle = entry.banner.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }
                Text("来自 \(entry.pluginDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(28)
            .padding(.trailing, 80)
        }
        .clipped()
        .contentShape(Rectangle())
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct MacHomeLoadingSections: View {
    let cardWidth: CGFloat

    var body: some View {
        ForEach(0..<2, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.28))
                    .frame(width: 150, height: 22)
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<4, id: \.self) { _ in
                        LiveRoomCardSkeleton()
                            .frame(width: cardWidth)
                    }
                }
            }
        }
    }
}

private struct MacHomeFailureCard: View {
    let pluginNames: [String]
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("部分推荐加载失败")
                    .font(.headline)
                Text(pluginNames.joined(separator: "、"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("重试", action: retry)
                .disabled(isRefreshing)
        }
        .padding(16)
        .background(AppConstants.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacHomeCategoryView: View {
    let route: PluginHomeCategoryRoute
    @State private var model: PluginHomeCategoryModel
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(\.openWindow) private var openWindow

    init(route: PluginHomeCategoryRoute) {
        self.route = route
        _model = State(initialValue: PluginHomeCategoryModel(route: route))
    }

    var body: some View {
        Group {
            if model.rooms.isEmpty, model.isLoading {
                ScrollView {
                    LiveRoomSkeletonGrid()
                        .padding(.vertical, 20)
                }
                .shimmering()
            } else if model.rooms.isEmpty, let error = model.errorMessage {
                ErrorView(
                    title: "加载失败",
                    message: error,
                    showRetry: true,
                    onRetry: { Task { await model.load(refresh: true) } }
                )
            } else if model.rooms.isEmpty {
                ErrorView.empty(
                    title: "暂无直播",
                    message: "当前推荐分类下没有正在直播的房间。",
                    symbolName: "video.slash",
                    tint: .secondary
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)],
                        spacing: 20
                    ) {
                        ForEach(model.rooms) { room in
                            Button {
                                fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
                            } label: {
                                LiveRoomCard(room: room)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if room.id == model.rooms.last?.id {
                                    Task { await model.loadMore() }
                                }
                            }
                        }
                    }
                    .padding(24)

                    if model.isLoading {
                        ProgressView()
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle(route.title)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.load(refresh: true) }
                } label: {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise")
                }
                .help("刷新")
                .disabled(model.isLoading)
            }
        }
        .task {
            if model.rooms.isEmpty {
                await model.load(refresh: true)
            }
        }
    }
}
