import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct TVPlaybackSleepTimer: Equatable {
    let minutes: Int
    let deadline: ContinuousClock.Instant

    var remainingTime: String {
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = max(0, remaining.seconds + (remaining.attoseconds > 0 ? 1 : 0))
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }
}

struct TVLivePlayerSettingsPanel: View, TVSettingsPanelRows {
    enum Page: Hashable {
        case menu, danmaku, subtitles, playback, sleepTimer

        var title: LocalizedStringKey {
            switch self {
            case .menu: "设置"
            case .danmaku: "弹幕"
            case .subtitles: "字幕与翻译"
            case .playback: "播放设置"
            case .sleepTimer: "定时关闭"
            }
        }
    }

    @Environment(RoomInfoViewModel.self) private var room
    @Environment(\.accessibilityReduceMotion) fileprivate var reduceMotion
    @FocusState private var focusedItem: Item?

    let page: Page
    let returnsFrom: Item?
    let sleepTimer: TVPlaybackSleepTimer?
    let onSetSleepTimer: (Int) -> Void
    let onOpen: (Page) -> Void
    let languageSheetDismissal: Int
    let onStatistics: () -> Void
    let onFavorite: () -> Void
    let onChooseLanguage: () -> Void
    let onClose: () -> Void

    @Environment(AppState.self) private var app
    fileprivate var focus: FocusState<Item?>.Binding { $focusedItem }

    enum Item: Hashable {
        case enabled, color, size(Int), alpha(Int), speed(Int), area(Int), keywords
        case subtitleEnabled, language, resource, translate, quality(DefaultPlaybackQuality)
        case close, danmaku, subtitles, playback, sleepTimer, sleepTimerOption(Int), statistics, favorite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVPlayerPanelHeader(title: Text(page.title)) {
                TVPlayerPanelCloseButton(isFocused: focusedItem == .close, action: onClose)
                    .focused($focusedItem, equals: .close)
            }
            if page == .menu, !room.isOnDemand {
                TVLivePlayerRoomIdentity(room: room.currentRoom, translatesTitle: !room.isTVUIAuditFixture)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case .menu: menu
                    case .danmaku: TVDanmakuPanelOptions(settings: danmaku, focus: $focusedItem)
                    case .subtitles: subtitleSettings
                    case .playback: playbackSettings
                    case .sleepTimer: sleepTimerOptions
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .clipped()
        }
        .tvPlayerPanelSurface()
        .task(id: page) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            switch page {
            case .menu: focusedItem = returnsFrom ?? (room.supportsDanmu ? .danmaku : .subtitles)
            case .danmaku: focusedItem = .enabled
            case .subtitles: focusedItem = .subtitleEnabled
            case .playback: focusedItem = .quality(defaultQuality.wrappedValue)
            case .sleepTimer: focusedItem = .sleepTimerOption(sleepTimer?.minutes ?? 0)
            }
        }
        .onChange(of: languageSheetDismissal) {
            if page == .subtitles {
                focusedItem = room.subtitlePlayback.phase == .manualSelectionRequired ? .language : .subtitleEnabled
            }
        }
    }

    private var defaultQuality: Binding<DefaultPlaybackQuality> {
        #if DEBUG
        if let audit = room.tvUIAuditSettings {
            @Bindable var audit = audit
            return $audit.defaultPlaybackQuality
        }
        #endif
        @Bindable var settings = app.playerSettingsViewModel
        return $settings.defaultPlaybackQuality
    }

    private var translationEnabled: Binding<Bool> {
        #if DEBUG
        if let audit = room.tvUIAuditSettings {
            @Bindable var audit = audit
            return $audit.isDanmakuTranslationEnabled
        }
        #endif
        @Bindable var translation = RoomTranslationSettings.shared
        return $translation.isDanmakuEnabled
    }

    private var playbackSettings: some View {
        section("默认画质") {
            ForEach(DefaultPlaybackQuality.allCases, id: \.self) { quality in
                row("\(quality.title)", item: .quality(quality), opensPanel: false,
                    isSelected: defaultQuality.wrappedValue == quality) {
                    defaultQuality.wrappedValue = quality
                }
            }
        }
        .accessibilityHint("进入直播间时按可用画质尽量匹配")
    }

    private var subtitleSettings: some View {
        let playback = room.subtitlePlayback
        let activation = playback.activationID
        return VStack(alignment: .leading, spacing: 8) {
            row(playback.isEnabled ? "关闭实时字幕" : "开启实时字幕", item: .subtitleEnabled,
                opensPanel: false) {
                if playback.isEnabled { playback.stop() }
                else { playback.startAutomatically(activationID: activation) }
            }
            if playback.isEnabled {
                if let message = playback.statusMessage {
                    Text(message).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
                }
                switch playback.phase {
                case .manualSelectionRequired:
                    row("选择主播语言", item: .language, action: onChooseLanguage)
                case .modelDownloadRequired, .speechResourcesRequired:
                    row(playback.phase == .modelDownloadRequired ? "下载字幕识别文件并继续" :
                            "下载\(playback.sourceLanguageDisplayName ?? "系统")语音包并继续",
                        item: .resource, opensPanel: false) { playback.prepareResources(activationID: activation) }
                case .failed:
                    row("重试实时字幕", item: .resource, opensPanel: false) {
                        playback.startAutomatically(activationID: activation)
                    }
                default: EmptyView()
                }
            }
            if room.supportsDanmu {
                toggleRow("自动翻译弹幕", item: .translate, value: translationEnabled.wrappedValue) {
                    translationEnabled.wrappedValue.toggle()
                }
            }
        }
    }

    private var danmaku: any TVPanelDanmakuSettings {
        #if DEBUG
        if let audit = room.tvUIAuditSettings { return audit }
        #endif
        return app.danmuSettingsViewModel
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("常用") {
                if room.supportsDanmu {
                    row("弹幕", symbol: "captions.bubble", item: .danmaku) { onOpen(.danmaku) }
                }
                row("字幕与翻译", symbol: "captions.bubble.fill", item: .subtitles) { onOpen(.subtitles) }
            }
            Divider().overlay(.white.opacity(0.12))
            section("更多") {
                row("播放设置", symbol: "gearshape", item: .playback) { onOpen(.playback) }
                row("定时关闭", symbol: "timer", item: .sleepTimer, countdown: sleepTimer) { onOpen(.sleepTimer) }
                row("视频信息", symbol: "chart.bar.xaxis", item: .statistics, action: onStatistics)
                row(room.currentRoomIsLiked ? "取消收藏" : "收藏直播间",
                    symbol: room.currentRoomIsLiked ? "heart.fill" : "heart",
                    item: .favorite, opensPanel: false, action: onFavorite)
                    .disabled(room.currentRoomLikeLoading)
            }
        }
        .padding(.top, 16)
    }

    private var sleepTimerOptions: some View {
        VStack(spacing: 0) {
            ForEach([0, 15, 30, 60, 90, 120], id: \.self) { minutes in
                row(minutes == 0 ? "关闭" : "\(minutes) 分钟", item: .sleepTimerOption(minutes),
                    opensPanel: false, isSelected: minutes == (sleepTimer?.minutes ?? 0)) {
                    onSetSleepTimer(minutes)
                }
            }
        }
    }

}


