import AngelLiveCore
import Kingfisher
import SwiftUI

struct MacRoomSwitcherPanel: View {
    let currentRoom: LiveModel
    let favorites: [LiveModel]
    let history: [LiveModel]
    let category: CategoryRoomListModel?
    let switchingRoom: LiveModel?
    let failure: (room: LiveModel, message: String)?
    let onSelect: (LiveModel) -> Void
    let onClose: () -> Void

    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @State private var source: RoomSwitchSource = .favorite
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var liveHistory: [LiveModel] = []
    @State private var historyClassification: ShortDramaHistoryClassification?

    private var activeSource: RoomSwitchSource {
        category == nil && source == .category ? .favorite : source
    }

    private var rooms: [LiveModel] {
        RoomSwitchCandidates.orderedRooms(
            for: activeSource,
            favorites: favorites,
            history: liveHistory,
            category: category?.rooms ?? [],
            includesOnDemand: true
        )
        .map { $0 == currentRoom ? currentRoom : $0 }
    }

    var body: some View {
        MacPlayerDrawer(title: "快速换台", onClose: onClose) {
            Text(sourceTitle)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("换台来源", selection: $source) {
                    Text("收藏").tag(RoomSwitchSource.favorite)
                    Text("历史").tag(RoomSwitchSource.history)
                    if category != nil {
                        Text("分区").tag(RoomSwitchSource.category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(AppConstants.Colors.accent)
                .accessibilityLabel("换台来源")

                roomList
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速换台")
        .onChange(of: activeSource) { _, newSource in
            if newSource == .history { refreshLiveHistory() }
            if newSource != .category { loadMoreTask?.cancel() }
        }
        .onChange(of: category.map(ObjectIdentifier.init)) { _, identity in
            loadMoreTask?.cancel()
            if identity == nil, source == .category { source = .favorite }
        }
        .onChange(of: history) { if activeSource == .history { refreshLiveHistory() } }
        .onChange(of: pluginAvailability.catalogRevision) { if activeSource == .history { refreshLiveHistory() } }
        .onChange(of: ShortDramaProgressStore.shared.historyRevision) { updateFilteredHistory() }
        .onDisappear { loadMoreTask?.cancel() }
    }

    private var roomList: some View {
        GeometryReader { geometry in
            let coverWidth = min(104, max(0, geometry.size.width - 16) * 0.28)
            let candidates = rooms
            ScrollView {
                LazyVStack(spacing: 8) {
                    if candidates.isEmpty { emptyState }
                    ForEach(candidates) { room in
                        candidateRow(room, coverWidth: coverWidth)
                    }
                    if activeSource == .category, let category {
                        pagination(for: category)
                    }
                }
                .padding(.vertical, 8)
            }
            .id(activeSource)
        }
    }

    private var sourceTitle: String {
        switch activeSource {
        case .favorite: "收藏中正在直播"
        case .history: "最近观看"
        case .category: "当前分区"
        }
    }

    private var emptyState: some View {
        let message: String
        let symbol: String
        switch activeSource {
        case .favorite:
            message = "收藏中没有正在直播的房间"
            symbol = "star.fill"
        case .history:
            message = "还没有直播观看记录"
            symbol = "clock.arrow.circlepath"
        case .category:
            message = "此分区没有可切换的直播间"
            symbol = "square.grid.2x2.fill"
        }
        return ContentUnavailableView(
            "暂无可切换直播间",
            systemImage: symbol,
            description: Text(message)
        )
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    @ViewBuilder
    private func candidateRow(_ room: LiveModel, coverWidth: CGFloat) -> some View {
        let isCurrent = room == currentRoom
        let isSwitching = room == switchingRoom
        let row = MacRoomSwitcherRow(
            room: room,
            coverWidth: coverWidth,
            isCurrent: isCurrent,
            isSwitching: isSwitching,
            failureMessage: failure.flatMap { $0.room == room ? $0.message : nil }
        )
        if isCurrent {
            row
        } else {
            Button { onSelect(room) } label: { row }
                .buttonStyle(MacRoomCardButtonStyle())
                .disabled(isSwitching)
                .accessibilityHint("切换到此直播间")
        }
    }

    @ViewBuilder
    private func pagination(for category: CategoryRoomListModel) -> some View {
        if let error = category.error {
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if category.isLoading {
            ProgressView("加载更多…")
                .controlSize(.small)
                .padding(8)
        } else if category.hasMore {
            Button(category.error == nil ? "加载更多" : "重试") {
                loadMoreTask?.cancel()
                loadMoreTask = Task { await category.loadMore() }
            }
        }
    }

    private func refreshLiveHistory() {
        let store = ShortDramaProgressStore.shared
        let classification = store.historyClassification(for: history)
        historyClassification = classification
        store.loadHistory(legacyRooms: history, classification: classification)
        updateFilteredHistory()
    }

    private func updateFilteredHistory() {
        guard activeSource == .history, let historyClassification else { return }
        liveHistory = ShortDramaProgressStore.shared.liveHistory(from: history, classification: historyClassification)
    }
}

private struct MacRoomSwitcherRow: View {
    let room: LiveModel
    let coverWidth: CGFloat
    let isCurrent: Bool
    let isSwitching: Bool
    let failureMessage: String?

    @State private var isHovered = false
    private let shape = RoundedRectangle(cornerRadius: 12)
    private let selectionColor = AppConstants.Colors.accent

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
                            .foregroundStyle(selectionColor)
                            .fixedSize()
                    } else if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在切换直播间")
                    }
                }

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

                if let count = PlaybackDisplay.popularityTitle(room.liveWatchedCount) {
                    Label(count, systemImage: "flame")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("热度 \(count)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(minHeight: 76)
        .background(
            isCurrent ? selectionColor.opacity(0.09) : Color.primary.opacity(isHovered ? 0.10 : 0.04),
            in: shape
        )
        .overlay {
            if isCurrent {
                shape.strokeBorder(selectionColor.opacity(0.32), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 && !isCurrent && !isSwitching }
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        KFImage(URL(string: room.roomCover))
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
