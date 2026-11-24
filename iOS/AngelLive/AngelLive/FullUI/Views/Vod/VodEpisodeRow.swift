import AngelLiveCore
import Kingfisher
import SharedAssets
import SwiftUI
import UIKit

struct VodEpisodeRow: View {
    let episode: VodEpisode
    let progress: VodEpisodeProgress?
    var isCurrent = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VodArtwork(path: episode.stillURL, symbol: "film")
                    .frame(width: 96, height: 54)
                    .overlay(alignment: .bottomLeading) {
                        if let progress, !progress.completed, progress.position > 0, progress.duration > 0 {
                            Capsule().fill(.white)
                                .frame(width: 96 * min(1, progress.position / progress.duration), height: 2.5)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(episode.number) 集 · \(episode.title)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    details
                }
                Spacer(minLength: 0)
                if progress?.completed == true {
                    Text("已看完").font(.caption2).foregroundStyle(.secondary)
                }
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityLabel("观看位置")
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    @ViewBuilder
    private var details: some View {
        Group {
            if let synopsis = episode.synopsis, !synopsis.isEmpty {
                Text(verbatim: synopsis)
            } else if let duration = episode.durationHint {
                Text(fullUIPlayerTime(duration))
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }
}

struct VodArtwork: View {
    let path: String?
    let symbol: String
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        Color.secondary.opacity(0.12)
            .overlay {
                if let path, let url = URL(string: path) {
                    if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    } else {
                        KFImage(url)
                            .placeholder { placeholder }
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        MediaArtworkPlaceholder(symbol: symbol)
    }
}

struct VodSeasonPicker: View {
    let seasons: [VodSeason]
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            Picker("选择季", selection: Binding(get: { selection }, set: { if let id = $0 { onSelect(id) } })) {
                ForEach(seasons) { season in Text(verbatim: season.title).tag(Optional(season.id)) }
            }
        } label: {
            Label(seasons.first { $0.id == selection }?.title ?? "选择季", systemImage: "chevron.up.chevron.down")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 34)
                .background(.white.opacity(0.10), in: Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择季")
    }
}

struct VodChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : .white.opacity(0.85))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(.white.opacity(isSelected ? 1 : 0.06), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(isSelected ? 0 : 0.32)) }
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct VodEpisodePage<Row: View>: View {
    let episodes: [VodEpisode]
    let preferredID: String?
    @Binding var selection: Int?
    var gridWidth: CGFloat?
    var seasonPicker: VodSeasonPicker?
    @ViewBuilder let row: (VodEpisode) -> Row

    var body: some View {
        let pageSize = 20
        let offsets = Array(stride(from: 0, to: episodes.count, by: pageSize))
        let preferred = (episodes.firstIndex { $0.id == preferredID } ?? 0) / pageSize
        let page = min(selection ?? preferred, max(0, offsets.count - 1))
        if offsets.count > 1 || seasonPicker != nil {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if let seasonPicker { seasonPicker }
                    if seasonPicker != nil && offsets.count > 1 {
                        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 18)
                    }
                    ForEach(offsets.count > 1 ? offsets : [], id: \.self) { offset in
                        let end = min(episodes.count, offset + pageSize)
                        VodChoiceChip(title: "\(offset + 1)–\(end)", isSelected: page == offset / pageSize) {
                            selection = offset / pageSize
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel("分集区间")
        }
        let items = ForEach(episodes.dropFirst(page * pageSize).prefix(pageSize), content: row)
        if let gridWidth {
            let count = max(2, Int((gridWidth + 18) / 258))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .topLeading), count: count),
                      alignment: .leading, spacing: 20) { items }
        } else {
            items
        }
    }
}
