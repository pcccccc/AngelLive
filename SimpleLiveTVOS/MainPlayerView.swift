//
//  MainPlayerView.swift
//  SimpleLiveTVOS
//  Base for KSPlayerView.swift
//
//  Created by pangchong on 2023/10/23.
//

import AVFoundation
import MediaPlayer
import SwiftUI
import KSPlayer


public struct MainPlayerView: View {
    
    //    @State private var title: String
    @State private var showDropDownMenu = false
    @StateObject private var playerCoordinator = KSVideoPlayer.Coordinator()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var dropdownFocused: Bool
    @State public var liveModel: LiveModel
    @State private var url: String = ""
    @FocusState var playFocusState: Bool
    @FocusState var qualityFocusState: Bool
    
    public init(liveModel: LiveModel) {
        _liveModel = .init(initialValue: liveModel)
    }
    
    public var body: some View {
        ZStack {
            if url.count > 0 {
                KSVideoPlayer(coordinator: playerCoordinator, url: URL(string: url)!, options: KSOptions())
                    .onStateChanged { playerLayer, state in
//                        if state == .readyToPlay {
//                            if let movieTitle = playerLayer.player.metadata["title"] {
//                            }
//                        }
                    }
                    .ignoresSafeArea()
                    .focusable()
                    .onMoveCommand { direction in
                        if direction == .up {
                            showDropDownMenu = false
                        }
                        if  direction == .down {
                            showDropDownMenu = true
                        }
                        if direction == .left {
                            print(">>> left swipe detected222")
                            self.playFocusState = true
            //                self.qualityFocusState = false
                        }
                        if direction == .right {
                            print(">>> right swipe detected222")

                            self.qualityFocusState = true
                        }
                        
                    }
                    .preferredColorScheme(.dark)
                    .background(Color.black)
                    .tint(.white)
                    .persistentSystemOverlays(.hidden)
//                    .toolbar(playerCoordinator.isMaskShow ? .visible : .hidden, for: .automatic)
                    .toolbar(.visible)
                    .onTapGesture {
                        playerCoordinator.isMaskShow = true
                    }
                    .onPlayPauseCommand {
                        if playerCoordinator.state.isPlaying {
                            playerCoordinator.playerLayer?.pause()
                        } else {
                            playerCoordinator.playerLayer?.play()
                        }
                    }
                    .onExitCommand {
                        if showDropDownMenu {
                            showDropDownMenu = false
                        } else if playerCoordinator.isMaskShow {
                            playerCoordinator.isMaskShow = false
                        } else {
                            dismiss()
                        }
                    }
                VStack {
                    Spacer()
                    ProgressView()
                        .background(.black.opacity(0.2))
                        .opacity(playerCoordinator.state == .buffering ? 1 : 0)
                    VStack {
                        if playerCoordinator.isMaskShow {
                            VideoTimeShowView(config: playerCoordinator, model: playerCoordinator.timemodel, playFocusState: _playFocusState, qualityFocusState: _qualityFocusState) {
                                playerCoordinator.isMaskShow = false
                            }
                        }
                    }
                    .padding()
                    .background(.black.opacity(0.4))
                    .opacity(playerCoordinator.isMaskShow ? 1 : 0)
                }
                if showDropDownMenu {
                    VideoSettingView(config: playerCoordinator, subtitleModel: playerCoordinator.subtitleModel)
                        .frame(width: KSOptions.sceneSize.width * 3 / 4)
                        .focused($dropdownFocused)
                        .onAppear {
                            dropdownFocused = true
                        }
                        .onExitCommand {
                            showDropDownMenu = false
                        }
                }
                
            }
        }
        .task {
            do {
                if let resUrl = try await liveModel.getPlayArgs() {
                    url = resUrl
                }
            }catch {
                
            }
        }
    }
}

extension View {
    func onKeyPressLeftArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.leftArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }
    
    func onKeyPressRightArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.rightArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }
    
    func onKeyPressSapce(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.space) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }
}

