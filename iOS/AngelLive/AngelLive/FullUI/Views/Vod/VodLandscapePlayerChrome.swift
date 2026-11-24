#if canImport(KSPlayer)
import AngelLiveCore
import AngelLiveDependencies
import SharedAssets
import SwiftUI

extension VodLandscapePlayerView {
    func chrome(layout: FullUILandscapePlayerLayout) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if !isLocked {
                    controlStack(width: size.width, layout: layout)
                    centerOverlay
                    if drawer == nil {
                        feedback
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, layout.insets.top + FullUIPlayerChrome.controlSize + 8)
                    }
                }

                if isLocked || showsChrome && model.playback != nil {
                    FullUILandscapePlayerLock(isLocked: isLocked) {
                        isLocked.toggle()
                        adjustment = nil
                        showControls()
                    }
                    .position(x: layout.lockInset + FullUIPlayerChrome.controlSize / 2, y: size.height / 2)
                }
            }
        }
        .overlay(alignment: .top) {
            FullUILandscapePlayerStatus(isVisible: showsChrome)
        }
        .animation(FullUIPlayerChrome.visibilityAnimation(showsChrome, reduceMotion: reduceMotion), value: showsChrome)
    }

    private func controlStack(width: CGFloat, layout: FullUILandscapePlayerLayout) -> some View {
        let titleWidth = layout.insets.top < FullUILandscapePlayerStatus.bottomEdge
            ? max(0, width / 2 - FullUILandscapePlayerStatus.halfWidthWithClearance
                  - layout.insets.leading - FullUIPlayerChrome.controlSize - 12)
            : width * 0.45
        return VStack(spacing: 0) {
            topBar(titleWidth: titleWidth)
                .modifier(VodChromeVisibility(isVisible: showsChrome))
            Spacer(minLength: 0)
            if !isLoading && seek == nil && drawer == nil {
                markerPrompts
                    .padding(.bottom, 8)
            }
            if showsChrome || seek != nil {
                VStack(spacing: 0) {
                    progressRow
                        .modifier(VodChromeVisibility(isVisible: drawer == nil))
                    bottomBar
                        .modifier(VodChromeVisibility(isVisible: showsChrome && model.playback != nil))
                }
            }
        }
        .padding(layout.insets)
    }

    private func topBar(titleWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            FullUIPlayerBackButton(centersSymbol: true, action: exit)
                .fullUIPlayerCircularControl()

            VStack(alignment: .leading, spacing: 1) {
                if let detail = model.detail {
                    Text(verbatim: detail.title)
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                if isSeries, let episode = model.selectedEpisode {
                    Text("第 \(episode.number) 集 · \(episode.title)")
                        .font(.system(size: 13))
                }
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            .fullUIPlayerMediaText()
            .frame(maxWidth: titleWidth, alignment: .leading)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)
            if model.playback != nil {
                FullUIPlayerGlassGroup {
                    if !controller.subtitleTracks.isEmpty {
                        chromeIcon("captions.bubble", label: "字幕") { openDrawer(.tracks(.subtitles)) }
                    }
                    chromeIcon("gearshape", label: "设置") { openDrawer(.settings) }
                }
            }
        }
        .frame(height: FullUIPlayerChrome.controlSize)
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            FullUIPlayerTimeLabel(time: currentTime)
                .offset(y: VodProgressTrack.baselineOffset)
                .accessibilityHidden(true)
            VodProgressTrack(
                time: currentTime, duration: clock.duration, cues: Array(Set([introEnd, creditsStart].compactMap { $0 })),
                isScrubbing: seek != nil, isEnabled: canSeek && seek?.fromPicture != true,
                onChange: trackSeek, onEnd: finishSeek
            )
            FullUIPlayerTimeLabel(time: clock.duration)
                .offset(y: VodProgressTrack.baselineOffset)
                .accessibilityHidden(true)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: FullUIPlayerChrome.controlSize)
        .opacity(clock.duration > 0 ? 1 : 0)
        .accessibilityHidden(clock.duration <= 0)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            FullUIPlayerGlassGroup {
                chromeIcon(playing ? "pause.fill" : "play.fill", label: playing ? "暂停" : "播放",
                           action: togglePlayback)
                if isSeries {
                    chromeIcon("backward.end.fill", label: "上一集", dimmed: atBoundary(-1)) { changeEpisode(-1) }
                    chromeIcon("forward.end.fill", label: "下一集", dimmed: atBoundary(1)) { changeEpisode(1) }
                }
            }
            Spacer(minLength: 4)
            FullUIPlayerGlassGroup {
                if isSeries {
                    Button { openDrawer(.episodes) } label: {
                        Label("选集", systemImage: "list.bullet")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: FullUIPlayerChrome.controlSize)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                chromeText(VodPlayerDrawer.rateTitle(rate)) { openDrawer(.tracks(.rate)) }
                    .accessibilityLabel("倍速")
                    .accessibilityValue(VodPlayerDrawer.rateTitle(rate))
            }
        }
        .frame(height: FullUIPlayerChrome.controlSize)
    }

    private func atBoundary(_ offset: Int) -> Bool {
        guard let episodes = model.detail?.episodes,
              let index = episodes.firstIndex(where: { $0.id == model.selectedEpisodeID }) else { return true }
        return !episodes.indices.contains(index + offset)
    }

    private func chromeIcon(_ symbol: String, label: LocalizedStringKey, dimmed: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(FullUIPlayerChrome.symbolFont)
                .foregroundStyle(.white.opacity(dimmed ? 0.4 : 1))
                .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func chromeText(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: FullUIPlayerChrome.controlSize, minHeight: FullUIPlayerChrome.controlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var centerOverlay: some View {
        if drawer == nil {
            if let seek {
                FullUIPlayerSeekReadout(time: seek.target, duration: seek.duration, preview: seekPreview.state,
                                        isHorizontalVideo: true)
                    .overlay(alignment: .bottom) {
                        if seek.fromPicture {
                            let delta = seek.target - seek.origin
                            Text(seek.cancelling ? "松开取消跳转"
                                 : "\(delta < 0 ? "−" : "+")\(fullUIPlayerTime(abs(delta))) · 上滑取消")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(seek.cancelling ? .red : .black.opacity(0.65), in: Capsule())
                                .alignmentGuide(.bottom) { $0[.top] - 8 }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Text(verbatim: error).font(.subheadline)
                    chromeText("重试", action: retry)
                        .fullUIPlayerGlass(in: Capsule())
                }
                .foregroundStyle(.white)
                .padding()
            } else if isLoading {
                ProgressView().tint(.white).fullUIArcLoadingStyle(size: 42, lineWidth: 1.8)
            } else if !playing && countdownOffer == nil {
                Button(action: togglePlayback) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .fullUIPlayerGlass(in: Circle())
                .accessibilityLabel(model.hasFinished ? "重播" : "播放")
            }
        }
    }

    private var markerPrompts: some View {
        HStack(alignment: .bottom) {
            if model.activeIntroSkipTarget != nil {
                chromeText("跳过片头", action: skipIntro)
                    .fullUIPlayerGlass(in: Capsule())
            }
            Spacer(minLength: 0)
            if let offer = countdownOffer {
                creditsCard(offer)
            }
        }
    }

    private func creditsCard(_ offer: VodCreditsOffer) -> some View {
        let next = offer.nextEpisode
        return MediaUpNextCard(episodeTitle: "第 \(next.number) 集 · \(next.title)", countdown: countdown) {
            VodArtwork(path: next.stillURL, symbol: "film")
        } actions: {
            Button(action: advanceFromCredits) { Label("立即播放", systemImage: "play.fill") }
                .buttonStyle(MediaUpNextButtonStyle(primary: true))
            Button("仍看片尾") { model.dismissCreditsOffer(playbackID: offer.playbackID) }
                .buttonStyle(MediaUpNextButtonStyle(primary: false))
        }
        .fullUIPlayerGlass(in: .rect(cornerRadius: 16))
        .frame(maxWidth: 360, alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { creditsHeight = $0 }
    }

    @ViewBuilder
    private var feedback: some View {
        if boosted {
            feedbackPill("2.0× 倍速播放中")
        } else if let adjustment {
            HStack(spacing: 8) {
                Image(systemName: adjustment.icon)
                ProgressView(value: adjustment.value).tint(.white).frame(width: 72)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .fullUIPlayerGlass(in: Capsule(), interactive: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(adjustment.title)
            .accessibilityValue(adjustment.value.formatted(.percent.precision(.fractionLength(0))))
            .allowsHitTesting(false)
        } else if let notice {
            feedbackPill(notice)
        }
    }

    private func feedbackPill(_ message: String) -> some View {
        Text(verbatim: message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fullUIPlayerGlass(in: Capsule(), interactive: false)
            .allowsHitTesting(false)
    }

    func drawerOverlay(_ kind: VodPlayerDrawer.Kind, geometry: GeometryProxy) -> some View {
        let safeArea = geometry.safeAreaInsets
        let fullWidth = geometry.size.width + safeArea.leading + safeArea.trailing
        let minimumWidth = min(300, fullWidth * 0.88)
        let width = min(360, max(minimumWidth, fullWidth * 0.37))
        return ZStack(alignment: .trailing) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: closeDrawer)
                .accessibilityHidden(true)

            VodPlayerDrawer(
                kind: kind, model: model, controller: controller, settings: settings,
                rate: $rate, pictureMode: $pictureMode,
                onEpisode: { selectEpisode($0) },
                onSource: { source in
                    if let episode = model.selectedEpisodeID { selectEpisode(episode, sourceID: source) }
                },
                onTracks: { openDrawer(.tracks(.subtitles)) }, onClose: closeDrawer
            )
            .frame(width: min(width, max(0, geometry.size.width - 24)))
            .modifier(RoomSwitcherDrawerSwipe(width: width, trailingSafeArea: 0, onDismiss: closeDrawer))
            .padding(.top, safeArea.top + 12)
            .padding(.bottom, safeArea.bottom + 12)
            .padding(.trailing, safeArea.trailing + 12)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
    }
}

private struct VodChromeVisibility: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}
#endif