@MainActor
private protocol TVPanelDanmakuSettings: AnyObject {
    var showDanmu: Bool { get set }
    var showColorDanmu: Bool { get set }
    var danmuFontSize: Int { get set }
    var danmuAlpha: Double { get set }
    var danmuAlphaString: String { get set }
    var danmuSpeed: Double { get set }
    var danmuSpeedIndex: Int { get set }
    var danmuAreaIndex: Int { get set }
    var blockedKeywords: [String] { get }
    func keywordSheet(isPresented: Binding<Bool>) -> DanmakuKeywordBlocklistSheet
}

extension DanmuSettingModel: TVPanelDanmakuSettings {
    fileprivate func keywordSheet(isPresented: Binding<Bool>) -> DanmakuKeywordBlocklistSheet {
        DanmakuKeywordBlocklistSheet(settings: self, isPresented: isPresented)
    }
}
#if DEBUG
extension TVUIAuditSettings: TVPanelDanmakuSettings {
    fileprivate func keywordSheet(isPresented: Binding<Bool>) -> DanmakuKeywordBlocklistSheet {
        DanmakuKeywordBlocklistSheet(auditSettings: self, isPresented: isPresented)
    }
}
#endif

struct TVFullUIDanmakuSettingsPage: View {
    let onClose: () -> Void
    @Environment(AppState.self) private var app
    @FocusState private var focus: TVLivePlayerSettingsPanel.Item?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVPlayerPanelHeader(title: Text("弹幕设置")) {
                TVPlayerPanelCloseButton(isFocused: focus == .close, action: onClose)
                    .focused($focus, equals: .close)
            }
            ScrollView(showsIndicators: false) {
                TVDanmakuPanelOptions(settings: app.danmuSettingsViewModel, focus: $focus)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .clipped()
        }
        .foregroundStyle(.white)
        .focusSection()
        .onAppear { focus = .enabled }
        .tvFullUIBackCommand(perform: onClose)
    }
}

