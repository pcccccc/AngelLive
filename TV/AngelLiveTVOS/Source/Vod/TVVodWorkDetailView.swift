import AngelLiveCore
import Kingfisher
import SharedAssets
import SwiftUI
import UIKit

struct TVVodWorkDetailView: View {
    let room: LiveModel
    let model: VodPlaybackModel
    let returnEpisodeID: String?
    let onExit: () -> Void
    let onPlay: (VodEpisode, String?) -> Void

    @FocusState private var focus: Item?
    @State private var sourceOptions: VodEpisodeSourceOptions?
    @State private var selectedGroup = 0
    @State private var reload = 0
    @State private var loadedRevision: Int?
    @State private var restoredEpisodeID: String?

    private enum SectionID: Hashable { case episodes }
    private enum Item: Hashable { case play, retry, exit, episode(String) }

    private var isPrepared: Bool { loadedRevision == reload && !model.isLoadingDetail }

    private var sourceQuery: VodEpisodeSourceOptions.Query? {
        guard isPrepared, let episodeID = model.preferredEpisode?.id else { return nil }
        return .init(episodeID: episodeID, reload: reload)
    }

    private var currentSourceOptions: VodEpisodeSourceOptions? {
        guard let sourceOptions, sourceOptions.query == sourceQuery else { return nil }
        return sourceOptions
    }

    private var supported: Bool { VodHostRouting.isVod(room) }
    private var groups: [TVVodEpisodeRange] { TVVodEpisodeRange.make(from: model.seasonEpisodes) }
    private var episodes: ArraySlice<VodEpisode> {
        let groups = groups
        return groups.indices.contains(selectedGroup) ? groups[selectedGroup].episodes : []
    }

