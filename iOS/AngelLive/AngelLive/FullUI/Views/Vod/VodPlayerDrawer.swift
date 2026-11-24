#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SharedAssets
import SwiftUI

struct VodPlayerDrawer: View {
    enum Kind: Equatable {
        case episodes
        case tracks(TrackSection)
        case settings

        var title: LocalizedStringKey {
            switch self {
            case .episodes: "选集"
            case .tracks: "字幕与播放"
            case .settings: "播放设置"
            }
        }
    }

    enum TrackSection: String, CaseIterable {
        case subtitles = "字幕"
        case audio = "音轨"
        case rate = "倍速"
    }

    let kind: Kind
    let model: VodPlaybackModel
    let controller: KSOnDemandPlayerController
    @Bindable var settings: GeneralSettingModel
    @Binding var rate: Float
    @Binding var pictureMode: VodPictureMode
    let onEpisode: (String) -> Void
    let onSource: (String) -> Void
    let onTracks: () -> Void
    let onClose: () -> Void

    @State private var seasonID: String?
    @State private var episodeGroup: Int?
    @State private var trackSection = TrackSection.subtitles

    private static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2, 3]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    switch kind {
                    case .episodes: episodePicker
                    case .tracks: tracks
                    case .settings: playbackSettings
                    }
                }
                .padding(.horizontal, FullUIPlayerDetailChrome.inset)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .adaptivePanelGlassEffect(cornerRadius: 26)
        .overlay {
            RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onChange(of: kind, initial: true) { _, next in
            switch next {
            case .episodes:
                seasonID = model.selectedEpisode?.seasonID ?? model.detail?.seasons.first?.id
                episodeGroup = nil
            case .tracks(let section):
                trackSection = section
            case .settings:
                break
            }
        }
    }

    private var header: some View {
        HStack {
            Text(kind.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .adaptivePanelCircleGlassEffect()
                    .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭抽屉")
        }
        .padding(.horizontal, FullUIPlayerDetailChrome.inset)
    }

    private var seasonEpisodes: [VodEpisode] {
        guard let episodes = model.detail?.episodes else { return [] }
        guard let seasonID else { return episodes }
        return episodes.filter { $0.seasonID == seasonID }
    }

    @ViewBuilder
    private var episodePicker: some View {
        let seasonPicker = model.detail.flatMap { detail in
            detail.hasExplicitSeasons && detail.seasons.count > 1
                ? VodSeasonPicker(seasons: detail.seasons, selection: seasonID) { id in
                    seasonID = id
                    episodeGroup = 0
                } : nil
        }
        let episodes = seasonEpisodes
        VodEpisodePage(episodes: episodes, preferredID: model.selectedEpisodeID, selection: $episodeGroup, seasonPicker: seasonPicker) { episode in
            VodEpisodeRow(
                episode: episode, progress: model.progressSnapshot?.episodes[episode.id],
                isCurrent: episode.id == model.selectedEpisodeID
            ) {
                if episode.id == model.selectedEpisodeID { onClose() } else { onEpisode(episode.id) }
            }
        }
        if episodes.isEmpty { ContentUnavailableView("暂无分集", systemImage: "film") }
    }

    private var tracks: some View {
        VStack(alignment: .leading, spacing: 8) {
            let sections = controller.audioTracks.count > 1 ? TrackSection.allCases : [.subtitles, .rate]
            Picker("播放轨道", selection: $trackSection) {
                ForEach(sections, id: \.self) { section in
                    Text(verbatim: section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .id(sections)
            switch trackSection {
            case .subtitles: subtitles
            case .audio: audio
            case .rate: rates
            }
        }
    }

    @ViewBuilder
    private var subtitles: some View {
        choiceGroup {
            choice("关闭字幕", selected: controller.selectedSubtitleID == nil) { controller.selectSubtitle(id: nil) }
        }
        subtitleGroup("内嵌字幕", tracks: controller.subtitleTracks.filter { !$0.isExternal })
        subtitleGroup("外挂字幕", tracks: controller.subtitleTracks.filter(\.isExternal))
        if !controller.subtitleTracks.isEmpty {
            Text("时间偏移").font(.subheadline.weight(.semibold))
            Text("\(controller.subtitleDelay, format: .number.precision(.fractionLength(1))) 秒")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("字幕时间偏移")
            HStack(spacing: 8) {
                VodChoiceChip(title: "−0.5s", isSelected: false) { controller.adjustSubtitleDelay(by: -0.5) }
                VodChoiceChip(title: "重置", isSelected: false) { controller.resetSubtitleDelay() }
                VodChoiceChip(title: "+0.5s", isSelected: false) { controller.adjustSubtitleDelay(by: 0.5) }
            }
            Text("字幕字号").font(.subheadline.weight(.semibold))
            Picker("字幕字号", selection: Binding(get: { controller.subtitleFontSizeTier },
                                                set: { controller.setSubtitleFontSizeTier($0) })) {
                ForEach(OnDemandSubtitleFontSizeTier.allCases, id: \.self) { tier in
                    Text(fontTitle(tier)).tag(tier)
                }
            }
            .pickerStyle(.segmented)
        }
        Text("文本模式支持 SRT、VTT 以及 ASS 的基础颜色与对齐。复杂绝对定位需使用位图模式。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func subtitleGroup(_ title: LocalizedStringKey, tracks: [OnDemandSubtitleTrack]) -> some View {
        if !tracks.isEmpty {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            choiceGroup {
                ForEach(tracks) { track in
                    if track.id != tracks.first?.id { choiceDivider }
                    choice(track.name, detail: track.format?.rawValue.uppercased(),
                           selected: controller.selectedSubtitleID == track.id) {
                        controller.selectSubtitle(id: track.id)
                    }
                }
            }
        }
    }

    private var audio: some View {
        choiceGroup {
            ForEach(controller.audioTracks) { track in
                if track.id != controller.audioTracks.first?.id { choiceDivider }
                choice(track.name, selected: controller.selectedAudioTrackID == track.id) {
                    controller.selectAudioTrack(id: track.id)
                }
            }
        }
    }

    private var rates: some View {
        choiceGroup {
            ForEach(Self.rates, id: \.self) { value in
                if value != Self.rates.first { choiceDivider }
                choice(Self.rateTitle(value), selected: value == rate) {
                    rate = value
                }
            }
        }
    }

    @ViewBuilder
    private var playbackSettings: some View {
        if model.detail?.kind == .series {
            Toggle("剧集自动连播", isOn: $settings.vodAutoplayEnabled)
                .tint(FullUIPlayerDetailChrome.accent)
                .frame(minHeight: FullUIPlayerChrome.controlSize)
        }
        Text("画面比例").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
        HStack(spacing: 8) {
            ForEach(VodPictureMode.allCases, id: \.self) { mode in
                VodChoiceChip(title: mode.rawValue, isSelected: pictureMode == mode) {
                    pictureMode = mode
                }
            }
        }
        if let playback = model.playback, playback.sources.count > 1 {
            Text("播放线路").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            choiceGroup {
                ForEach(playback.sources) { source in
                    if source.id != playback.sources.first?.id { choiceDivider }
                    choice(source.title, selected: playback.sourceID == source.id) {
                        if playback.sourceID != source.id { onSource(source.id) }
                    }
                }
            }
        }
        Button(action: onTracks) {
            HStack {
                Text("字幕、音轨与倍速")
                Spacer()
                Image(systemName: "chevron.forward").font(.caption)
            }
            .frame(minHeight: FullUIPlayerChrome.controlSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func choiceGroup<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        VStack(spacing: 0, content: rows)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private var choiceDivider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 14)
    }

    private func choice(_ title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title).font(.subheadline)
                Spacer(minLength: 8)
                if let detail {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: FullUIPlayerChrome.controlSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func fontTitle(_ tier: OnDemandSubtitleFontSizeTier) -> String {
        switch tier {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        }
    }

    static func rateTitle(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}
private extension View {
    @ViewBuilder
    func adaptivePanelGlassEffect(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.interactive().tint(.black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func adaptivePanelCircleGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.interactive().tint(.black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)),
                in: .circle
            )
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }
}
#endif