@available(iOS 15, tvOS 16, macOS 12, *)
struct VideoControllerView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @State
    private var showVideoSetting = false
    public var body: some View {
        HStack {
            Button {
                config.isMuted.toggle()
            } label: {
                Image(systemName: config.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            Button {
                config.isScaleAspectFill.toggle()
            } label: {
                Image(systemName: config.isScaleAspectFill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
            }
#if !os(tvOS) && !os(xrOS)
            if config.playerLayer?.player.allowsExternalPlayback == true {
                AirPlayView().fixedSize()
            }
#endif
            Spacer()
            Button {
                config.skip(interval: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
#if !os(tvOS)
            .keyboardShortcut(.leftArrow, modifiers: .none)
#endif
            Button {
                if config.state.isPlaying {
                    config.playerLayer?.pause()
                } else {
                    config.playerLayer?.play()
                }
            } label: {
                Image(systemName: config.state == .error ? "play.slash.fill" : (config.state.isPlaying ? "pause.fill" : "play.fill"))
            }
            .padding(.horizontal)
            .font(.system(.largeTitle))
#if !os(tvOS)
            .keyboardShortcut(.space, modifiers: .none)
#endif
            Button {
                config.skip(interval: 15)
            } label: {
                Image(systemName: "goforward.15")
            }
#if !os(tvOS)
            .keyboardShortcut(.rightArrow, modifiers: .none)
#endif
            Spacer()
            Button {
                config.playerLayer?.isPipActive.toggle()
            } label: {
                Image(systemName: config.playerLayer?.isPipActive ?? false ? "pip.exit" : "pip.enter")
            }
            Button {
                showVideoSetting.toggle()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            // iOS 模拟器加keyboardShortcut会导致KSVideoPlayer.Coordinator无法释放。真机不会有这个问题
#if !os(tvOS)
            .keyboardShortcut("s", modifiers: [.command, .shift])
#endif
        }
        .font(.system(.title2))
        .sheet(isPresented: $showVideoSetting) {
            VideoSettingView(config: config, subtitleModel: config.subtitleModel)
        }
#if !os(tvOS)
        .buttonStyle(.borderless)
#endif
    }
}

@available(iOS 15, tvOS 15, macOS 12, *)
struct VideoTimeShowView: View {
    @ObservedObject fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject fileprivate var model: ControllerTimeModel
    @FocusState var playFocusState: Bool
    @FocusState var qualityFocusState: Bool
    var needHideBottomToolBar: () -> Void = {}
    public var body: some View {
        HStack {
            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                Image(systemName: "play.fill")
            })
            .focused($playFocusState)
//            .frame(width: 40, height: 40)
//            .buttonStyle(.card)
//            .padding(.leading, 15)
//            .padding(.bottom, 15)
            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                Text("清晰度")
            })
//            .buttonStyle(.card)
            .focused($qualityFocusState)
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
            Text("Live")
            Spacer()
            
//
        }
        .focusable()
        
        .onAppear {
            playFocusState = true
        }
        .onDisappear {
//            playFocusState = false
//            qualityFocusState = false
        }
        
//        .onKeyPressLeftArrow {
//            self.playFocusState = true
//            self.qualityFocusState = false
//        }
//        .onKeyPressRightArrow {
//            self.playFocusState = false
//            self.qualityFocusState = true
//        }
        .onMoveCommand(perform: { direction in
            if direction == .left {
                print(">>> left swipe detected")
                self.playFocusState = true
//                self.qualityFocusState = false
            }
            if direction == .right {
                print(">>> right swipe detected")

                self.qualityFocusState = true
            }
            
        })
//        #if !targetEnvironment(simulator)
//        .swipeGestures(onRight: {
//            self.playFocusState = false
//            self.qualityFocusState = true
//        }, onLeft: {
//            self.playFocusState = true
//            self.qualityFocusState = false
//        })
//        #endif
        .onExitCommand(perform: {
            needHideBottomToolBar()
        })
    }
}

struct RoundedButtonStyle: ButtonStyle {

    let focused: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .foregroundColor(.accentColor)
            .background(Color.clear)
            .shadow(color: .accentColor, radius: self.focused ? 20 : 0, x: 0, y: 0) //  0
    }
}

