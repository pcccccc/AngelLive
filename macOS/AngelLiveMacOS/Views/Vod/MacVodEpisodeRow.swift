#if canImport(KSPlayer)
import AngelLiveCore
import AppKit
import Kingfisher
import SharedAssets
import SwiftUI

struct MacVodArtwork: View {
    let path: String?
    var contentMode: SwiftUI.ContentMode = .fill
    @State private var failed = false

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay { artwork }
            .clipped()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if let path, !path.isEmpty, let url = URL(string: path) {
            if url.isFileURL {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
                } else { placeholder }
            } else if failed {
                placeholder
            } else {
                KFImage(url)
                    .placeholder { placeholder }
                    .onFailure { _ in failed = true }
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        MediaArtworkPlaceholder()
    }
}

struct MacVodEpisodeRow: View {
    let episode: VodEpisode
    let progress: VodEpisodeProgress?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MacVodArtwork(path: episode.stillURL)
                    .frame(width: 96, height: 54)
                    .overlay(alignment: .bottomLeading) {
                        if let progress, !progress.completed, progress.duration > 0, progress.position > 0 {
                            Rectangle().fill(.white)
                                .frame(width: 96 * min(progress.position / progress.duration, 1), height: 2.5)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: episode.macVodTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let synopsis = episode.synopsis, !synopsis.isEmpty {
                        Text(verbatim: synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    if let duration = progress?.duration ?? episode.durationHint, duration > 0 {
                        Text(macPlayerTime(duration)).monospacedDigit()
                    }
                    if progress?.completed == true { Text("已看完") }
                    if isSelected { Image(systemName: "play.fill").accessibilityLabel("观看位置") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.primary.opacity(isSelected ? 0.10 : isHovered ? 0.06 : 0), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension VodEpisode {
    var macVodTitle: String { displayTitle }
}

struct MacVodEpisodeList: View {
    let detail: VodWorkDetail
    let snapshot: VodProgressSnapshot?
    let selectedEpisodeID: String?
    var scrolls = true
    var locatesCurrentEpisode = false
    var gridWidth: CGFloat?
    let onSelect: (VodEpisode) -> Void

    @State private var seasonID: String?
    @State private var page: Int?
    private let pageSize = 20

    private var currentSeasonID: String? {
        seasonID ?? detail.episodes.first { $0.id == selectedEpisodeID }?.seasonID ?? detail.seasons.first?.id
    }

    private var seasonEpisodes: [VodEpisode] {
        guard let currentSeasonID else { return detail.episodes }
        return detail.episodes.filter { $0.seasonID == currentSeasonID }
    }

    private var currentPage: Int {
        page ?? (seasonEpisodes.firstIndex { $0.id == selectedEpisodeID } ?? 0) / pageSize
    }

    private var pageEpisodes: ArraySlice<VodEpisode> {
        seasonEpisodes.dropFirst(currentPage * pageSize).prefix(pageSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !locatesCurrentEpisode {
                Text("分集").font(.system(size: 18, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
            }
            let hasSeasons = detail.hasExplicitSeasons && detail.seasons.count > 1
            let hasRanges = seasonEpisodes.count > pageSize
            if hasSeasons || hasRanges {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if hasSeasons {
                            ForEach(detail.seasons) { season in
                                selector(season.title, selected: season.id == currentSeasonID) {
                                    seasonID = season.id
                                    page = nil
                                }
                            }
                        }
                        if hasSeasons && hasRanges {
                            Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 14)
                                .padding(.horizontal, 4)
                        }
                        if hasRanges {
                            ForEach(0..<((seasonEpisodes.count - 1) / pageSize + 1), id: \.self) { index in
                                let start = index * pageSize
                                let first = seasonEpisodes[start].number
                                let last = seasonEpisodes[min(start + pageSize, seasonEpisodes.count) - 1].number
                                selector("\(first)–\(last)", selected: currentPage == index) { page = index }
                            }
                        }
                    }
                }
                .scrollClipDisabled()
                .padding(.bottom, 16)
            }
            if pageEpisodes.isEmpty {
                Text("暂无可播放分集").foregroundStyle(.secondary)
            } else if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { rows }
                        .task(id: pageEpisodes.map(\.id)) {
                            let target = locatesCurrentEpisode && pageEpisodes.contains { $0.id == selectedEpisodeID }
                                ? selectedEpisodeID : pageEpisodes.first?.id
                            if let target { proxy.scrollTo(target, anchor: locatesCurrentEpisode ? .center : .top) }
                        }
                }
            } else {
                let wide = gridWidth != nil
                let count = gridWidth.map { max(2, Int(($0 + 20) / 260)) } ?? 1
                let columns = Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .topLeading), count: count)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(pageEpisodes) { episode in
                        let progress = snapshot?.episodes[episode.id]
                        Button { onSelect(episode) } label: {
                            MediaCardLabel(title: episode.title, episodeNumber: episode.number, synopsis: episode.synopsis,
                                           duration: (progress?.duration ?? episode.durationHint).map(macPlayerTime),
                                           completed: progress?.completed == true, lastWatched: episode.id == selectedEpisodeID,
                                           progress: progress?.fractionWatched, compact: !wide) {
                                MacVodArtwork(path: episode.stillURL)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        LazyVStack(spacing: 2) {
            ForEach(pageEpisodes) { episode in
                MacVodEpisodeRow(episode: episode, progress: snapshot?.episodes[episode.id],
                                 isSelected: episode.id == selectedEpisodeID, action: { onSelect(episode) })
                    .id(episode.id)
            }
        }
    }

    private func selector(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 12)
                .foregroundStyle(selected ? Color.black : .white.opacity(0.85))
                .frame(height: 28)
                .background(.white.opacity(selected ? 1 : 0.06), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(selected ? 0 : 0.32)) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
