//
//  KSVideoPlayerViewBuilder.swift
//  AngelLive
//
//  Forked and modified from KSPlayer by Ian Magallan Bosch
//  Created by pangchong on 10/26/25.
//

import SwiftUI
import KSPlayer
internal import AVFoundation
import AngelLiveCore
import AngelLiveDependencies

@MainActor
public enum KSVideoPlayerViewBuilder {
    @ViewBuilder
    static func contentModeButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isScaleAspectFill.toggle()
        } label: {
            Image(systemName: config.isScaleAspectFill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                .ksMenuLabelStyle()
        }
        .ksBorderlessButton()
    }

    @ViewBuilder
    static func subtitleButton(config: KSVideoPlayer.Coordinator) -> some View {
        MenuView(selection: Binding {
            config.playerLayer?.subtitleModel.selectedSubtitleInfo?.subtitleID
        } set: { value in
            let info = config.playerLayer?.subtitleModel.subtitleInfos.first { $0.subtitleID == value }
            config.playerLayer?.select(subtitleInfo: info)
        }) {
            Text("Off").tag(nil as String?)
            ForEach(config.playerLayer?.subtitleModel.subtitleInfos ?? [], id: \.subtitleID) { track in
                Text(track.name).tag(track.subtitleID as String?)
            }
        } label: {
            Image(systemName: "text.bubble")
        }
    }

    @ViewBuilder
    static func playbackRateButton(playbackRate: Binding<Float>) -> some View {
        MenuView(selection: playbackRate) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0, 8.0] as [Float]) { value in
                // 需要有一个变量text。不然会自动帮忙加很多0
                let text = "\(value) x"
                Text(text).tag(value)
            }
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
    }

    @ViewBuilder
    static func titleView(title: String, config: KSVideoPlayer.Coordinator) -> some View {
        Group {
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minWidth: 100, alignment: .leading)
            ProgressView()
                .opacity((config.state == .buffering || config.playerLayer?.player.playbackState == .seeking) ? 1 : 0)
        }
    }

    @ViewBuilder
    static func muteButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isMuted.toggle()
        } label: {
            Image(systemName: config.isMuted ? speakerDisabledSystemName : speakerSystemName)
                .ksMenuLabelStyle()
        }
        .ksBorderlessButton()
    }

    @ViewBuilder
    static func infoButton(showVideoSetting: Binding<Bool>) -> some View {
        Button {
            showVideoSetting.wrappedValue.toggle()
        } label: {
            Image(systemName: "info.circle")
                .frame(width: 30, height: 30)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .ksBorderlessButton()
        .keyboardShortcut("i", modifiers: [.command])
    }

    @ViewBuilder
    static func refreshButton(isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .frame(width: 30, height: 30)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isLoading ? 360 : 0))
                .animation(
                    isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isLoading
                )
        }
        .ksBorderlessButton()
        .disabled(isLoading)
        .keyboardShortcut("r", modifiers: [.command])
    }

    @ViewBuilder
    static func recordButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isRecord.toggle()
        } label: {
            Image(systemName: config.isRecord ? "video.fill" : "video")
                .ksMenuLabelStyle()
        }
        .ksBorderlessButton()
    }

    @ViewBuilder
    static func volumeSlider(config: KSVideoPlayer.Coordinator, volume: Binding<Float>) -> some View {
        Slider(value: volume, in: 0 ... 1)
            .accentColor(.clear)
            .onChange(of: config.playbackVolume) { newValue in
                config.isMuted = newValue == 0
            }
    }

    @ViewBuilder
    static func audioButton(config: KSVideoPlayer.Coordinator, audioTracks: [MediaPlayerTrack]) -> some View {
        MenuView(selection: Binding {
            audioTracks.first { $0.isEnabled }?.trackID
        } set: { value in
            if let track = audioTracks.first(where: { $0.trackID == value }) {
                config.playerLayer?.player.select(track: track)
            }
        }) {
            ForEach(audioTracks, id: \.trackID) { track in
                Text(track.description).tag(track.trackID as Int32?)
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
        }
    }

    @ViewBuilder
    static func pipButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            if let playerLayer = config.playerLayer as? KSComplexPlayerLayer {
                if playerLayer.isPictureInPictureActive {
                    playerLayer.pipStop(restoreUserInterface: true)
                } else {
                    playerLayer.pipStart()
                }
            }
        } label: {
            Image(systemName: "pip")
                .ksMenuLabelStyle()
        }
        .ksBorderlessButton()
    }

    @ViewBuilder
    static func backwardButton(config: KSVideoPlayer.Coordinator) -> some View {
        if config.playerLayer?.player.seekable ?? false {
            Button {
                config.skip(interval: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .centerControlButtonStyle()
            }
            .keyboardShortcut(.leftArrow, modifiers: .none)
        }
    }

    @ViewBuilder
    static func forwardButton(config: KSVideoPlayer.Coordinator) -> some View {
        if config.playerLayer?.player.seekable ?? false {
            Button {
                config.skip(interval: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .centerControlButtonStyle()
            }
            .keyboardShortcut(.rightArrow, modifiers: .none)
        }
    }

    @ViewBuilder
    static func playButton(config: KSVideoPlayer.Coordinator, isToolbar: Bool = false, isPlaying: Bool = false) -> some View {
        Button {
            if isPlaying || config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        } label: {
            let systemName = isPlaying ? "pause.fill" : (config.state.isPlaying ? "pause.fill" : "play.fill")
            if isToolbar {
                // 工具栏样式：30x30
                Image(systemName: systemName)
                    .frame(width: 30, height: 30)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                // 中间大按钮样式
                Image(systemName: systemName)
                    .centerControlButtonStyle()
            }
        }
        .ksBorderlessButton()
        .keyboardShortcut(.space, modifiers: .none)
    }

    @ViewBuilder
    static func preButton(model: KSVideoPlayerModel) -> some View {
        if model.urls.count > 1 {
            Button {
                model.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .ksMenuLabelStyle()
            }
            .ksBorderlessButton()
        }
    }

    @ViewBuilder
    static func nextButton(model: KSVideoPlayerModel) -> some View {
        if model.urls.count > 1 {
            Button {
                model.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .ksMenuLabelStyle()
            }
            .ksBorderlessButton()
        }
    }

    @ViewBuilder
    static var landscapeButton: some View {
        Button {
            KSOptions.supportedInterfaceOrientations = UIApplication.isLandscape ? .portrait : .landscapeLeft
            UIViewController.attemptRotationToDeviceOrientation()
        } label: {
            Image(systemName: UIApplication.isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .frame(width: 30, height: 30)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .ksBorderlessButton()
    }

    @ViewBuilder
    static var portraitButton: some View {
        Button {
            KSOptions.supportedInterfaceOrientations = .portrait
            UIViewController.attemptRotationToDeviceOrientation()
        } label: {
            Image(systemName: "arrow.up.and.down")
                .frame(width: 30, height: 30)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .ksBorderlessButton()
    }

    @ViewBuilder
    static func qualityMenuButton(viewModel: RoomInfoViewModel) -> some View {
        Menu {
            if let playArgs = viewModel.currentRoomPlayArgs {
                ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                    Menu {
                        ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                            Button {
                                viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                            } label: {
                                HStack {
                                    Text(quality.title)
                                    if viewModel.currentPlayQualityQn == quality.qn {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("线路 \(cdnIndex + 1)")
                    }
                }
            }
        } label: {
            Text(viewModel.currentPlayQualityString)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }
}

private extension View {
    func centerControlButtonStyle() -> some View {
        font(.system(.title, design: .rounded).bold())
            .imageScale(.large)
            .foregroundStyle(.white)
            .padding(12)
            .contentShape(.rect)
    }
}

public extension KSVideoPlayerViewBuilder {
    static var speakerSystemName: String {
        "speaker.wave.2.fill"
    }

    static var speakerDisabledSystemName: String {
        "speaker.slash.fill"
    }
}

extension KSPlayerState {
    var systemName: String {
        if self == .error {
            return "play.slash.fill"
        } else if self == .playedToTheEnd {
            return "restart.circle.fill"
        } else if isPlaying {
            return "pause.fill"
        } else {
            return "play.fill"
        }
    }
}
