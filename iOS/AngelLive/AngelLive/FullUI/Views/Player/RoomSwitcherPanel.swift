import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct RoomSwitcherPanel: View {
    let content: RoomSwitcherListContent
    @Binding var selectedSource: RoomSwitchSource
    let onSelect: (LiveModel) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoomSwitcherHeader(title: "换台", selectedSource: $selectedSource) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭换台")
            }

            GeometryReader { geometry in
                ScrollView {
                    RoomSwitcherRows(
                        content: content,
                        coverWidth: RoomSwitcherRows.coverWidth(in: geometry.size.width),
                        onSelect: onSelect
                    )
                    .padding(.horizontal, FullUIPlayerDetailChrome.inset)
                    .padding(.vertical, 8)
                }
                .id(selectedSource)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速换台")
        .accessibilityActions {
            Button("关闭换台", action: onDismiss)
        }
    }
}

struct RoomSwitcherListContent {
    let currentRoom: LiveModel
    let favorites: [LiveModel]
    let history: [LiveModel]
    let category: [LiveModel]
    let source: RoomSwitchSource
    let switchingRoomID: String?
    let failedRoomID: String?
    let failureMessage: String?
    let canLoadMoreCategory: () -> Bool
    let isLoadingMoreCategory: Bool
    let onLoadMoreCategory: (() async -> [LiveModel])?

    var rooms: [LiveModel] {
        RoomSwitchCandidates.orderedRooms(for: source, favorites: favorites, history: history,
                                          category: category, includesOnDemand: true)
            .map { $0 == currentRoom ? currentRoom : $0 }
    }

    var emptyDescription: String {
        switch source {
        case .favorite: "收藏中没有其他正在直播的房间"
        case .history: "还没有其他观看记录"
        case .category: "从直播分区进入后，这里会显示同分区直播间"
        }
    }
}

struct RoomSwitcherRows: View {
    let content: RoomSwitcherListContent
    let coverWidth: CGFloat
    let onSelect: (LiveModel) -> Void

    var body: some View {
        let rooms = content.rooms

        LazyVStack(spacing: 8) {
            if rooms.isEmpty {
                emptyState
            }

            ForEach(rooms) { room in
                let row = RoomSwitcherRow(
                    room: room,
                    coverWidth: coverWidth,
                    isCurrent: room == content.currentRoom,
                    isSwitching: room.id == content.switchingRoomID,
                    failureMessage: room.id == content.failedRoomID ? content.failureMessage : nil
                )
                if room == content.currentRoom {
                    row
                } else {
                    Button { onSelect(room) } label: { row }
                        .buttonStyle(.plain)
                        .disabled(room.id == content.switchingRoomID)
                }
            }

            if content.source == .category, content.canLoadMoreCategory(), let onLoadMoreCategory = content.onLoadMoreCategory {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .accessibilityLabel("正在加载更多直播间")
                    .task {
                        guard !content.isLoadingMoreCategory else { return }
                        _ = await onLoadMoreCategory()
                    }
            }
        }
    }

    static func coverWidth(in containerWidth: CGFloat) -> CGFloat {
        let rowWidth = containerWidth - 2 * FullUIPlayerDetailChrome.inset
        return min(104, max(0, rowWidth - 16) * 0.28)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: content.source.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("暂无可切换直播间")
                .font(.subheadline.weight(.semibold))
            Text(content.emptyDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct RoomSwitcherRow: View {
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

struct RoomActionDock: View {
    let room: LiveModel
    let onOpenSwitcher: () -> Void
    let onClearChat: () -> Void
    var onJumpToLatestChat: (() -> Void)?

    var body: some View {
        RoomSwitcherHeader(title: "聊天", selectedSource: nil) {
            RoomSwitcherOpenButton(action: onOpenSwitcher)
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
}

private struct RoomSwitcherOpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("换台")
                    .font(.footnote.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: FullUIPlayerDetailChrome.pillHeight)
            .background(FullUIPlayerDetailChrome.pillFill, in: Capsule())
            .frame(minWidth: FullUIPlayerChrome.controlSize, minHeight: FullUIPlayerChrome.controlSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("换台")
    }
}

private struct RoomSwitcherHeader<Actions: View>: View {
    let title: LocalizedStringKey
    let selectedSource: Binding<RoomSwitchSource>?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            if let selectedSource {
                sourceMenu(selection: selectedSource)
            }

            Spacer(minLength: 0)

            actions()
        }
        .frame(minHeight: FullUIPlayerChrome.controlSize)
        .padding(.horizontal, FullUIPlayerDetailChrome.inset)
    }

    private func sourceMenu(selection: Binding<RoomSwitchSource>) -> some View {
        Menu {
            Picker("来源", selection: selection) {
                ForEach(RoomSwitchSource.allCases, id: \.self) { source in
                    Label(source.title, systemImage: source.systemImage)
                        .tag(source)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("·")
                    .accessibilityHidden(true)
                Text(selection.wrappedValue.inlineTitle)
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
        .tint(FullUIPlayerDetailChrome.accent)
        .menuIndicator(.hidden)
        .accessibilityLabel("换台来源")
        .accessibilityValue(selection.wrappedValue.inlineTitle)
    }
}

extension RoomSwitchSource {
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
