//
//  VideoControllerView.swift
//  KSPlayer
//
//  Created by kintan on 3/18/25.
//

import Foundation
import SwiftUI

@available(iOS 16, macOS 13, tvOS 16, *)
struct VideoControllerView: View {
    @ObservedObject
    private var model: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    private var playerWidth: CGFloat {
        model.config.playerLayer?.player.view.frame.width ?? 0
    }

    init(model: KSVideoPlayerModel) {
        self.model = model
    }

    var body: some View {
        VStack {
            #if os(tvOS)
            Spacer()
            HStack(spacing: 24) {
                KSVideoPlayerViewBuilder.titleView(title: model.title, config: model.config)
                    .lineLimit(2)
                    .layoutPriority(100)
                KSVideoPlayerViewBuilder.muteButton(config: model.config)
                if let audioTracks = model.config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    KSVideoPlayerViewBuilder.audioButton(config: model.config, audioTracks: audioTracks)
                }
                Spacer()
                    .layoutPriority(2)
                HStack(spacing: 24) {
                    KSVideoPlayerViewBuilder.preButton(model: model)
                    KSVideoPlayerViewBuilder.playButton(config: model.config)
                    KSVideoPlayerViewBuilder.nextButton(model: model)
                    KSVideoPlayerViewBuilder.contentModeButton(config: model.config)
                    KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $model.config.playbackRate)
                    KSVideoPlayerViewBuilder.recordButton(config: model.config)
                    KSVideoPlayerViewBuilder.pipButton(config: model.config)
                    KSVideoPlayerViewBuilder.subtitleButton(config: model.config)
                    KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $model.showVideoSetting)
                }
            }
            if model.config.isMaskShow {
                VideoTimeShowView(config: model.config, model: model.config.timemodel, timeFont: .caption2)
                    .isFocused($model.focusableView, equals: .slider)
            }
            #elseif os(macOS)
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    KSVideoPlayerViewBuilder.muteButton(config: model.config)
                    KSVideoPlayerViewBuilder.volumeSlider(config: model.config, volume: $model.config.playbackVolume)
                        .frame(maxWidth: 100)
                    if let audioTracks = model.config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                        KSVideoPlayerViewBuilder.audioButton(config: model.config, audioTracks: audioTracks)
                    }
                    Spacer()
                    KSVideoPlayerViewBuilder.preButton(model: model)
                    KSVideoPlayerViewBuilder.backwardButton(config: model.config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.playButton(config: model.config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.forwardButton(config: model.config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.nextButton(model: model)
                    Spacer()
                    KSVideoPlayerViewBuilder.contentModeButton(config: model.config)
                    KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $model.config.playbackRate)
                    KSVideoPlayerViewBuilder.recordButton(config: model.config)
                    KSVideoPlayerViewBuilder.pipButton(config: model.config)
                    KSVideoPlayerViewBuilder.subtitleButton(config: model.config)
                    KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $model.showVideoSetting)
                }
                // 设置opacity为0，还是会去更新View。所以只能这样了
                if model.config.isMaskShow {
                    VideoTimeShowView(config: model.config, model: model.config.timemodel, timeFont: .caption2)
                }
            }
            .padding()
            .background(.black.opacity(0.35))
            .cornerRadius(10)
            .padding(.horizontal, playerWidth * 0.15)
            .padding(.vertical, 24)
            #else
            HStack {
                Button {
                    dismiss()
                    #if os(iOS)
                    KSOptions.supportedInterfaceOrientations = nil
                    #endif
                } label: {
                    Image(systemName: "x.circle.fill")
                }
                #if os(visionOS)
                .glassBackgroundEffect()
                #endif
                KSVideoPlayerViewBuilder.muteButton(config: model.config)
                KSVideoPlayerViewBuilder.volumeSlider(config: model.config, volume: $model.config.playbackVolume)
                    .frame(maxWidth: 100)
                    .tint(.white.opacity(0.8))
                    .padding(.leading, 16)
                #if os(visionOS)
                    .glassBackgroundEffect()
                #endif
                if let audioTracks = model.config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    KSVideoPlayerViewBuilder.audioButton(config: model.config, audioTracks: audioTracks)
                    #if os(visionOS)
                        .aspectRatio(1, contentMode: .fit)
                        .glassBackgroundEffect()
                    #endif
                }
                Spacer()
                #if os(iOS)
                if model.config.playerLayer?.player.allowsExternalPlayback == true {
                    AirPlayView().fixedSize()
                }
                KSVideoPlayerViewBuilder.contentModeButton(config: model.config)
                if model.config.playerLayer?.player.naturalSize.isHorizonal == true {
                    KSVideoPlayerViewBuilder.landscapeButton
                }
                #endif
            }
            Spacer()
            #if !os(visionOS)
            HStack(spacing: 20) {
                KSVideoPlayerViewBuilder.preButton(model: model)
                KSVideoPlayerViewBuilder.backwardButton(config: model.config)
                KSVideoPlayerViewBuilder.playButton(config: model.config)
                KSVideoPlayerViewBuilder.forwardButton(config: model.config)
                KSVideoPlayerViewBuilder.nextButton(model: model)
            }
            Spacer()
            HStack(spacing: 18) {
                KSVideoPlayerViewBuilder.titleView(title: model.title, config: model.config)
                Spacer()
                KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $model.config.playbackRate)
                KSVideoPlayerViewBuilder.pipButton(config: model.config)
                KSVideoPlayerViewBuilder.recordButton(config: model.config)
                KSVideoPlayerViewBuilder.subtitleButton(config: model.config)
                KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $model.showVideoSetting)
            }
            if model.config.isMaskShow {
                VideoTimeShowView(config: model.config, model: model.config.timemodel, timeFont: .caption2)
            }
            #endif
            #endif
        }
        .isFocused($model.focusableView, equals: .controller)
        .sheet(isPresented: $model.showVideoSetting) {
            VideoSettingView(model: model)
        }
        #if os(visionOS)
        .ornament(visibility: model.config.isMaskShow ? .visible : .hidden, attachmentAnchor: .scene(.bottom)) {
            VStack(alignment: .leading) {
                HStack {
                    KSVideoPlayerViewBuilder.titleView(title: model.title, config: model.config)
                }
                HStack(spacing: 16) {
                    KSVideoPlayerViewBuilder.backwardButton(config: model.config)
                    KSVideoPlayerViewBuilder.playButton(config: model.config)
                    KSVideoPlayerViewBuilder.forwardButton(config: model.config)
                    VideoTimeShowView(config: model.config, model: model.config.timemodel, timeFont: .title3)
                    KSVideoPlayerViewBuilder.contentModeButton(config: model.config)
                    KSVideoPlayerViewBuilder.subtitleButton(config: model.config)
                    KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $model.config.playbackRate)
                    KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $model.showVideoSetting)
                }
            }
            .frame(minWidth: playerWidth / 1.5)
            .buttonStyle(.plain)
            .padding(.vertical, 24)
            .padding(.horizontal, 36)
            .glassBackgroundEffect()
        }
        #endif
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.bottom, 80)
        .background(LinearGradient(
            stops: [
                Gradient.Stop(color: .black.opacity(0), location: 0.22),
                Gradient.Stop(color: .black.opacity(0.7), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        ))
        .ignoresSafeArea()
        #else
        .font(.title)
        .buttonStyle(.borderless)
        .padding()
        #if os(iOS)
            .background {
                Color.black.opacity(0.35).ignoresSafeArea()
            }
        #endif
        #endif
        // macOS要写在这里才能隐藏，写在外面无法隐藏
        .opacity(model.config.isMaskShow ? 1 : 0)
    }
}

