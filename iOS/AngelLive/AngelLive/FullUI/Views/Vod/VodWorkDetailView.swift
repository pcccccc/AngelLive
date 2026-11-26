import AngelLiveCore
import SharedAssets
import SwiftUI
import UIKit

struct VodWorkDetailView: View {
    let room: LiveModel
    let presentsOverSource: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var model: VodPlaybackModel
    @State private var sourceOptions: VodEpisodeSourceOptions?
    @Environment(\.fullUIWindowContext) private var windowContext
    @State private var playing = false
    @State private var presentationFailed = false
    @State private var episodeGroup: Int?
    @State private var reload = 0
    @State private var loadedRevision: Int?

    private var sourceQuery: VodEpisodeSourceOptions.Query? {
        guard !playing, loadedRevision == reload, !model.isLoadingDetail,
              let episodeID = model.preferredEpisode?.id else { return nil }
        return .init(episodeID: episodeID, reload: reload)
    }

    private var currentSourceOptions: VodEpisodeSourceOptions? {
        guard let sourceOptions, sourceOptions.query == sourceQuery else { return nil }
        return sourceOptions
    }

    init(room: LiveModel, presentsOverSource: Bool) {
        self.room = room
        self.presentsOverSource = presentsOverSource
        _model = State(initialValue: VodRouting.model(for: room))
    }

    var body: some View {
        GeometryReader { geometry in
            page(geometry)
                .modifier(PlayerPagePan())
                .modifier(PlayerBackSwipe(
                    enabled: !playing,
                    width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                    exitsFullscreen: false,
                    revealsRoomList: presentsOverSource,
                    onReturn: { dismiss() }
                ))
        }
    }

