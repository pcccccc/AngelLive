#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct MacVodPlayerDrawer: View {
    enum Kind: Hashable {
        case episodes
        case tracks
        case settings

        var title: LocalizedStringKey {
            switch self {
            case .episodes: "选集"
            case .tracks: "字幕与音轨"
            case .settings: "播放设置"
            }
        }
    }

    let kind: Kind
    let model: VodPlaybackModel
    let controller: KSOnDemandPlayerController
    @Binding var autoplayEnabled: Bool
    @Binding var pictureMode: MacVodPictureMode
    @Binding var closeDeadline: ContinuousClock.Instant?
    let canAirPlay: Bool
    let onClose: () -> Void
    let onEpisode: (VodEpisode) -> Void
    let onSource: (String) -> Void
    let onTracks: () -> Void
    let onAirPlay: () -> Void
    let onVideoInfo: () -> Void

    var body: some View {
        MacPlayerDrawer(title: kind.title, onClose: onClose) {
            if kind == .episodes, let detail = model.detail {
                Text("可播 \(detail.episodes.count) 集")
            }
        } content: {
            if kind == .episodes, let detail = model.detail {
                MacVodEpisodeList(detail: detail, snapshot: model.progressSnapshot,
                                  selectedEpisodeID: model.selectedEpisodeID, locatesCurrentEpisode: true,
                                  onSelect: onEpisode)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if kind == .tracks { tracks } else { settings }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var tracks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("字幕", selection: Binding(get: { controller.selectedSubtitleID },
                                                set: { controller.selectSubtitle(id: $0) })) {
                Text("关闭字幕").tag(nil as String?)
                ForEach(controller.subtitleTracks) { track in
                    Text(subtitleTitle(track)).tag(Optional(track.id))
                }
            }
            LabeledContent("字幕时间偏移") {
                Text("\(controller.subtitleDelay, format: .number.sign(strategy: .always()).precision(.fractionLength(1))) 秒")
                    .monospacedDigit()
            }
            HStack {
                Button("−0.5s") { controller.adjustSubtitleDelay(by: -0.5) }
                    .accessibilityLabel("字幕提前 0.5 秒").disabled(controller.subtitleDelay <= -10)
                Button("重置") { controller.resetSubtitleDelay() }
                    .accessibilityLabel("重置字幕时间偏移").disabled(controller.subtitleDelay == 0)
                Button("+0.5s") { controller.adjustSubtitleDelay(by: 0.5) }
                    .accessibilityLabel("字幕延后 0.5 秒").disabled(controller.subtitleDelay >= 10)
            }
            Picker("字幕字号", selection: Binding(get: { controller.subtitleFontSizeTier },
                                                set: { controller.setSubtitleFontSizeTier($0) })) {
                Text("小").tag(OnDemandSubtitleFontSizeTier.small)
                Text("标准").tag(OnDemandSubtitleFontSizeTier.standard)
                Text("大").tag(OnDemandSubtitleFontSizeTier.large)
            }
            .pickerStyle(.segmented)
            Text("支持 SRT、VTT 和 ASS。ASS 使用文本模式，部分定位和样式可能无法显示。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.audioTracks.count > 1 {
                Divider()
                Picker("音轨", selection: Binding(get: { controller.selectedAudioTrackID }, set: {
                    if let id = $0 { controller.selectAudioTrack(id: id) }
                })) {
                    ForEach(controller.audioTracks) { track in
                        Text(verbatim: track.name).tag(Optional(track.id))
                    }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.detail?.kind == .series {
                Toggle("剧集自动连播", isOn: $autoplayEnabled)
                    .toggleStyle(.switch)
                    .tint(AppConstants.Colors.accent)
            }
            Picker("画面比例", selection: $pictureMode) {
                ForEach(MacVodPictureMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if let playback = model.playback, playback.sources.count > 1 {
                Picker("播放线路", selection: Binding(get: { playback.sourceID }, set: {
                    if let id = $0 { onSource(id) }
                })) {
                    if playback.sourceID == nil { Text("默认").tag(nil as String?) }
                    ForEach(playback.sources) { source in
                        Text(verbatim: source.title).tag(Optional(source.id))
                    }
                }
            }
            Divider()
            Button(action: onTracks) { Label("字幕与音轨", systemImage: "captions.bubble") }
            MacPlayerSleepTimerMenu(deadline: $closeDeadline)
            if canAirPlay { Button("AirPlay", systemImage: "airplay.video", action: onAirPlay) }
            Button("视频信息", systemImage: "info.circle", action: onVideoInfo)
                .disabled(controller.coordinator == nil)
        }
    }

    private func subtitleTitle(_ track: OnDemandSubtitleTrack) -> String {
        if let format = track.format { return "\(track.name) · 外挂 \(format.rawValue.uppercased())" }
        return "\(track.name) · 内嵌"
    }
}
#endif
