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
            let contentWidth = min(max(geometry.size.width - 48, 320), 1_440)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    hero(contentWidth: contentWidth)

                    if !favoriteModel.roomList.isEmpty {
                        MacHomeRoomRail(
                            title: "我的收藏",
                            subtitle: favoriteModel.isFavoriteStatusRefreshing ? "状态更新中" : nil,
                            rooms: Array(favoriteModel.roomList.prefix(10)),
                            trailingTitle: "全部",
                            trailingAction: onShowFavorites,
                            openMode: .favorite
                        )
                    }

                    ForEach(model.sectionEntries) { entry in
                        MacHomePluginSection(entry: entry)
                    }

                    if isAwaitingFirstContent {
                        MacHomeLoadingSections()
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
                .frame(width: contentWidth, alignment: .leading)
                .padding(.vertical, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .center)
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
        let heroWidth = MacHomeHeroMetrics.width(for: contentWidth)
        let heroHeight = MacHomeHeroMetrics.height(for: heroWidth)

        if !model.bannerEntries.isEmpty {
            MacHomeHeroCarousel(entries: model.bannerEntries, width: heroWidth)
                .frame(width: contentWidth, alignment: .center)
        } else if isAwaitingFirstContent {
            RoundedRectangle(
                cornerRadius: MacHomeHeroMetrics.cornerRadius,
                style: .continuous
            )
                .fill(Color.gray.opacity(0.24))
                .frame(width: heroWidth, height: heroHeight)
                .frame(width: contentWidth, alignment: .center)
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

private enum MacHomeHeroMetrics {
    static let maximumWidth: CGFloat = 1_080
    static let sidePanelMinimumWidth: CGFloat = 760
    static let cornerRadius = AppConstants.CornerRadius.lg

    static func width(for contentWidth: CGFloat) -> CGFloat {
        let availableWidth = max(contentWidth, 320)
        guard availableWidth >= sidePanelMinimumWidth else { return availableWidth }

        // 与 Twitch 桌面推荐位相同，宽窗口也保留足够两侧留白，
        // 避免为了填满窗口继续放大低分辨率图片。
        let proportionalWidth = availableWidth * 0.78
        return min(max(proportionalWidth, sidePanelMinimumWidth), maximumWidth)
    }

    static func height(for width: CGFloat) -> CGFloat {
        if width >= sidePanelMinimumWidth {
            // Twitch 类型推荐位：16:9 媒体 + 右侧信息面板，整体约 2.5:1。
            return width / 2.5
        }
        return width * 9 / 16
    }
}

private enum MacHomeRoomOpenMode: Equatable {
    case direct
    case favorite
}

private struct MacHomePluginSection: View {
    let entry: HomeSectionEntry

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
            route: route,
            openMode: .direct
        )
    }
}

private struct MacHomeRoomRail: View {
    let title: String
    let subtitle: String?
    let rooms: [LiveModel]
    var trailingTitle: String?
    var trailingAction: (() -> Void)?
    var route: PluginHomeCategoryRoute?
    let openMode: MacHomeRoomOpenMode

    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if let route {
                    NavigationLink(value: route) {
                        MacHomeSeeAllLabel()
                    }
                    .buttonStyle(.borderless)
                } else if let trailingTitle, let trailingAction {
                    Button(action: trailingAction) {
                        MacHomeSeeAllLabel(title: trailingTitle)
                    }
                    .buttonStyle(.borderless)
                } else if !rooms.isEmpty {
                    NavigationLink {
                        MacHomeAllRoomsView(
                            title: title,
                            rooms: rooms,
                            openMode: openMode
                        )
                    } label: {
                        MacHomeSeeAllLabel()
                    }
                    .buttonStyle(.borderless)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 196, maximum: 248), spacing: 12)
                ],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(rooms) { room in
                    MacHomeRoomTile(room: room) {
                        open(room)
                    }
                }
            }
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

private struct MacHomeSeeAllLabel: View {
    var title = "全部"

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(minHeight: 24)
        .contentShape(Rectangle())
    }
}