extension EventModifiers {
    static let none = Self()
}



@available(iOS 15, tvOS 16, macOS 12, *)
struct VideoSettingView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var subtitleModel: SubtitleModel
    @State
    fileprivate var subtitleTitle: String
    //    @Environment(\.dismiss)
    //    private var dismiss
    init(config: KSVideoPlayer.Coordinator, subtitleModel: SubtitleModel) {
        self.config = config
        self.subtitleModel = subtitleModel
        _subtitleTitle = .init(initialValue: subtitleModel.url?.deletingPathExtension().lastPathComponent ?? "")
    }
    
    var body: some View {
        PlatformView {
            Picker(selection: $config.playbackRate) {
                ForEach([0.5, 1.0, 1.25, 1.5, 2.0] as [Float]) { value in
                    // 需要有一个变量text。不然会自动帮忙加很多0
                    let text = "\(value) x"
                    Text(text).tag(value)
                }
            } label: {
                Label("Playback Speed", systemImage: "speedometer")
            }
            
            if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                Picker(selection: Binding {
                    audioTracks.first { $0.isEnabled }?.trackID
                } set: { value in
                    if let track = audioTracks.first(where: { $0.trackID == value }) {
                        config.playerLayer?.player.select(track: track)
                        config.playerLayer?.player.isMuted = false
                    } else {
                        config.playerLayer?.player.isMuted = true
                    }
                }) {
                    ForEach(audioTracks, id: \.trackID) { track in
                        Text(track.description).tag(track.trackID as Int32?)
                    }
                } label: {
                    Label("Audio track", systemImage: "waveform")
                }
            }
            
            if let videoTracks = config.playerLayer?.player.tracks(mediaType: .video), !videoTracks.isEmpty {
                Picker(selection: Binding {
                    videoTracks.first { $0.isEnabled }?.trackID
                } set: { value in
                    if let track = videoTracks.first(where: { $0.trackID == value }) {
                        config.playerLayer?.player.select(track: track)
                        config.playerLayer?.options.videoDisable = false
                    } else {
                        config.playerLayer?.options.videoDisable = true
                    }
                }) {
                    ForEach(videoTracks, id: \.trackID) { track in
                        Text(track.description).tag(track.trackID as Int32?)
                    }
                } label: {
                    Label("Video track", systemImage: "video.fill")
                }
            }
            Picker(selection: Binding {
                subtitleModel.selectedSubtitleInfo?.subtitleID
            } set: { value in
                subtitleModel.selectedSubtitleInfo = subtitleModel.subtitleInfos.first { $0.subtitleID == value }
            }) {
                Text("Off").tag(nil as String?)
                ForEach(subtitleModel.subtitleInfos, id: \.subtitleID) { track in
                    Text(track.name).tag(track.subtitleID as String?)
                }
            } label: {
                Label("Sutitle", systemImage: "captions.bubble")
            }
            TextField("Sutitle delay", value: $subtitleModel.subtitleDelay, format: .number)
            TextField("Title", text: $subtitleTitle)
            Button("Search Sutitle") {
                subtitleModel.searchSubtitle(query: subtitleTitle, languages: ["zh-cn"])
            }
            if let fileSize = config.playerLayer?.player.fileSize, fileSize > 0 {
                Text("File Size \(String(format: "%.1f", fileSize / 1_000_000))MB")
            }
        }
        .padding()
    }
}

@available(iOS 15, tvOS 16, macOS 12, *)
public struct PlatformView<Content: View>: View {
    private let content: () -> Content
    public var body: some View {
#if os(tvOS)
        ScrollView {
            content()
                .padding()
        }
        .pickerStyle(.navigationLink)
#else
        Form {
            content()
        }
#endif
    }
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct MainPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "http://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
        KSVideoPlayerView(url: url, options: KSOptions())
    }
}