@available(iOS 15, macOS 12, tvOS 15, *)
struct VideoTimeShowView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var model: ControllerTimeModel
    fileprivate var timeFont: Font
    var body: some View {
        if let playerLayer = config.playerLayer, playerLayer.player.seekable {
            HStack {
                Text(model.currentTime.toString(for: .minOrHour))
                PlayerSlider(model: model) { [weak model, weak playerLayer] onEditingChanged in
                    guard let model, let playerLayer else { return }
                    if onEditingChanged {
                        playerLayer.pause()
                    } else {
                        playerLayer.seek(time: TimeInterval(model.currentTime))
                    }
                }
                .frame(maxHeight: 20)
                #if os(visionOS)
                    .tint(.white.opacity(0.8))
                #endif
                Text((model.totalTime).toString(for: .minOrHour))
            }
            .font(timeFont.monospacedDigit())
        } else {
            Text(String(localized: "Live Streaming", bundle: .module))
        }
    }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct VideoSettingView: View {
    @ObservedObject
    var model: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    @State
    private var subtitleFileImport = false
    var body: some View {
        PlatformView {
            if let playerLayer = model.config.playerLayer {
                if model.urls.count > 0 {
                    Picker(selection: Binding {
                        model.url
                    } set: { value in
                        model.url = value
                    }) {
                        ForEach(model.urls) { url in
                            Text(url.lastPathComponent).tag(url)
                        }
                    } label: {
                        Label(String(localized: "PlayList", bundle: .module), systemImage: "list.bullet.rectangle.fill")
                    }
                }
                if let playList = playerLayer.player.ioContext as? PlayList {
                    let list = playList.playlists.filter { $0.duration > 60 * 2 }
                    if list.count > 1 {
                        Picker(selection: Binding {
                            playList.currentStream?.name
                        } set: { value in
                            if let value, var components = playerLayer.url.components {
                                if components.scheme == "BDMVIOContext", var queryItems = components.queryItems, let index = queryItems.firstIndex(where: { $0.name == "streamName" }) {
                                    queryItems[index].value = value
                                    components.queryItems = queryItems
                                    model.url = components.url
                                } else if var newURL = URL(string: "BDMVIOContext://") {
                                    newURL.append(queryItems: [URLQueryItem(name: "streamName", value: value), URLQueryItem(name: "url", value: playerLayer.url.description)])
                                    model.url = newURL
                                }
                            }
                        }) {
                            ForEach(list, id: \.name) { stream in
                                Text(stream.name + " duration=\(Int(stream.duration).toString(for: .minOrHour))").tag(stream.name as String?)
                            }
                        } label: {
                            Label(String(localized: "Stream Name", bundle: .module), systemImage: "video.fill")
                        }
                    }
                }
                let videoTracks = playerLayer.player.tracks(mediaType: .video)
                if !videoTracks.isEmpty {
                    Picker(selection: Binding {
                        videoTracks.first { $0.isEnabled }?.trackID
                    } set: { value in
                        if let track = videoTracks.first(where: { $0.trackID == value }) {
                            playerLayer.player.select(track: track)
                        }
                    }) {
                        ForEach(videoTracks, id: \.trackID) { track in
                            Text(track.description).tag(track.trackID as Int32?)
                        }
                    } label: {
                        Label(String(localized: "Video Track", bundle: .module), systemImage: "video.fill")
                    }

                    Picker(String(localized: "Video Display Type", bundle: .module), selection: Binding {
                        if playerLayer.options.display === KSOptions.displayEnumVR {
                            return "VR"
                        } else if playerLayer.options.display === KSOptions.displayEnumVRBox {
                            return "VRBox"
                        } else {
                            return "Plane"
                        }
                    } set: { value in
                        if value == "VR" {
                            playerLayer.options.display = KSOptions.displayEnumVR
                        } else if value == "VRBox" {
                            playerLayer.options.display = KSOptions.displayEnumVRBox
                        } else {
                            playerLayer.options.display = KSOptions.displayEnumPlane
                        }
                    }) {
                        Text("Plane").tag("Plane")
                        Text("VR").tag("VR")
                        Text("VRBox").tag("VRBox")
                    }
                    LabeledContent(String(localized: "Video Type", bundle: .module), value: (videoTracks.first { $0.isEnabled }?.dynamicRange ?? .sdr).description)
                    LabeledContent(String(localized: "Stream Type", bundle: .module), value: (videoTracks.first { $0.isEnabled }?.fieldOrder ?? .progressive).description)
                    LabeledContent(String(localized: "Decode Type", bundle: .module), value: playerLayer.options.decodeType.rawValue)
                    #if os(macOS)
                    TextField(String(localized: "brightness", bundle: .module), value: Binding {
                        playerLayer.options.brightness
                    } set: { value in
                        playerLayer.options.brightness = value
                    }, format: .number)
                    #endif
                }
                TextField(String(localized: "Subtitle delay", bundle: .module), value: Binding {
                    playerLayer.subtitleModel.subtitleDelay
                } set: { value in
                    playerLayer.subtitleModel.subtitleDelay = value
                }, format: .number)
                Picker(selection: Binding {
                    playerLayer.subtitleModel.secondarySubtitleInfo?.subtitleID
                } set: { value in
                    let info = playerLayer.subtitleModel.subtitleInfos.first { $0.subtitleID == value }
                    playerLayer.select(subtitleInfo: info, isSecondary: true)
                }) {
                    Text("Off").tag(nil as String?)
                    ForEach(playerLayer.subtitleModel.subtitleInfos ?? [], id: \.subtitleID) { track in
                        Text(track.name).tag(track.subtitleID as String?)
                    }
                } label: {
                    Label(String(localized: "Secondary Subtitle", bundle: .module), systemImage: "text.bubble")
                }
                TextField(String(localized: "Title", bundle: .module), text: $model.title)
                Button(String(localized: "Search Subtitle", bundle: .module)) {
                    playerLayer.subtitleModel.searchSubtitle(query: model.title, languages: [Locale.current.identifier])
                }
                .buttonStyle(.bordered)
                #if !os(tvOS)
                Button(String(localized: "Add Subtitle", bundle: .module)) {
                    subtitleFileImport = true
                }
                .buttonStyle(.bordered)
                #endif
                DynamicInfoView(dynamicInfo: playerLayer.player.dynamicInfo)
                let fileSize = playerLayer.player.fileSize
                if fileSize > 0 {
                    LabeledContent(String(localized: "File Size", bundle: .module), value: fileSize.kmFormatted + "B")
                }
                LabeledContent(String(localized: "First Time Log", bundle: .module), value: model.options.firstTimeLog().debugDescription)
            } else {
                Text(String(localized: "Loading...", bundle: .module))
            }
        }
        #if !os(tvOS)
        .fileImporter(isPresented: $subtitleFileImport, allowedContentTypes: [.data]) { result in
            guard let url = try? result.get() else {
                return
            }
            if url.startAccessingSecurityScopedResource() {
                if url.isSubtitle {
                    let info = URLSubtitleInfo(url: url)
                    model.config.playerLayer?.select(subtitleInfo: info)
                }
            }
        }
        #endif
        #if os(macOS) || targetEnvironment(macCatalyst) || os(visionOS)
        .toolbar {
            Button(String(localized: "Done", bundle: .module)) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        #endif
    }
}

@available(iOS 16, macOS 13, tvOS 16, *)
public struct DynamicInfoView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo
    public var body: some View {
        LabeledContent(String(localized: "Display FPS", bundle: .module), value: dynamicInfo.displayFPS, format: .number)
        LabeledContent(String(localized: "Audio Video sync", bundle: .module), value: dynamicInfo.audioVideoSyncDiff, format: .number)
        LabeledContent(String(localized: "Dropped Frames", bundle: .module), value: dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount, format: .number)
        LabeledContent(String(localized: "Bytes Read", bundle: .module), value: dynamicInfo.bytesRead.kmFormatted + "B")
        LabeledContent(String(localized: "Audio bitrate", bundle: .module), value: dynamicInfo.audioBitrate.kmFormatted + "bps")
        LabeledContent(String(localized: "Video bitrate", bundle: .module), value: dynamicInfo.videoBitrate.kmFormatted + "bps")
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct HUDLogView: View {
    @ObservedObject
    public var dynamicInfo: DynamicInfo
    public var body: some View {
        Text(dynamicInfo.hudLogText)
            .foregroundColor(Color.orange)
            .multilineTextAlignment(.leading)
            .padding()
    }
}

private extension DynamicInfo {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    var hudLogText: String {
        var log = String(localized: "Display FPS", bundle: .module) + ": \(displayFPS)\n"
            + String(localized: "Dropped Frames", bundle: .module) + ": \(droppedVideoFrameCount)\n"
            + String(localized: "Audio Video sync", bundle: .module) + ": \(audioVideoSyncDiff)\n"
            + String(localized: "Network Speed", bundle: .module) + ": \(networkSpeed.kmFormatted)B/s\n"
        #if DEBUG
        log += String(localized: "Average Audio Video sync", bundle: .module) + ": \(averageAudioVideoSyncDiff)\n"
        #endif
        return log
    }
}
