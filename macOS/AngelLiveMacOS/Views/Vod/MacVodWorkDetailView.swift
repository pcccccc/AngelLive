#if canImport(KSPlayer)
import AngelLiveCore
import AppKit
import SharedAssets
import SwiftUI

struct MacVodWorkDetailView: View {
    let model: VodPlaybackModel
    let isSupported: Bool
    let presentation: MacPlaybackPresentation
    let onClose: @MainActor () -> Void
    let onRetry: () -> Void
    let onPlay: (VodEpisode, String?) -> Void

    @Environment(\.macPlayerAcceptsCommands) private var acceptsCommands
    @State private var window: NSWindow?
    @State private var isFullscreen = false
    @State private var sources: [VodPlaybackSource] = []
    @State private var sourceID: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if !isSupported {
                    ContentUnavailableView("点播协议不兼容", systemImage: "film",
                                           description: Text("当前插件版本未提供受支持的点播能力。"))
                } else if let detail = model.detail {
                    detailContent(detail)
                } else if let message = model.errorMessage {
                    ContentUnavailableView {
                        Label("无法加载作品", systemImage: "film")
                    } description: {
                        Text(verbatim: message)
                    } actions: {
                        Button("重试", action: onRetry)
                    }
                } else {
                    ProgressView("正在加载作品").fullUIArcLoadingStyle()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            toolbar
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .background(MacFullUIWindowProbe(window: $window))
        .macPlayerWindowState(window) {
            isFullscreen = window?.styleMask.contains(.fullScreen) == true
        }
        .macPlayerEscapeKey(isEnabled: acceptsCommands) { onClose() }
        .task(id: model.preferredEpisode?.id) {
            sources = []
            sourceID = nil
            guard let detail = model.detail, let episode = model.preferredEpisode else { return }
            let available = try? await VodHostRouting.sources(for: detail, episode: episode)
            guard !Task.isCancelled else { return }
            sources = available ?? []
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: isNavigation ? "chevron.backward" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .macPlayerGlass(in: Circle())
            .accessibilityLabel("关闭作品详情")
            .help(isNavigation ? "返回" : "关闭作品详情")
            .padding(.leading, MacPlayerChrome.inset)

            // Keep the AppKit drag view outside the button's hit area.
            if !isFullscreen {
                WindowDragArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(height: 32)
        .padding(.top, MacPlayerChrome.inset)
    }

    private var isNavigation: Bool {
        if case .navigation = presentation { return true }
        return false
    }

    private func detailContent(_ detail: VodWorkDetail) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let wide = size.width >= 720
            let inset: CGFloat = size.width >= 960 ? 40 : wide ? 32 : 24
            let artwork = detail.heroArtwork(portrait: size.height > size.width, preferredEpisode: model.preferredEpisode)
            let height = detail.kind == .series ? min(520, max(360, size.height * 0.57)) : size.height * 0.78
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    MediaHeroStage(title: detail.title, metadata: detail.displayMetadata(formatTime: macPlayerTime),
                                   tags: detail.displayTags(sourceCount: sources.count), synopsis: detail.synopsis,
                                   titleFont: .system(size: 32, weight: .bold), height: height, inset: inset,
                                   topClearance: geometry.safeAreaInsets.top + 32 + MacPlayerChrome.inset * 2,
                                   landscape: size.width >= size.height, fitsPoster: artwork.fitsPoster) {
                        MacVodArtwork(path: artwork.url, contentMode: artwork.fitsPoster ? .fit : .fill)
                    } actions: {
                        HStack(spacing: 10) {
                            if let episode = model.preferredEpisode {
                                Button { play(episode) } label: {
                                    actionLabel(detail.playTitle(for: episode, snapshot: model.progressSnapshot, formatTime: macPlayerTime),
                                                symbol: "play.fill")
                                        .font(Self.actionFont)
                                        .foregroundStyle(.black).padding(.horizontal, 16)
                                        .frame(height: Self.actionHeight)
                                        .background(.white, in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("暂无可播放内容").foregroundStyle(.secondary)
                            }
                            if sources.count > 1 { sourcePicker }
                        }
                    }
                    if let warning = model.progressWarning {
                        Text(verbatim: warning).font(.footnote).padding(.horizontal, inset)
                    }
                    if detail.kind == .series {
                        MacVodEpisodeList(detail: detail, snapshot: model.progressSnapshot,
                                          selectedEpisodeID: model.progressSnapshot?.lastEpisodeID,
                                          scrolls: false, gridWidth: wide ? size.width - 2 * inset : nil, onSelect: play)
                            .padding(.horizontal, inset)
                    }
                }
                .padding(.bottom, inset)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var sourcePicker: some View {
        Menu {
            Picker("播放线路", selection: $sourceID) {
                Text("默认").tag(nil as String?)
                ForEach(sources) { source in Text(verbatim: source.title).tag(Optional(source.id)) }
            }
        } label: {
            actionLabel(sources.first { $0.id == sourceID }?.title ?? "选择线路",
                        symbol: "point.3.connected.trianglepath.dotted")
                .font(Self.actionFont)
                .padding(.horizontal, 16)
                .frame(height: Self.actionHeight)
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .frame(height: Self.actionHeight)
        .macPlayerGlass(in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.75).allowsHitTesting(false) }
        .accessibilityLabel("播放线路")
        .accessibilityValue(sources.first { $0.id == sourceID }?.title ?? "默认")
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(verbatim: title).lineLimit(1)
        }
    }

    private static let actionHeight: CGFloat = 32
    private static let actionFont = Font.system(size: 13, weight: .semibold)

    private func play(_ episode: VodEpisode) {
        onPlay(episode, episode.id == model.preferredEpisode?.id ? sourceID : nil)
    }
}
#endif