private struct MacHomeRoomTile: View {
    let room: LiveModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LiveRoomCard(room: room)
                .frame(maxWidth: .infinity)
                .padding(7)
        }
        .buttonStyle(MacRoomCardButtonStyle())
        .macRoomCardHoverEffect()
        .accessibilityLabel("\(room.roomTitle)，\(room.userName)")
        .accessibilityHint("打开直播间")
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
    @State private var autoplayProgress: CGFloat = 1

    private let autoplayInterval: TimeInterval = 6
    private var height: CGFloat { MacHomeHeroMetrics.height(for: width) }
    private var indicatorRegionWidth: CGFloat {
        width >= MacHomeHeroMetrics.sidePanelMinimumWidth ? height * 16 / 9 : width
    }

    private var activeEntry: HomeBannerEntry? {
        entries.first(where: { $0.id == selectedID }) ?? entries.first
    }

    private var activeID: String? {
        activeEntry?.id
    }

    var body: some View {
        ZStack {
            if let activeEntry {
                destination(for: activeEntry)
                    .id(activeEntry.id)
                    .transition(reduceMotion ? .identity : .opacity)
            }

            if entries.count > 1 {
                HStack {
                    carouselButton(systemImage: "chevron.left", action: showPrevious)
                    Spacer()
                    carouselButton(systemImage: "chevron.right", action: showNext)
                }
                .frame(width: width >= 850 ? width + 80 : width)
                .padding(.horizontal, width >= 850 ? 0 : 14)

                MacHomeHeroPageIndicator(
                    entries: entries,
                    selectedID: activeID,
                    progress: autoplayProgress
                )
                .padding(.trailing, 22)
                .padding(.bottom, 18)
                .frame(width: indicatorRegionWidth, height: height, alignment: .bottomTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: activeID)
        .onAppear(perform: normalizeSelection)
        .onChange(of: entries.map(\.id)) { _, _ in normalizeSelection() }
        .task(id: autoplayTaskID) {
            await runAutoplayIfNeeded()
        }
    }

    private var autoplayTaskID: String {
        "\(entries.map(\.id).joined(separator: "|"))::\(selectedID ?? "")::\(scenePhase)::\(reduceMotion)"
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
        showNext()
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
                MacHomeHeroCard(entry: entry, width: width, height: height)
            }
            .buttonStyle(.plain)
        case .category(let category):
            NavigationLink(value: PluginHomeCategoryRoute(
                pluginId: entry.pluginId,
                liveType: entry.liveType,
                category: category,
                fallbackTitle: entry.banner.title
            )) {
                MacHomeHeroCard(entry: entry, width: width, height: height)
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

private struct MacHomeHeroPageIndicator: View {
    let entries: [HomeBannerEntry]
    let selectedID: String?
    let progress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(entries) { entry in
                MacHomeHeroPageProgressCapsule(
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

private struct MacHomeHeroPageProgressCapsule: View {
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

private struct MacHomeHeroCard: View {
    let entry: HomeBannerEntry
    let width: CGFloat
    let height: CGFloat

    private var preferredImageURL: URL? {
        // Banner 是插件为首页焦点位专门提供的图，优先级应高于普通房间封面。
        entry.banner.imageURL ?? roomCoverURL
    }

    private var fallbackImageURL: URL? {
        guard preferredImageURL != roomCoverURL else { return nil }
        return roomCoverURL
    }

    private var room: LiveModel? {
        guard case .room(let room) = entry.banner.target else { return nil }
        return room
    }

    private var roomCoverURL: URL? {
        guard let room, !room.roomCover.isEmpty else { return nil }
        return URL(string: room.roomCover)
    }

    private var usesSidePanel: Bool {
        width >= MacHomeHeroMetrics.sidePanelMinimumWidth
    }

    private var mediaWidth: CGFloat {
        usesSidePanel ? height * 16 / 9 : width
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: MacHomeHeroMetrics.cornerRadius,
            style: .continuous
        )
    }

    private var bannerTitle: String? {
        meaningfulText(entry.banner.title)
    }

    private var displayedRoomUserName: String? {
        guard let room, let value = meaningfulText(room.userName) else { return nil }
        guard !matchesVisibleText(value, bannerTitle) else { return nil }
        return value
    }

    private var bannerBadgeText: String? {
        guard let value = meaningfulText(entry.banner.badge) else { return nil }
        guard !matchesVisibleText(value, bannerTitle),
              !matchesVisibleText(value, displayedRoomUserName) else { return nil }
        return value
    }

    private var bannerSubtitle: String? {
        guard let value = meaningfulText(entry.banner.subtitle) else { return nil }
        guard !matchesVisibleText(value, bannerTitle),
              !matchesVisibleText(value, displayedRoomUserName),
              !matchesVisibleText(value, bannerBadgeText) else { return nil }
        return value
    }

    private var actionTitle: String {
        switch entry.banner.target {
        case .room:
            return "立即观看"
        case .category:
            return "查看分类"
        }
    }

    private var actionSymbol: String {
        switch entry.banner.target {
        case .room:
            return "play.fill"
        case .category:
            return "rectangle.grid.2x2.fill"
        }
    }

    var body: some View {
        Group {
            if usesSidePanel {
                sidePanelLayout
            } else {
                compactLayout
            }
        }
        .frame(width: width, height: height)
        .background(AppConstants.Colors.secondaryBackground, in: cardShape)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(
                    AppConstants.Colors.separator.opacity(0.35),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        .contentShape(cardShape)
    }

    private var sidePanelLayout: some View {
        HStack(spacing: 0) {
            heroImage
                .frame(width: mediaWidth, height: height)
                .clipped()

            heroInformationPanel
                .frame(width: width - mediaWidth, height: height)
                .background {
                    ZStack {
                        AppConstants.Colors.secondaryBackground
                        Color.primary.opacity(0.035)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppConstants.Colors.separator.opacity(0.5))
                        .frame(width: 1)
                }
        }
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage
            .frame(width: width, height: height)

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: height)

            VStack(alignment: .leading, spacing: 7) {
                bannerBadge
                if let bannerTitle {
                    Text(bannerTitle)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                }
                if let bannerSubtitle {
                    Text(bannerSubtitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Text("来自")
                    platformSourceLabel
                }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(28)
            .padding(.trailing, 80)
            .frame(width: width, height: height, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var heroImage: some View {
        MacHomeHeroRemoteImage(
            url: preferredImageURL,
            fallbackURL: fallbackImageURL,
            targetSize: CGSize(width: mediaWidth, height: height)
        )
    }

    private var heroInformationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let room, let displayedRoomUserName {
                HStack(alignment: .center, spacing: 10) {
                    RemoteAvatarView(url: URL(string: room.userHeadImg), size: 42) {
                        Circle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayedRoomUserName)
                            .font(.headline)
                            .lineLimit(1)
                        if let watchedCount = room.liveWatchedCount, !watchedCount.isEmpty {
                            Text("\(watchedCount) 人正在观看")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            bannerBadge

            if let bannerTitle {
                Text(bannerTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let bannerSubtitle {
                Text(bannerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                platformSourceLabel

                Spacer(minLength: 4)

                Label(actionTitle, systemImage: actionSymbol)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(22)
    }

    @ViewBuilder
    private var bannerBadge: some View {
        if let bannerBadgeText {
            Text(bannerBadgeText)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.18), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
    }

    private var platformSourceLabel: some View {
        HStack(spacing: 6) {
            if let image = MacPlatformIconProvider.tabImage(for: entry.liveType) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "puzzlepiece.extension")
            }

            Text(entry.pluginDisplayName)
                .lineLimit(1)
        }
    }

    private func meaningfulText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }
        return trimmed
    }

    private func matchesVisibleText(_ value: String, _ other: String?) -> Bool {
        guard let other else { return false }
        return comparisonKey(value) == comparisonKey(other)
    }

    private func comparisonKey(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

private struct MacHomeHeroRemoteImage: View {
    let url: URL?
    let fallbackURL: URL?
    let targetSize: CGSize

    @Environment(\.displayScale) private var displayScale

    private var downsamplingSize: CGSize {
        let headroom: CGFloat = 1.1
        return CGSize(
            width: max(targetSize.width, 1) * headroom,
            height: max(targetSize.height, 1) * headroom
        )
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
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct MacHomeLoadingSections: View {
    var body: some View {
        ForEach(0..<2, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.28))
                    .frame(width: 150, height: 22)
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 196, maximum: 248), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(0..<4, id: \.self) { _ in
                        LiveRoomCardSkeleton()
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

private struct MacHomeAllRoomsView: View {
    let title: String
    let rooms: [LiveModel]
    let openMode: MacHomeRoomOpenMode

    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 196, maximum: 248), spacing: 16)
                ],
                spacing: 22
            ) {
                ForEach(rooms) { room in
                    Button {
                        open(room)
                    } label: {
                        LiveRoomCard(room: room)
                    }
                    .buttonStyle(MacRoomCardButtonStyle())
                    .macRoomCardHoverEffect()
                    .accessibilityLabel("\(room.roomTitle)，\(room.userName)")
                    .accessibilityHint("打开直播间")
                }
            }
            .padding(24)
        }
        .background(AppConstants.Colors.primaryBackground)
        .navigationTitle(title)
    }

    private func open(_ room: LiveModel) {
        if openMode == .favorite, room.liveState == LiveState.close.rawValue {
            toastManager.show(icon: "tv.slash", message: "主播已下播")
        } else {
            fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
        }
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
                            .buttonStyle(MacRoomCardButtonStyle())
                            .macRoomCardHoverEffect()
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
