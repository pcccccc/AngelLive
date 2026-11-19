import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import JXSegmentedView

struct RoomSwitcherPanel: View {
    let currentRoom: LiveModel
    let favorites: [LiveModel]
    let history: [LiveModel]
    let category: [LiveModel]
    @Binding var selectedSource: RoomSwitchSource
    let switchingRoomID: String?
    let failedRoomID: String?
    let failureMessage: String?
    let canLoadMoreCategory: () -> Bool
    let isLoadingMoreCategory: Bool
    let onLoadMoreCategory: (() async -> [LiveModel])?
    let onSelect: (LiveModel) -> Void
    let onClose: () -> Void
    var isInline = false
    @Environment(AppFavoriteModel.self) private var favoriteModel

    private var availableSources: [RoomSwitchSource] {
        guard category.contains(currentRoom) else { return [.favorite, .history] }
        let categoryRooms = RoomSwitchCandidates.rooms(
            for: .category,
            currentRoom: currentRoom,
            favorites: favorites,
            history: history,
            category: category
        )
        return categoryRooms.isEmpty ? [.favorite, .history] : RoomSwitchSource.allCases
    }

    private func candidates(for source: RoomSwitchSource) -> [LiveModel] {
        RoomSwitchCandidates.rooms(
            for: source,
            currentRoom: currentRoom,
            favorites: favorites,
            history: history,
            category: category
        )
    }

    private var pages: [RoomSwitchPage] {
        availableSources.map { source in
            RoomSwitchPage(
                title: source.title,
                rooms: candidates(for: source),
                emptyTitle: "暂无可切换直播间",
                emptyMessage: emptyDescription(for: source),
                emptySymbolName: source.systemImage,
                canLoadMore: source == .category ? { !isLoadingMoreCategory && canLoadMoreCategory() } : { false },
                onLoadMore: loadMoreAction(for: source)
            )
        }
    }

    var body: some View {
        Group {
            if isInline {
                inlineList
            } else {
                overlayPanel
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速换台")
    }

    private var overlayPanel: some View {
        VStack(spacing: 0) {
            currentRoomStrip

            Divider().opacity(0.35)

            JXRoomSourcePager(
                pages: pages,
                selectedIndex: Binding(
                    get: { availableSources.firstIndex(of: selectedSource) ?? 0 },
                    set: { index in
                        let sources = availableSources
                        if sources.indices.contains(index) { selectedSource = sources[index] }
                    }
                ),
                favoriteModel: favoriteModel,
                onSelectRoom: onSelect
            )
        }
    }

    private var inlineRooms: [LiveModel] {
        let sourceRooms: [LiveModel]
        switch selectedSource {
        case .favorite:
            sourceRooms = favorites.filter { $0.liveState == LiveState.live.rawValue }
        case .history:
            sourceRooms = history
        case .category:
            sourceRooms = category
        }
        var rooms = candidates(for: selectedSource)
        if let currentIndex = sourceRooms.firstIndex(of: currentRoom) {
            let precedingRooms = Set(sourceRooms[..<currentIndex])
            let insertIndex = rooms.firstIndex { !precedingRooms.contains($0) } ?? rooms.endIndex
            rooms.insert(currentRoom, at: insertIndex)
        }
        return rooms
    }

    private var inlineList: some View {
        let rooms = inlineRooms
        return GeometryReader { geometry in
            let rowWidth = geometry.size.width - 2 * FullUIPlayerDetailChrome.inset
            let coverWidth = min(104, max(0, rowWidth - 16) * 0.28)
            inlineScrollView(rooms: rooms, coverWidth: coverWidth)
        }
        .id(selectedSource)
    }

    private func inlineScrollView(rooms: [LiveModel], coverWidth: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if rooms.isEmpty {
                    inlineEmptyState
                }

                ForEach(rooms) { room in
                    let row = InlineRoomSwitchRow(
                        room: room,
                        coverWidth: coverWidth,
                        isCurrent: room == currentRoom,
                        isSwitching: room.id == switchingRoomID,
                        failureMessage: room.id == failedRoomID ? failureMessage : nil
                    )
                    if room == currentRoom {
                        row
                    } else {
                        Button { onSelect(room) } label: { row }
                            .buttonStyle(.plain)
                            .disabled(room.id == switchingRoomID)
                    }
                }

                if selectedSource == .category, canLoadMoreCategory(), let onLoadMoreCategory {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .accessibilityLabel("正在加载更多直播间")
                        .task {
                            guard !isLoadingMoreCategory else { return }
                            _ = await onLoadMoreCategory()
                        }
                }
            }
            .padding(.horizontal, FullUIPlayerDetailChrome.inset)
            .padding(.vertical, 8)
        }
    }