    private func page(_ geometry: GeometryProxy) -> some View {
        let revision = reload
        let sourceQuery = sourceQuery
        return ZStack(alignment: .top) {
            if !VodRouting.isVod(room) {
                ContentUnavailableView("点播协议不兼容", systemImage: "film",
                                       description: Text("当前插件版本未提供受支持的点播能力。"))
            } else if let detail = model.detail {
                detailContent(detail, geometry: geometry)
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("无法加载作品", systemImage: "film")
                } description: {
                    Text(verbatim: error)
                } actions: {
                    Button("重试") { reload += 1 }
                }
            } else {
                ProgressView("正在加载作品")
                    .fullUIArcLoadingStyle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            backBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .fullUITabBarHidden()
        .task(id: revision) {
            guard !Task.isCancelled, revision == reload, !playing, VodRouting.isVod(room) else { return }
            loadedRevision = nil
            await model.loadDetail()
            guard !Task.isCancelled, revision == reload else { return }
            loadedRevision = revision
        }
        .task(id: sourceQuery) { await discoverSources(for: sourceQuery) }
        .alert("无法打开播放器", isPresented: $presentationFailed) {
            Button("好", role: .cancel) {}
        }
        .onDisappear {
            if !playing { model.cancel() }
        }
    }

    private var backBar: some View {
        HStack {
            FullUIPlayerBackButton(centersSymbol: true) { dismiss() }
                .fullUIPlayerCircularControl()
            Spacer()
        }
        .padding(.horizontal, FullUIPlayerDetailChrome.inset)
    }

    private func detailContent(_ detail: VodWorkDetail, geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let height = geometry.size.height + geometry.safeAreaInsets.top
        let portrait = height > width
        let wide = width >= 720
        let artwork = detail.heroArtwork(portrait: portrait, preferredEpisode: model.preferredEpisode)
        let sourceOptions = currentSourceOptions
        let inset: CGFloat = wide ? 32 : 20
        // A movie page has no episode grid below the hero, so the hero fills the visible height.
        let heroHeight = detail.kind == .movie ? height - 24 :
            wide ? min(520, max(360, height * 0.57)) : height * 0.56
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                MediaHeroStage(title: detail.title, metadata: detail.displayMetadata(formatTime: fullUIPlayerTime),
                               tags: detail.displayTags(sourceCount: sourceOptions?.sources.count ?? 0), synopsis: detail.synopsis,
                               titleFont: wide ? .system(size: 36, weight: .bold) : .title.bold(),
                               height: heroHeight, inset: inset, topClearance: geometry.safeAreaInsets.top + 52,
                               landscape: !portrait, fitsPoster: artwork.fitsPoster) {
                    VodArtwork(path: artwork.url, symbol: "film", contentMode: artwork.fitsPoster ? .fit : .fill)
                } actions: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            if let episode = model.preferredEpisode { playButton(episode, detail: detail) }
                            if let sourceOptions, sourceOptions.sources.count > 1 {
                                sourcePicker(sourceOptions).fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        VStack(alignment: .leading, spacing: 10) {
                            if let episode = model.preferredEpisode { playButton(episode, detail: detail) }
                            if let sourceOptions, sourceOptions.sources.count > 1 { sourcePicker(sourceOptions) }
                        }
                    }
                }
                if let warning = model.progressWarning {
                    Text(verbatim: warning).font(.footnote).padding(.horizontal, inset)
                }
                episodes(detail, gridWidth: wide ? width - 2 * inset : nil).padding(.horizontal, inset)
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func sourcePicker(_ options: VodEpisodeSourceOptions) -> some View {
        Menu {
            ForEach(options.sources) { source in
                Button {
                    guard currentSourceOptions?.query == options.query else { return }
                    sourceOptions?.select(source.id)
                } label: {
                    if options.selectedID == source.id { Label(source.title, systemImage: "checkmark") }
                    else { Text(verbatim: source.title) }
                }
            }
        } label: {
            Label(options.selectedTitle ?? "选择线路", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .fullUIPlayerGlass(in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1).allowsHitTesting(false) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放线路")
        .accessibilityValue(options.selectedTitle ?? "默认")
    }

    private func playButton(_ episode: VodEpisode, detail: VodWorkDetail) -> some View {
        Button { open(episode) } label: {
            Label(detail.playTitle(for: episode, snapshot: model.progressSnapshot, formatTime: fullUIPlayerTime),
                  systemImage: "play.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        #if !canImport(KSPlayer)
        .disabled(true)
        #endif
    }

    @ViewBuilder
    private func episodes(_ detail: VodWorkDetail, gridWidth: CGFloat?) -> some View {
        if detail.kind == .series || detail.episodes.isEmpty {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("分集").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                let seasonPicker = detail.hasExplicitSeasons && detail.seasons.count > 1
                    ? VodSeasonPicker(seasons: detail.seasons, selection: model.selectedSeasonID) {
                        model.selectSeason(id: $0)
                        episodeGroup = 0
                    } : nil
                if model.seasonEpisodes.isEmpty {
                    ContentUnavailableView("暂无可播放内容", systemImage: "film")
                }
                VodEpisodePage(episodes: model.seasonEpisodes, preferredID: model.progressSnapshot?.lastEpisodeID,
                               selection: $episodeGroup, gridWidth: gridWidth, seasonPicker: seasonPicker) { episode in
                    let progress = model.progressSnapshot?.episodes[episode.id]
                    let current = episode.id == model.progressSnapshot?.lastEpisodeID
                    Button { open(episode) } label: {
                        MediaCardLabel(title: episode.title, episodeNumber: episode.number, synopsis: episode.synopsis,
                                       duration: (progress?.duration ?? episode.durationHint).map(fullUIPlayerTime),
                                       completed: progress?.completed == true, lastWatched: current,
                                       progress: progress?.fractionWatched, compact: gridWidth == nil) {
                            VodArtwork(path: episode.stillURL, symbol: "film")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(_ episode: VodEpisode) {
        #if canImport(KSPlayer)
        guard !playing, loadedRevision == reload else { return }
        guard let window = windowContext?.window, var presenter = window.rootViewController else {
            presentationFailed = true
            return
        }
        while let next = presenter.presentedViewController { presenter = next }
        let sourceID = currentSourceOptions?.sourceID(for: episode.id)
        let orientation = VodRouting.preferredOrientation(for: room)
        playing = true
        let player = VodPlayerPresentation(window: window, model: model, episode: episode, sourceID: sourceID,
                                           orientation: orientation) { failed in
            playing = false
            episodeGroup = nil
            reload += 1
            presentationFailed = failed
        }
        player.show(from: presenter)
        #endif
    }

    private func discoverSources(for query: VodEpisodeSourceOptions.Query?) async {
        guard !Task.isCancelled, let query, query == sourceQuery,
              let detail = model.detail, let episode = model.preferredEpisode else { return }
        let offered = (try? await VodRouting.sources(for: detail, episode: episode)) ?? []
        guard !Task.isCancelled, query == sourceQuery else { return }
        sourceOptions = VodEpisodeSourceOptions(query: query, sources: offered, previous: sourceOptions)
    }
}
