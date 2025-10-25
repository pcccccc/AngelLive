//
//  VideoControllerView.swift
//  KSPlayer
//
//  Created by kintan on 3/18/25.
//

import Foundation
import SwiftUI
import KSPlayer
internal import AVFoundation

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
                    .ksIsFocused($model.focusableView, equals: .slider)
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
        .ksIsFocused($model.focusableView, equals: .controller)
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

struct VideoTimeShowView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var model: ControllerTimeModel
    fileprivate var timeFont: Font
    var body: some View {
        // 直播应用，只显示"直播中"
        Text("Live Streaming")
            .font(timeFont)
    }
}

struct VideoSettingView: View {
    @ObservedObject
    var model: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    @State
    private var subtitleFileImport = false

    private func formatFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1fM", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1fG", gb)
    }

    var body: some View {
        KSPlatformView {
            if let playerLayer = model.config.playerLayer {
                if model.urls.count > 0 {
                    Picker(selection: Binding<URL?>(
                        get: { model.url },
                        set: { model.url = $0 }
                    )) {
                        ForEach(model.urls) { url in
                            Text(url.lastPathComponent).tag(url as URL?)
                        }
                    } label: {
                        Label("PlayList", systemImage: "list.bullet.rectangle.fill")
                    }
                }
                if let playList = playerLayer.player.ioContext as? PlayList {
                    let list = playList.playlists.filter { $0.duration > 60 * 2 }
                    if list.count > 1 {
                        Picker(selection: Binding<String?>(
                            get: { playList.currentStream?.name },
                            set: { value in
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
                            }
                        )) {
                            ForEach(list, id: \.name) { stream in
                                Text(stream.name + " duration=\(Int(stream.duration).toString(for: .minOrHour))").tag(stream.name as String?)
                            }
                        } label: {
                            Label("Stream Name", systemImage: "video.fill")
                        }
                    }
                }
                let videoTracks = playerLayer.player.tracks(mediaType: .video)
                if !videoTracks.isEmpty {
                    Picker(selection: Binding<Int32?>(
                        get: { videoTracks.first { $0.isEnabled }?.trackID },
                        set: { value in
                            if let value, let track = videoTracks.first(where: { $0.trackID == value }) {
                                playerLayer.player.select(track: track)
                            }
                        }
                    )) {
                        ForEach(videoTracks, id: \.trackID) { track in
                            Text(track.description).tag(track.trackID as Int32?)
                        }
                    } label: {
                        Label("Video Track", systemImage: "video.fill")
                    }

                    Picker("Video Display Type", selection: Binding<String>(
                        get: {
                            if playerLayer.options.display === KSOptions.displayEnumVR {
                                return "VR"
                            } else if playerLayer.options.display === KSOptions.displayEnumVRBox {
                                return "VRBox"
                            } else {
                                return "Plane"
                            }
                        },
                        set: { (value: String) in
                            if value == "VR" {
                                playerLayer.options.display = KSOptions.displayEnumVR
                            } else if value == "VRBox" {
                                playerLayer.options.display = KSOptions.displayEnumVRBox
                            } else {
                                playerLayer.options.display = KSOptions.displayEnumPlane
                            }
                        }
                    )) {
                        Text("Plane").tag("Plane")
                        Text("VR").tag("VR")
                        Text("VRBox").tag("VRBox")
                    }
                    LabeledContent("Video Type", value: (videoTracks.first { $0.isEnabled }?.dynamicRange ?? .sdr).description)
                    LabeledContent("Stream Type", value: (videoTracks.first { $0.isEnabled }?.fieldOrder ?? .progressive).description)
                    LabeledContent("Decode Type", value: playerLayer.options.decodeType.rawValue)
                    #if os(macOS)
                    TextField("brightness", value: Binding<Float>(
                        get: { playerLayer.options.brightness },
                        set: { playerLayer.options.brightness = $0 }
                    ), format: .number)
                    #endif
                }
                TextField("Subtitle delay", value: Binding<Double>(
                    get: { playerLayer.subtitleModel.subtitleDelay },
                    set: { playerLayer.subtitleModel.subtitleDelay = $0 }
                ), format: .number)
                // 次要字幕功能（直播不需要，已注释）
                // Picker(selection: Binding<String?>(
                //     get: { playerLayer.subtitleModel.secondarySubtitleInfo?.subtitleID },
                //     set: { value in
                //         let info = playerLayer.subtitleModel.subtitleInfos.first { $0.subtitleID == value }
                //         playerLayer.select(subtitleInfo: info, isSecondary: true)
                //     }
                // )) {
                //     Text("Off").tag(nil as String?)
                //     ForEach(playerLayer.subtitleModel.subtitleInfos ?? [], id: \.subtitleID) { track in
                //         Text(track.name).tag(track.subtitleID as String?)
                //     }
                // } label: {
                //     Label("Secondary Subtitle", systemImage: "text.bubble")
                // }
                TextField("Title", text: $model.title)
                Button("Search Subtitle") {
                    playerLayer.subtitleModel.searchSubtitle(query: model.title, languages: [Locale.current.identifier])
                }
                .buttonStyle(.bordered)
                #if !os(tvOS)
                Button("Add Subtitle") {
                    subtitleFileImport = true
                }
                .buttonStyle(.bordered)
                #endif
                DynamicInfoView(dynamicInfo: playerLayer.player.dynamicInfo)
                let fileSize = playerLayer.player.fileSize
                if fileSize > 0 {
                    LabeledContent("File Size", value: formatFileSize(fileSize) + "B")
                }
            } else {
                Text("Loading...")
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
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        #endif
    }
}

public struct DynamicInfoView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo
    public var body: some View {
        LabeledContent("Display FPS", value: dynamicInfo.displayFPS, format: .number)
        LabeledContent("Audio Video sync", value: dynamicInfo.audioVideoSyncDiff, format: .number)
        LabeledContent("Dropped Frames", value: dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount, format: .number)
        LabeledContent("Bytes Read", value: formatBytes(dynamicInfo.bytesRead) + "B")
        LabeledContent("Audio bitrate", value: formatBytes(Int64(dynamicInfo.audioBitrate)) + "bps")
        LabeledContent("Video bitrate", value: formatBytes(Int64(dynamicInfo.videoBitrate)) + "bps")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1fM", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1fG", gb)
    }
}

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
    var hudLogText: String {
        var log = ""
        log += "Display FPS: \(displayFPS)\n"
        log += "Dropped Frames: \(droppedVideoFrameCount)\n"
        log += "Audio Video sync: \(audioVideoSyncDiff)\n"
        log += "Network Speed: \(formatBytes(Int64(networkSpeed)))B/s\n"
        #if DEBUG
        log += "Average Audio Video sync: \(averageAudioVideoSyncDiff)\n"
        #endif
        return log
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1fM", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1fG", gb)
    }
}
