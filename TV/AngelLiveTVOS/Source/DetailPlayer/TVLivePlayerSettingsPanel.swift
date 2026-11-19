import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct TVLivePlayerSettingsPanel: View {
    enum Page: Hashable {
        case menu, subtitles, playback

        var title: LocalizedStringKey {
            switch self {
            case .menu: "设置"
            case .subtitles: "字幕与翻译"
            case .playback: "播放设置"
            }
        }
    }

    @Environment(RoomInfoViewModel.self) private var room
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedItem: Item?

    let page: Page
    let returnsFrom: Item?
    let onOpen: (Page) -> Void
    let onDanmaku: () -> Void
    let onStatistics: () -> Void
    let onFavorite: () -> Void
    let onChooseLanguage: () -> Void
    let onClose: () -> Void

    enum Item: Hashable { case close, danmaku, subtitles, playback, statistics, favorite }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !room.isOnDemand {
                TVLivePlayerRoomIdentity(room: room.currentRoom)
            }
            if page != .menu {
                HStack(spacing: 16) {
                    Text(page.title)
                        .font(.system(size: 38, weight: .bold))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(TVPanelCloseButtonStyle(isFocused: focusedItem == .close, reduceMotion: reduceMotion))
                    .focused($focusedItem, equals: .close)
                    .accessibilityLabel("关闭")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case .menu:
                        menu
                    case .subtitles:
                        subtitleSettings
                    case .playback:
                        TVLivePlaybackSettings()
                    }
                }
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, TVFullUIPlayerControlMetrics.screenInset)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 0)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .focusSection()
        .task(id: page) {
            guard page == .menu else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedItem = returnsFrom ?? (room.supportsDanmu ? .danmaku : .subtitles)
        }
    }

    private var subtitleSettings: some View {
        @Bindable var translation = RoomTranslationSettings.shared
        return VStack(alignment: .leading, spacing: 16) {
            LiveSubtitleQuickControls(playback: room.subtitlePlayback, onChooseLanguage: onChooseLanguage)
            if room.supportsDanmu {
                Toggle("自动翻译弹幕", isOn: $translation.isDanmakuEnabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("常用") {
                if room.supportsDanmu {
                    row("弹幕", symbol: "captions.bubble", item: .danmaku, action: onDanmaku)
                }
                row("字幕与翻译", symbol: "captions.bubble.fill", item: .subtitles) { onOpen(.subtitles) }
            }
            Divider().overlay(.white.opacity(0.12))
            section("更多") {
                row("播放设置", symbol: "gearshape", item: .playback) { onOpen(.playback) }
                row("视频信息", symbol: "chart.bar.xaxis", item: .statistics, action: onStatistics)
                row(room.currentRoomIsLiked ? "取消收藏" : "收藏直播间",
                    symbol: room.currentRoomIsLiked ? "heart.fill" : "heart",
                    item: .favorite, opensPanel: false, action: onFavorite)
                    .disabled(room.currentRoomLikeLoading)
            }
        }
        .padding(.top, 16)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 14)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
        }
    }

    private func row(
        _ title: LocalizedStringKey, symbol: String, item: Item, opensPanel: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let focused = focusedItem == item
        return Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .frame(width: 30)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if opensPanel {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 28, weight: focused ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(height: TVFullUIPlayerControlMetrics.height)
            .background(.white.opacity(focused ? 0.25 : 0), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(TVQualityItemButtonStyle(isFocused: focused, reduceMotion: reduceMotion))
        .focused($focusedItem, equals: item)
    }
}

private struct TVLivePlaybackSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.playerSettingsViewModel
        Picker("默认画质", selection: $settings.defaultPlaybackQuality) {
            ForEach(DefaultPlaybackQuality.allCases, id: \.self) { quality in
                Text(quality.title).tag(quality)
            }
        }
        .accessibilityHint("进入直播间时按可用画质尽量匹配")
    }
}