private struct TVDanmakuPanelOptions: View, TVSettingsPanelRows {
    let settings: any TVPanelDanmakuSettings
    let focus: FocusState<TVLivePlayerSettingsPanel.Item?>.Binding
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var showsKeywords = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            toggleRow("开启弹幕", item: .enabled, value: settings.showDanmu) { settings.showDanmu.toggle() }
            toggleRow("彩色弹幕", item: .color, value: settings.showColorDanmu) { settings.showColorDanmu.toggle() }
            section("字号 · \(settings.danmuFontSize)") {
                HStack(spacing: 12) {
                    ForEach([-5, -1, 1, 5], id: \.self) { delta in
                        stepButton(delta > 0 ? "+\(delta)" : "\(delta)", item: .size(delta)) {
                            settings.danmuFontSize = min(100, max(10, settings.danmuFontSize + delta))
                        }
                    }
                }
                Text("弹幕预览").font(.system(size: CGFloat(settings.danmuFontSize)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("透明度 · \(settings.danmuAlpha, format: .number.precision(.fractionLength(1)))") {
                HStack(spacing: 12) {
                    ForEach([-1, 1], id: \.self) { delta in
                        stepButton(delta > 0 ? "+0.1" : "−0.1", item: .alpha(delta)) {
                            let step = Int((settings.danmuAlpha * 10).rounded()) + delta
                            settings.danmuAlpha = Double(min(10, max(1, step))) / 10
                            settings.danmuAlphaString = String(format: "%.1f", settings.danmuAlpha)
                        }
                    }
                }
            }
            section("弹幕速度") {
                ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                    row("\(DanmuSettingModel.danmuSpeedArray[index])", item: .speed(index), opensPanel: false,
                        isSelected: settings.danmuSpeedIndex == index) {
                        settings.danmuSpeedIndex = index
                        settings.danmuSpeed = [0.5, 0.7, 0.85][index]
                    }
                }
            }
            section("显示区域") {
                ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                    row("\(DanmuSettingModel.danmuAreaArray[index])", item: .area(index), opensPanel: false,
                        isSelected: settings.danmuAreaIndex == index) { settings.danmuAreaIndex = index }
                }
            }
            row("屏蔽关键词", item: .keywords, value: "\(settings.blockedKeywords.count)") { showsKeywords = true }
        }
        .monospacedDigit()
        .tvFullUIModalPresentation(fullUI: true, isPresented: $showsKeywords, onDismiss: {
            focus.wrappedValue = .keywords
        }) {
            settings.keywordSheet(isPresented: $showsKeywords)
        }
    }

    private func stepButton(_ title: String, item: Item, action: @escaping () -> Void) -> some View {
        let focused = focus.wrappedValue == item
        return Button(action: action) {
            Text(title)
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 70)
                .tvPanelRowHighlight(focused, idleOpacity: 0.08)
        }
        .buttonStyle(TVQualityItemButtonStyle(isFocused: focused, reduceMotion: reduceMotion))
        .focused(focus, equals: item)
    }
}

@MainActor
private protocol TVSettingsPanelRows {
    var focus: FocusState<TVLivePlayerSettingsPanel.Item?>.Binding { get }
    var reduceMotion: Bool { get }
}

private extension TVSettingsPanelRows {
    typealias Item = TVLivePlayerSettingsPanel.Item

    func toggleRow(_ title: LocalizedStringKey, item: Item, value: Bool, action: @escaping () -> Void) -> some View {
        row(title, item: item, opensPanel: false, value: value ? "已开启" : "已关闭", action: action)
    }

    func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 14)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
        }
    }

    func row(
        _ title: LocalizedStringKey, symbol: String? = nil, item: Item, opensPanel: Bool = true,
        countdown: TVPlaybackSleepTimer? = nil, isSelected: Bool = false, value: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let focused = focus.wrappedValue == item
        return Button(action: action) {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .frame(width: 30)
                }
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let value { Text(value).font(.system(size: 24).monospacedDigit()) }
                if let sleepTimer = countdown {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(sleepTimer.remainingTime)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                if opensPanel {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 28, weight: focused ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(height: TVFullUIPlayerControlMetrics.height)
            .tvPanelRowHighlight(focused)
        }
        .buttonStyle(TVQualityItemButtonStyle(isFocused: focused, reduceMotion: reduceMotion))
        .focused(focus, equals: item)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
