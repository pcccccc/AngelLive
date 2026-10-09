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
    let animateCurrentEpisode: Bool
    @AccessibilityFocusState.Binding var accessibilityFocus: ShortDramaAccessibilityFocus?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let interiorWidth = max(44, availableWidth - 40)
        let widthBasedCount = max(1, Int((interiorWidth + 8) / 52))
        let preferredCount = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        let count = min(preferredCount, widthBasedCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            episodeHeader

            HStack(spacing: 8) {
                Text("剧集列表")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("可播 \(model.episodes.count) 集")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.episodes) { episode in
                        episodeCell(episode)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