    private var inlineEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: selectedSource.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("暂无可切换直播间")
                .font(.subheadline.weight(.semibold))
            Text(emptyDescription(for: selectedSource))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var currentRoomStrip: some View {
        HStack(spacing: 10) {
            roomAvatar(currentRoom, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(currentRoom.userName.orDash)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    playbackStatus
                }
                Group {
                    if failedRoomID == nil {
                        TranslatedRoomTitle(currentRoom.roomTitle.orDash)
                    } else {
                        Text(failureMessage ?? "切换失败")
                    }
                }
                    .font(.caption)
                    .foregroundStyle(failedRoomID == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if switchingRoomID != nil {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在切换直播间")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭快速换台")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var playbackStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(failedRoomID == nil ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(failedRoomID == nil ? "播放中" : "切换失败")
                .font(.caption2.weight(.medium))
                .foregroundStyle(failedRoomID == nil ? Color.secondary : Color.red)
        }
        .fixedSize()
    }

    private func roomAvatar(_ room: LiveModel, size: CGFloat) -> some View {
        AsyncImage(url: URL(string: room.userHeadImg)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func emptyDescription(for source: RoomSwitchSource) -> String {
        switch source {
        case .favorite: "收藏中没有其他正在直播的房间"
        case .history: "还没有其他观看记录"
        case .category: "从直播分区进入后，这里会显示同分区直播间"
        }
    }

    private func loadMoreAction(for source: RoomSwitchSource) -> (() async -> [LiveModel])? {
        guard source == .category, let onLoadMoreCategory else { return nil }
        return {
            let rooms = await onLoadMoreCategory()
            return RoomSwitchCandidates.rooms(
                for: .category,
                currentRoom: currentRoom,
                favorites: favorites,
                history: history,
                category: rooms
            )
        }
    }
}

private struct InlineRoomSwitchRow: View {
    let room: LiveModel
    let coverWidth: CGFloat
    let isCurrent: Bool
    let isSwitching: Bool
    let failureMessage: String?

    private let shape = RoundedRectangle(cornerRadius: 12)
    private let selectionColor = Color(red: 131 / 255, green: 196 / 255, blue: 1)

    var body: some View {
        HStack(spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(room.userName.orDash)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isCurrent {
                        Label("正在看", systemImage: "checkmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FullUIPlayerDetailChrome.accent)
                            .fixedSize()
                    } else if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在切换直播间")
                    }
                }
                .frame(minHeight: 20)

                Group {
                    if let failureMessage {
                        Text(failureMessage)
                            .foregroundStyle(.red)
                    } else {
                        TranslatedRoomTitle(room.roomTitle.orDash)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .lineLimit(1)
                .frame(minHeight: 16)

                FullUIRoomPopularity(count: room.liveWatchedCount)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        }
        .padding(8)
        .frame(minHeight: 76)
        .background(isCurrent ? selectionColor.opacity(0.09) : Color.primary.opacity(0.04), in: shape)
        .overlay {
            if isCurrent {
                shape.strokeBorder(selectionColor.opacity(0.32), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        KFImage(URL(string: room.roomCover))
            .placeholder { Color.primary.opacity(0.05) }
            .resizable()
            .scaledToFill()
            .frame(width: coverWidth, height: coverWidth * 9 / 16)
            .background(Color.primary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 7))
            .accessibilityHidden(true)
            .overlay(alignment: .bottomLeading) {
                if isCurrent || room.liveState == LiveState.live.rawValue {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text("直播中")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.85), in: .rect(cornerRadius: 4))
                    .padding(4)
                }
            }
    }
}

private struct RoomSwitchPage {
    let title: String
    let rooms: [LiveModel]
    let emptyTitle: String
    let emptyMessage: String
    let emptySymbolName: String
    let canLoadMore: () -> Bool
    let onLoadMore: (() async -> [LiveModel])?
}

private struct JXRoomSourcePager: UIViewControllerRepresentable {
    let pages: [RoomSwitchPage]
    @Binding var selectedIndex: Int
    let favoriteModel: AppFavoriteModel
    let onSelectRoom: (LiveModel) -> Void

    func makeUIViewController(context: Context) -> JXRoomSourcePagerViewController {
        let viewController = JXRoomSourcePagerViewController()
        configure(viewController)
        return viewController
    }

    func updateUIViewController(_ viewController: JXRoomSourcePagerViewController, context: Context) {
        configure(viewController)
    }

    private func configure(_ viewController: JXRoomSourcePagerViewController) {
        viewController.configure(
            pages: pages,
            selectedIndex: selectedIndex,
            favoriteModel: favoriteModel,
            onSelect: { index in
                guard selectedIndex != index else { return }
                selectedIndex = index
            },
            onSelectRoom: onSelectRoom
        )
    }
}

private final class JXRoomSourcePagerViewController: UIViewController {
    private let dataSource = JXSegmentedTitleDataSource()
    private var pages: [RoomSwitchPage] = []
    private var configuredSelectedIndex = 0
    private var favoriteModel: AppFavoriteModel?
    private var onSelect: (Int) -> Void = { _ in }
    private var onSelectRoom: (LiveModel) -> Void = { _ in }
    private var isApplyingSwiftUIUpdate = false

    private lazy var segmentedView: JXSegmentedView = {
        let view = JXSegmentedView()
        view.backgroundColor = .clear
        view.dataSource = dataSource
        view.delegate = self
        view.contentEdgeInsetLeft = 20
        view.contentEdgeInsetRight = 20
        view.translatesAutoresizingMaskIntoConstraints = false

        let indicator = JXSegmentedIndicatorLineView()
        indicator.indicatorWidth = 20
        indicator.indicatorColor = UIColor(AppConstants.Colors.accent)
        indicator.indicatorHeight = 4
        indicator.indicatorCornerRadius = 2
        indicator.verticalOffset = 2
        view.indicators = [indicator]
        view.accessibilityLabel = "换台来源"
        return view
    }()

    private lazy var listContainerView: JXSegmentedListContainerView = {
        let view = JXSegmentedListContainerView(dataSource: self, type: .scrollView)
        view.backgroundColor = .clear
        view.listCellBackgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(segmentedView)
        view.addSubview(listContainerView)
        segmentedView.listContainer = listContainerView

        NSLayoutConstraint.activate([
            segmentedView.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedView.heightAnchor.constraint(equalToConstant: 50),
            listContainerView.topAnchor.constraint(equalTo: segmentedView.bottomAnchor),
            listContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        reloadSources()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        listContainerView.setNeedsLayout()
        listContainerView.layoutIfNeeded()

        for list in listContainerView.validListDict.values {
            (list as? RoomListViewController)?.refreshLayoutForCurrentBounds()
        }
    }

    func configure(
        pages: [RoomSwitchPage],
        selectedIndex: Int,
        favoriteModel: AppFavoriteModel,
        onSelect: @escaping (Int) -> Void,
        onSelectRoom: @escaping (LiveModel) -> Void
    ) {
        let sourcesChanged = self.pages.map(\.title) != pages.map(\.title)
        self.pages = pages
        configuredSelectedIndex = selectedIndex
        self.favoriteModel = favoriteModel
        self.onSelect = onSelect
        self.onSelectRoom = onSelectRoom

        guard isViewLoaded else { return }
        if sourcesChanged {
            reloadSources()
        } else {
            refreshVisiblePages()
            selectConfiguredSource()
        }
    }

    private func reloadSources() {
        let safeIndex = min(max(configuredSelectedIndex, 0), max(pages.count - 1, 0))
        configuredSelectedIndex = safeIndex

        dataSource.titles = pages.map(\.title)
        dataSource.isItemSpacingAverageEnabled = false
        dataSource.titleNormalColor = UIColor(AppConstants.Colors.secondaryText)
        dataSource.titleSelectedColor = UIColor(AppConstants.Colors.accent)
        dataSource.titleNormalFont = .systemFont(ofSize: 15, weight: .regular)
        dataSource.titleSelectedFont = .systemFont(ofSize: 16, weight: .bold)
        dataSource.isTitleZoomEnabled = true
        dataSource.titleSelectedZoomScale = 1.08
        dataSource.itemWidth = JXSegmentedViewAutomaticDimension

        segmentedView.defaultSelectedIndex = safeIndex
        listContainerView.defaultSelectedIndex = safeIndex
        segmentedView.reloadData()
        listContainerView.reloadData()
        selectConfiguredSource()
    }

    private func refreshVisiblePages() {
        for (index, list) in listContainerView.validListDict {
            guard pages.indices.contains(index),
                  let roomListViewController = list as? RoomListViewController else { continue }
            roomListViewController.updateStaticRooms(pages[index].rooms)
        }
    }

    private func selectConfiguredSource() {
        guard pages.indices.contains(configuredSelectedIndex),
              segmentedView.selectedIndex != configuredSelectedIndex else { return }
        isApplyingSwiftUIUpdate = true
        segmentedView.selectItemAt(index: configuredSelectedIndex)
        isApplyingSwiftUIUpdate = false
    }
}

extension JXRoomSourcePagerViewController: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        guard !isApplyingSwiftUIUpdate, pages.indices.contains(index) else { return }
        configuredSelectedIndex = index
        onSelect(index)
    }
}

extension JXRoomSourcePagerViewController: JXSegmentedListContainerViewDataSource {
    func numberOfLists(in listContainerView: JXSegmentedListContainerView) -> Int {
        pages.count
    }

    func listContainerView(
        _ listContainerView: JXSegmentedListContainerView,
        initListAt index: Int
    ) -> JXSegmentedListContainerViewListDelegate {
        guard pages.indices.contains(index) else {
            return RoomListViewController(
                rooms: [],
                emptyTitle: "暂无可切换直播间",
                emptyMessage: "当前没有可显示的直播间。",
                emptySymbolName: "rectangle.stack.badge.questionmark",
                favoriteModel: favoriteModel,
                canLoadMore: nil,
                onLoadMore: nil,
                onSelectRoom: { _ in }
            )
        }
        let page = pages[index]
        return RoomListViewController(
            rooms: page.rooms,
            emptyTitle: page.emptyTitle,
            emptyMessage: page.emptyMessage,
            emptySymbolName: page.emptySymbolName,
            favoriteModel: favoriteModel,
            canLoadMore: page.canLoadMore,
            onLoadMore: page.onLoadMore,
            onSelectRoom: { [weak self] room in
                self?.onSelectRoom(room)
            }
        )
    }
}

struct RoomActionDock: View {
    let isSwitcherPresented: Bool
    @Binding var selectedSource: RoomSwitchSource
    let room: LiveModel
    let onToggleSwitcher: () -> Void
    let onClearChat: () -> Void
    var onJumpToLatestChat: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(isSwitcherPresented ? "换台" : "聊天")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            if isSwitcherPresented {
                sourceMenu
            }

            Spacer(minLength: 0)

            Button(action: onToggleSwitcher) {
                HStack(spacing: 4) {
                    Text(isSwitcherPresented ? "聊天" : "换台")
                        .font(.footnote.weight(.semibold))
                    if !isSwitcherPresented {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: FullUIPlayerDetailChrome.pillHeight)
                .background(FullUIPlayerDetailChrome.pillFill, in: Capsule())
                .frame(minWidth: FullUIPlayerChrome.controlSize, minHeight: FullUIPlayerChrome.controlSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSwitcherPresented ? "返回聊天" : "换台")

            if !isSwitcherPresented {
                MoreActionsButton(
                    room: room,
                    onClearChat: onClearChat,
                    usesDetailPill: true,
                    onJumpToLatestChat: onJumpToLatestChat
                )
                .padding(.leading, -6)
                .padding(.trailing, -6)
            }
        }
        .frame(minHeight: FullUIPlayerChrome.controlSize)
        .padding(.horizontal, FullUIPlayerDetailChrome.inset)
    }

    private var sourceMenu: some View {
        Menu {
            Picker("来源", selection: $selectedSource) {
                ForEach(RoomSwitchSource.allCases, id: \.self) { source in
                    Label(source.title, systemImage: source.systemImage)
                        .tag(source)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("·")
                    .accessibilityHidden(true)
                Text(selectedSource.inlineTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("换台来源")
        .accessibilityValue(selectedSource.inlineTitle)
    }
}

private extension RoomSwitchSource {
    var inlineTitle: String {
        switch self {
        case .favorite: "收藏中正在直播"
        case .history: "最近观看"
        case .category: "当前分区"
        }
    }

    var title: String {
        switch self {
        case .favorite: "收藏"
        case .history: "历史"
        case .category: "分区"
        }
    }

    var systemImage: String {
        switch self {
        case .favorite: "star.fill"
        case .history: "clock.arrow.circlepath"
        case .category: "square.grid.2x2.fill"
        }
    }
}
