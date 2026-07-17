import SwiftUI
import AngelLiveCore
import JXSegmentedView

struct RoomSwitcherPanel: View {
    let currentRoom: LiveModel
    let favorites: [LiveModel]
    let history: [LiveModel]
    let category: [LiveModel]
    @Binding var selectedSourceIndex: Int
    let switchingRoomID: String?
    let failedRoomID: String?
    let failureMessage: String?
    let canLoadMoreCategory: () -> Bool
    let isLoadingMoreCategory: Bool
    let onLoadMoreCategory: (() async -> [LiveModel])?
    let onSelect: (LiveModel) -> Void
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
        VStack(spacing: 0) {
            currentRoomStrip

            Divider().opacity(0.35)

            JXRoomSourcePager(
                pages: pages,
                selectedIndex: $selectedSourceIndex,
                favoriteModel: favoriteModel,
                onSelectRoom: onSelect
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速换台")
        .onAppear {
            normalizeSelectedSource()
        }
        .onChange(of: availableSources) { _, _ in
            normalizeSelectedSource()
        }
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
                Text(failedRoomID == nil ? currentRoom.roomTitle.orDash : (failureMessage ?? "切换失败"))
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

    private func normalizeSelectedSource() {
        let safeIndex = min(max(selectedSourceIndex, 0), max(availableSources.count - 1, 0))
        selectedSourceIndex = safeIndex
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
    let room: LiveModel
    let onToggleSwitcher: () -> Void
    let onClearChat: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleSwitcher) {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.stack.fill")
                        .symbolRenderingMode(.hierarchical)
                    Text(isSwitcherPresented ? "聊天" : "换台")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSwitcherPresented ? "返回聊天" : "快速换台")

            Divider()
                .frame(height: 22)

            MoreActionsButton(
                room: room,
                onClearChat: onClearChat,
                embeddedInDock: true
            )
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }
}

private extension RoomSwitchSource {
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