    var body: some View {
        let revision = reload
        let sourceQuery = sourceQuery
        GeometryReader { geometry in
            let inset = TVFullUIPlayerControlMetrics.screenInset
            Group {
                if !supported {
                    status("点播协议不兼容", message: "当前插件版本未提供受支持的点播能力。", canRetry: false)
                } else if !isPrepared {
                    VStack(spacing: 22) {
                        ProgressView().fullUIArcLoadingStyle(size: 64, lineWidth: 2.5).tint(.white)
                        Text("正在加载作品").font(.title3)
                    }
                } else if let error = model.errorMessage {
                    status("无法加载作品", message: error, canRetry: true)
                } else if let detail = model.detail, !detail.episodes.isEmpty {
                    ScrollViewReader { page in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 20) {
                                overview(detail, size: geometry.size, inset: inset)
                                    .focusSection()
                                if let warning = model.progressWarning {
                                    Text(verbatim: warning).font(.footnote).padding(.horizontal, inset)
                                }
                                if detail.kind == .series {
                                    episodeBrowser(detail, page: page)
                                        .padding(.horizontal, inset)
                                        .id(SectionID.episodes)
                                        .focusSection()
                                }
                            }
                            .padding(.bottom, detail.kind == .series ? inset : 0)
                        }
                        .defaultFocus($focus, restoredEpisodeID.map(Item.episode) ?? .play)
                    }
                } else {
                    status("暂无可播放内容", message: "当前作品没有可用的播放信息。", canRetry: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .ignoresSafeArea(.container)
        .environment(\.colorScheme, .dark)
        .task(id: revision) {
            guard !Task.isCancelled, revision == reload, supported else { return }
            loadedRevision = nil
            await model.loadDetail()
            guard !Task.isCancelled, revision == reload else { return }
            if model.detail?.kind == .series,
               let episode = model.detail?.episodes.first(where: { $0.id == returnEpisodeID }) {
                model.selectSeason(id: episode.seasonID)
                selectedGroup = groups.firstIndex { $0.episodes.contains(episode) } ?? 0
                restoredEpisodeID = episode.id
            }
            loadedRevision = revision
        }
        .task(id: sourceQuery) { await discoverSources(for: sourceQuery) }
    }

    private func status(_ title: String, message: String, canRetry: Bool) -> some View {
        VStack(spacing: 22) {
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 24) {
                if canRetry {
                    Button("重试") { reload += 1 }.focused($focus, equals: .retry)
                }
                Button("返回", action: onExit).focused($focus, equals: .exit)
            }
            .buttonStyle(TVVodPillStyle())
        }
        .defaultFocus($focus, canRetry ? .retry : .exit)
    }

    private func overview(_ detail: VodWorkDetail, size: CGSize, inset: CGFloat) -> some View {
        let artwork = detail.heroArtwork(portrait: false, preferredEpisode: model.preferredEpisode)
        let sourceOptions = currentSourceOptions
        return MediaHeroStage(title: detail.title, metadata: detail.displayMetadata(formatTime: tvPlayerTimeLabel),
                              tags: detail.displayTags(sourceCount: sourceOptions?.sources.count ?? 0), synopsis: detail.synopsis,
                              titleFont: .system(size: 50, weight: .bold),
                              height: detail.kind == .series ? min(530, size.height * 0.49) : size.height,
                              inset: inset, topClearance: inset, landscape: true, fitsPoster: artwork.fitsPoster) {
            TVVodArtwork(path: artwork.url, contentMode: artwork.fitsPoster ? .fit : .fill)
        } actions: {
            HStack(spacing: 12) {
                if let episode = model.preferredEpisode {
                    Button { open(episode) } label: {
                        Label(detail.playTitle(for: episode, snapshot: model.progressSnapshot, formatTime: tvPlayerTimeLabel),
                              systemImage: "play.fill")
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
                    .focused($focus, equals: .play)
                    #if !canImport(KSPlayer)
                    .disabled(true)
                    #endif
                }
                if let sourceOptions, sourceOptions.sources.count > 1 { sourcePicker(sourceOptions) }
            }
        }
    }

    private func sourcePicker(_ options: VodEpisodeSourceOptions) -> some View {
        Menu {
            ForEach(options.sources) { source in
                Button {
                    guard currentSourceOptions?.query == options.query else { return }
                    sourceOptions?.select(source.id)
                } label: {
                    if source.id == options.selectedID { Label(source.title, systemImage: "checkmark") }
                    else { Text(verbatim: source.title) }
                }
            }
        } label: {
            Label(options.selectedTitle ?? "选择线路", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel("播放线路")
        .accessibilityValue(options.selectedTitle ?? "默认")
    }

    private func episodeBrowser(_ detail: VodWorkDetail, page: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("分集").font(.system(size: 38, weight: .bold)).accessibilityAddTraits(.isHeader)
            let hasSeasons = detail.hasExplicitSeasons && detail.seasons.count > 1
            let hasRanges = groups.count > 1
            if hasSeasons || hasRanges {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if hasSeasons {
                            ForEach(detail.seasons) { season in
                                picker(season.title, selected: model.selectedSeasonID == season.id) {
                                    restoredEpisodeID = nil
                                    model.selectSeason(id: season.id)
                                    selectedGroup = 0
                                }
                            }
                        }
                        if hasSeasons && hasRanges {
                            Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 18)
                        }
                        if hasRanges {
                            ForEach(groups.indices, id: \.self) { index in
                                picker(groups[index].title, selected: selectedGroup == index) {
                                    restoredEpisodeID = nil
                                    selectedGroup = index
                                }
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
            if episodes.isEmpty {
                Text("暂无可播放剧集").foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(episodes) { episode in
                            let item = Item.episode(episode.id)
                            let lastWatched = model.progressSnapshot?.lastEpisodeID == episode.id
                            Button { open(episode) } label: {
                                let progress = model.progressSnapshot?.episodes[episode.id]
                                MediaCardLabel(title: episode.title, episodeNumber: episode.number, synopsis: episode.synopsis,
                                               duration: (progress?.duration ?? episode.durationHint).map(tvPlayerTimeLabel),
                                               completed: progress?.completed == true, lastWatched: lastWatched,
                                               progress: progress?.fractionWatched, focused: focus == item) {
                                    TVVodArtwork(path: episode.stillURL)
                                }
                                .frame(width: 360)
                            }
                            .buttonStyle(TVEpisodeStillButtonStyle())
                            .focusEffectDisabled()
                            .focused($focus, equals: item)
                            .id(episode.id)
                            #if !canImport(KSPlayer)
                            .disabled(true)
                            #endif
                        }
                    }
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
                .task(id: restoredEpisodeID) {
                    guard let id = restoredEpisodeID, episodes.contains(where: { $0.id == id }) else { return }
                    page.scrollTo(SectionID.episodes, anchor: .top)
                    proxy.scrollTo(id, anchor: .center)
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    focus = .episode(id)
                }
            }
        }
    }

    private func picker(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 23, weight: .medium))
        }
        .buttonStyle(TVVodPillStyle(selected: selected))
        .focusEffectDisabled()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func open(_ episode: VodEpisode) {
        guard isPrepared else { return }
        onPlay(episode, currentSourceOptions?.sourceID(for: episode.id))
    }

    private func discoverSources(for query: VodEpisodeSourceOptions.Query?) async {
        guard !Task.isCancelled, let query, query == sourceQuery,
              let detail = model.detail, let episode = model.preferredEpisode else { return }
        let offered = (try? await VodHostRouting.sources(for: detail, episode: episode)) ?? []
        guard !Task.isCancelled, query == sourceQuery else { return }
        sourceOptions = VodEpisodeSourceOptions(query: query, sources: offered, previous: sourceOptions)
    }
}

struct TVVodEpisodeRange {
    let title: String
    let episodes: ArraySlice<VodEpisode>

    static func make(from episodes: [VodEpisode]) -> [Self] {
        stride(from: 0, to: episodes.count, by: 20).map { start in
            let end = min(start + 20, episodes.count)
            return Self(title: "\(start + 1)–\(end)", episodes: episodes[start..<end])
        }
    }
}

struct TVVodArtwork: View {
    let path: String?
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let path, let url = URL(string: path), !path.isEmpty {
                    if url.isFileURL {
                        if let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                        } else {
                            placeholder
                        }
                    } else {
                        KFImage(url).placeholder { placeholder }.resizable().aspectRatio(contentMode: contentMode)
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        MediaArtworkPlaceholder()
    }
}

struct TVVodEpisodeLabel: View {
    let episode: VodEpisode
    let progress: VodEpisodeProgress?
    let marker: String?
    let showsProgressTime: Bool

    private var metadata: String {
        var parts: [String] = []
        if let duration = progress?.duration ?? episode.durationHint, duration > 0 { parts.append(tvPlayerTimeLabel(duration)) }
        if progress?.completed == true { parts.append("已看完") }
        else if showsProgressTime, let progress, progress.position > 0, progress.duration > 0 {
            parts.append("已观看 \(tvPlayerTimeLabel(progress.position))")
        }
        if let marker { parts.append(marker) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 16) {
            TVVodArtwork(path: episode.stillURL)
                .frame(width: 144, height: 81)
                .overlay(alignment: .bottomLeading) {
                    if let progress, !progress.completed, progress.duration > 0, progress.position > 0 {
                        Rectangle().fill(.white)
                            .frame(width: 144 * min(progress.position / progress.duration, 1), height: 4)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(episode.tvVodTitle).font(.system(size: 28, weight: .semibold)).lineLimit(1)
                if let synopsis = episode.synopsis, !synopsis.isEmpty {
                    Text(verbatim: synopsis).font(.system(size: 21)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Text(verbatim: metadata).monospacedDigit()
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TVVodPillStyle: ButtonStyle {
    var selected = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let bright = selected || focused
        configuration.label
            .foregroundStyle(bright ? Color.black : .white)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(.white.opacity(bright ? 1 : 0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(bright ? 0 : 0.24), lineWidth: 1) }
            .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 8, y: 3)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: focused)
    }
}

private struct TVEpisodeStillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.35)
    }
}

struct TVVodOptionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let focused: Bool
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: TVFullUIPlayerControlMetrics.height, alignment: .leading)
            .contentShape(Rectangle())
            .background(focused ? .white.opacity(0.22) : selected ? .white.opacity(0.08) : .clear,
                        in: .rect(cornerRadius: 14))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(!reduceMotion && focused ? 1.03 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: focused)
    }
}

extension VodEpisode {
    var tvVodTitle: String { displayTitle }
}
