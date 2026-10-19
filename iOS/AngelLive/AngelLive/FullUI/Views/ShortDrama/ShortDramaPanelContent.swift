#if canImport(KSPlayer)
import SwiftUI
import AngelLiveCore
import Kingfisher

struct ShortDramaEpisodesPanelContent: View {
    let room: LiveModel
    let model: ShortDramaPlaybackModel
    let onSelect: (String) -> Void
    let onHeaderDragChanged: (DragGesture.Value) -> Void
    let onHeaderDragEnded: (DragGesture.Value) -> Void
    let onHeaderDragCancelled: () -> Void
    let availableWidth: CGFloat
    let presentationSettled: Bool
    let animateCurrentEpisode: Bool
    @AccessibilityFocusState.Binding var accessibilityFocus: ShortDramaAccessibilityFocus?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var browseGroupID: String?
    @State private var positionedLayout: EpisodeGridLayout?

    private var episodeGroups: [ShortDramaEpisodeGroup] {
        ShortDramaEpisodeGroup.make(from: model.episodes)
    }

    private var browsedGroup: ShortDramaEpisodeGroup? {
        let groups = episodeGroups
        return groups.first { $0.id == browseGroupID }
            ?? groups.first { $0.contains(episodeID: model.selectedEpisodeID) }
            ?? groups.first
    }

    private var columns: [GridItem] {
        let interiorWidth = max(44, availableWidth - 40)
        let widthBasedCount = max(1, Int((interiorWidth + 8) / 52))
        let preferredCount = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        let count = min(preferredCount, widthBasedCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        let group = browsedGroup
        let visibleEpisodes = group?.episodes ?? []
        let scrollEpisodeID = group?.contains(episodeID: model.selectedEpisodeID) == true
            ? model.selectedEpisodeID : visibleEpisodes.first?.id
        VStack(spacing: 0) {
            episodeHeader

            episodeListHeader
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(visibleEpisodes) { episode in
                                episodeCell(episode)
                                    .id(episode.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .task(id: EpisodeScrollTarget(
                        episodeID: scrollEpisodeID,
                        layout: EpisodeGridLayout(
                            groupID: group?.id,
                            episodeIDs: visibleEpisodes.map(\.id),
                            width: viewport.size.width,
                            columnCount: columns.count
                        ),
                        presentationSettled: presentationSettled
                    )) {
                        guard presentationSettled, viewport.size.height > 0,
                              let id = scrollEpisodeID else { return }
                        let layout = EpisodeGridLayout(
                            groupID: group?.id,
                            episodeIDs: visibleEpisodes.map(\.id),
                            width: viewport.size.width,
                            columnCount: columns.count
                        )
                        // A detent's settlement is only the initial positioning gate. Once
                        // positioned, only changing the browsed group, its contents or its
                        // layout repositions the grid; playback samples never change browsing.
                        guard positionedLayout != layout else { return }
                        // Let the lazy grid register stable targets after insertion/reflow.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        positionedLayout = layout
                    }
                }
            }
        }
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: episodeGroups.map(\.id), initial: true) { _, groupIDs in
            // Pin the initial choice for this presentation. If the directory removes it,
            // browsedGroup already resolves to the current episode's group or the first.
            if browseGroupID == nil || !groupIDs.contains(where: { $0 == browseGroupID }) {
                browseGroupID = browsedGroup?.id
            }
        }
    }

    @ViewBuilder
    private var episodeListHeader: some View {
        if episodeGroups.count > 1 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    episodeGroupMenu.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    episodeCount.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    episodeGroupMenu
                    episodeCount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 8) {
                Text("剧集列表")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                episodeCount
            }
        }
    }

    private var episodeCount: some View {
        Text("可播 \(model.episodes.count) 集")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.58))
    }

    private var episodeGroupMenu: some View {
        Menu {
            Picker("集数区间", selection: Binding(
                get: { browsedGroup?.id ?? "" },
                set: { browseGroupID = $0 }
            )) {
                ForEach(episodeGroups) { group in
                    Text(group.title).tag(group.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(browsedGroup?.title ?? "剧集列表")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("集数区间")
        .accessibilityValue(browsedGroup?.title ?? "")
    }

    private var episodeHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            poster
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(room.roomTitle.isEmpty ? room.userName : room.roomTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($accessibilityFocus, equals: .episodesTitle)
                Text("可播 \(model.episodes.count) 集")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                if let providerName = model.selectedEpisode?.cdn.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !providerName.isEmpty {
                    Text(providerName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                } else if let note = model.selectionNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .shortDramaPanelDragRegion(
                onChanged: onHeaderDragChanged,
                onEnded: onHeaderDragEnded,
                onCancelled: onHeaderDragCancelled
            )
        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = URL(string: room.roomCover), !room.roomCover.isEmpty {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }
        }
    }

    private func episodeCell(_ episode: ShortDramaEpisode) -> some View {
        let isSelected = episode.id == model.selectedEpisodeID
        return Button {
            onSelect(episode.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text("\(episode.number)")
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isSelected {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(
                            .variableColor.iterative,
                            options: .speed(0.6),
                            isActive: animateCurrentEpisode
                        )
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 48)
            .background(isSelected ? .white.opacity(0.12) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? .white : .white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "第 \(episode.number) 集，当前集" : "第 \(episode.number) 集")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EpisodeScrollTarget: Equatable {
    let episodeID: String?
    let layout: EpisodeGridLayout
    let presentationSettled: Bool
}

private struct EpisodeGridLayout: Equatable {
    let groupID: String?
    let episodeIDs: [String]
    let width: CGFloat
    let columnCount: Int
}

struct ShortDramaSettingsPanelContent: View {
    @Binding var playbackRate: Float
    @Binding var autoplay: Bool
    let availableWidth: CGFloat
    let onHeaderDragChanged: (DragGesture.Value) -> Void
    let onHeaderDragEnded: (DragGesture.Value) -> Void
    let onHeaderDragCancelled: () -> Void
    @AccessibilityFocusState.Binding var accessibilityFocus: ShortDramaAccessibilityFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("播放设置")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .settingsTitle)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .shortDramaPanelDragRegion(
                    onChanged: onHeaderDragChanged,
                    onEnded: onHeaderDragEnded,
                    onCancelled: onHeaderDragCancelled
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("播放速度")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                        ShortDramaRatePicker(
                            selection: $playbackRate,
                            availableWidth: max(0, availableWidth - 40),
                            onSelect: { _ in }
                        )
                    }

                    Toggle(isOn: $autoplay) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动连播")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                            Text("本集结束后播放下一集")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                    .frame(minHeight: 52)
                    .accessibilityHint("控制本集结束后是否自动播放下一集")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#endif
