#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct TVVodSelectionPanel: View {
    enum Kind: Equatable {
        case episodes, tracks, rate, settings

        var title: String {
            switch self {
            case .episodes: "选集"
            case .tracks: "字幕与音轨"
            case .rate, .settings: "播放设置"
            }
        }
    }

    enum Page: Equatable { case main, seasons, ranges }

    private enum Item: Hashable {
        case close, seasonPicker, rangePicker, season(String), range(Int), episode(String)
        case subtitle(String?), audio(Int32), delayDown, delayReset, delayUp, font(OnDemandSubtitleFontSizeTier)
        case rate(Float), autoplay, picture(TVVodPictureMode), source(String)
    }

    let kind: Kind
    let model: VodPlaybackModel
    let controller: KSOnDemandPlayerController
    let settings: GeneralSettingModel
    @Binding var page: Page
    @Binding var rate: Float
    @Binding var pictureMode: TVVodPictureMode
    let onSelect: (String) -> Void
    let onSource: (String) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Item?
    @State private var seasonID: String?
    @State private var groupIndex = 0
    @State private var requestedFocus: Item = .close

    private static let rates: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private var seasons: [VodSeason] { model.detail?.seasons ?? [] }
    private var seasonEpisodes: [VodEpisode] {
        guard let detail = model.detail else { return [] }
        guard let seasonID else { return detail.episodes }
        return detail.episodes.filter { $0.seasonID == seasonID }
    }
    private var groups: [TVVodEpisodeRange] { TVVodEpisodeRange.make(from: seasonEpisodes) }
    private var group: TVVodEpisodeRange? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }
    private var hasSeasonPicker: Bool { model.detail?.hasExplicitSeasons == true && seasons.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            if kind == .episodes, page == .main { episodeFilters }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        switch kind {
                        case .episodes: episodeChoices
                        case .tracks: trackChoices
                        case .rate, .settings: settingChoices
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentMargins(.vertical, 10, for: .scrollContent)
                .task(id: requestedFocus) {
                    let target = requestedFocus
                    proxy.scrollTo(target, anchor: .center)
                    await Task.yield()
                    guard !Task.isCancelled, requestedFocus == target else { return }
                    focus = target
                }
            }
            Spacer(minLength: 0)
        }
        .tvPlayerPanelSurface()
        .onAppear(perform: prepare)
        .onChange(of: page) { previous, current in
            switch current {
            case .seasons: requestedFocus = seasonID.map(Item.season) ?? .close
            case .ranges: requestedFocus = .range(groupIndex)
            case .main:
                requestedFocus = previous == .seasons ? .seasonPicker : .rangePicker
            }
        }
    }

    private var header: some View {
        TVPlayerPanelHeader(title: Text(title), subtitle: subtitle.map { Text(verbatim: $0) }) {
            TVPlayerPanelCloseButton(isFocused: focus == .close, action: onClose)
                .focused($focus, equals: .close)
                .accessibilityLabel("关闭\(kind.title)")
        }
    }

    private var title: String {
        switch page {
        case .main: kind.title
        case .seasons: "选择季"
        case .ranges: "选择剧集区间"
        }
    }

    private var subtitle: String? {
        switch kind {
        case .episodes: model.selectedEpisode?.tvVodTitle
        case .tracks: nil
        case .rate, .settings: "当前：\(tvVodRateLabel(rate))"
        }
    }

    @ViewBuilder
    private var episodeFilters: some View {
        if hasSeasonPicker || groups.count > 1 {
            VStack(spacing: 4) {
                if hasSeasonPicker, let season = seasons.first(where: { $0.id == seasonID }) {
                    option(season.title, item: .seasonPicker, opensPage: true) { page = .seasons }
                        .accessibilityLabel("选择季")
                        .accessibilityValue(season.title)
                }
                if groups.count > 1, let group {
                    option("区间：\(group.title)", item: .rangePicker, opensPage: true) { page = .ranges }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private var episodeChoices: some View {
        switch page {
        case .seasons:
            ForEach(seasons) { season in
                option(season.title, item: .season(season.id), selected: seasonID == season.id) {
                    if seasonID != season.id {
                        seasonID = season.id
                        groupIndex = 0
                    }
                    page = .main
                }
            }
        case .ranges:
            ForEach(groups.indices, id: \.self) { index in
                option(groups[index].title, item: .range(index), selected: groupIndex == index) {
                    groupIndex = index
                    page = .main
                }
            }
        case .main:
            if let group {
                ForEach(group.episodes) { episode in
                    let selected = model.selectedEpisodeID == episode.id
                    row(.episode(episode.id), selected: selected) { onSelect(episode.id) } label: {
                        TVVodEpisodeLabel(episode: episode, progress: model.progressSnapshot?.episodes[episode.id],
                                          marker: selected ? "正在播放" : nil, showsProgressTime: true)
                    }
                }
            } else {
                Text("暂无可播放剧集").foregroundStyle(.secondary).padding(20)
            }
        }
    }

    private var trackChoices: some View {
        Group {
            heading("字幕")
            option("关闭字幕", item: .subtitle(nil), selected: controller.selectedSubtitleID == nil) {
                controller.selectSubtitle(id: nil)
            }
            subtitleGroup("内嵌字幕", tracks: controller.subtitleTracks.filter { !$0.isExternal })
            subtitleGroup("外挂字幕", tracks: controller.subtitleTracks.filter(\.isExternal))
            if controller.subtitleTracks.contains(where: { $0.format == .ass }) {
                Text("ASS 字幕的部分定位和样式可能因播放内核而异。")
                    .font(.system(size: 21)).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            if !controller.subtitleTracks.isEmpty {
                heading("字幕时间偏移")
                option("−0.5 秒", item: .delayDown) { controller.adjustSubtitleDelay(by: -0.5) }
                    .disabled(controller.subtitleDelay <= -10)
                option(String(format: "重置（当前 %+.1f 秒）", controller.subtitleDelay), item: .delayReset) {
                    controller.resetSubtitleDelay()
                }
                option("+0.5 秒", item: .delayUp) { controller.adjustSubtitleDelay(by: 0.5) }
                    .disabled(controller.subtitleDelay >= 10)
                heading("字幕字号")
                ForEach(OnDemandSubtitleFontSizeTier.allCases, id: \.self) { tier in
                    option(fontTitle(tier), item: .font(tier), selected: controller.subtitleFontSizeTier == tier) {
                        controller.setSubtitleFontSizeTier(tier)
                    }
                }
            }
            if !controller.audioTracks.isEmpty {
                heading("音轨")
                ForEach(controller.audioTracks) { track in
                    option(track.name, item: .audio(track.id), selected: controller.selectedAudioTrackID == track.id) {
                        controller.selectAudioTrack(id: track.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subtitleGroup(_ title: String, tracks: [OnDemandSubtitleTrack]) -> some View {
        if !tracks.isEmpty {
            heading(title)
            ForEach(tracks) { track in
                option(subtitleTitle(track), item: .subtitle(track.id), selected: controller.selectedSubtitleID == track.id) {
                    controller.selectSubtitle(id: track.id)
                }
            }
        }
    }

    private func subtitleTitle(_ track: OnDemandSubtitleTrack) -> String {
        guard let format = track.format?.rawValue.uppercased(),
              !track.name.localizedCaseInsensitiveContains(format) else { return track.name }
        return "\(track.name) · \(format)"
    }

    private var settingChoices: some View {
        @Bindable var settings = settings
        return Group {
            if model.detail?.kind == .series {
                Toggle("剧集自动连播", isOn: $settings.vodAutoplayEnabled)
                    .padding(.horizontal, 20)
                    .frame(minHeight: TVFullUIPlayerControlMetrics.height)
                    .focused($focus, equals: .autoplay)
                    .id(Item.autoplay)
            }
            heading("画面比例")
            ForEach(TVVodPictureMode.allCases, id: \.self) { mode in
                option(mode.rawValue, item: .picture(mode), selected: pictureMode == mode) { pictureMode = mode }
            }
            heading("倍速")
            ForEach(Self.rates, id: \.self) { value in
                option(tvVodRateLabel(value), item: .rate(value), selected: rate == value) { rate = value }
            }
            if let playback = model.playback, playback.sources.count > 1 {
                heading("播放线路")
                ForEach(playback.sources) { source in
                    option(source.title, item: .source(source.id), selected: source.id == playback.sourceID) {
                        if source.id != playback.sourceID { onSource(source.id) }
                    }
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 20).padding(.top, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private func option(_ title: String, item: Item, selected: Bool = false, opensPage: Bool = false,
                        action: @escaping () -> Void) -> some View {
        row(item, selected: selected, action: action) {
            HStack(spacing: 14) {
                Text(title).font(.system(size: 28, weight: focus == item || selected ? .semibold : .regular))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                } else if opensPage {
                    Image(systemName: "chevron.forward").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row<Label: View>(_ item: Item, selected: Bool, action: @escaping () -> Void,
                                  @ViewBuilder label: () -> Label) -> some View {
        Button(action: action, label: label)
            .buttonStyle(TVVodOptionStyle(focused: focus == item, selected: selected))
            .focused($focus, equals: item)
            .id(item)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func prepare() {
        switch kind {
        case .episodes:
            seasonID = model.selectedEpisode?.seasonID ?? seasons.first?.id
            groupIndex = groups.firstIndex { group in
                group.episodes.contains { $0.id == model.selectedEpisodeID }
            } ?? 0
            requestedFocus = group?.episodes.first(where: { $0.id == model.selectedEpisodeID })
                .map { .episode($0.id) } ?? group?.episodes.first.map { .episode($0.id) } ?? .close
        case .tracks: requestedFocus = .subtitle(controller.selectedSubtitleID)
        case .rate: requestedFocus = .rate(rate)
        case .settings: requestedFocus = model.detail?.kind == .series ? .autoplay : .picture(pictureMode)
        }
    }

    private func fontTitle(_ tier: OnDemandSubtitleFontSizeTier) -> String {
        switch tier {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        }
    }
}

func tvVodRateLabel(_ rate: Float) -> String {
    "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
}
#endif
