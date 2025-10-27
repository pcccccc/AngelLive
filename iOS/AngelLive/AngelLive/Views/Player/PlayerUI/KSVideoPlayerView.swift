//
//  KSVideoPlayerView.swift
//  AngelLive
//
//  Forked and modified from KSPlayer by kintan
//  Created by pangchong on 10/26/25.
//
internal import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import KSPlayer

@MainActor
public struct KSVideoPlayerView: View {
    @ObservedObject
    private var model: KSVideoPlayerModel
    private let subtitleDataSource: SubtitleDataSource?
    private let liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)?
    @Environment(\.dismiss)
    private var dismiss

    public init(model: KSVideoPlayerModel, subtitleDataSource: SubtitleDataSource? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        self.model = model
        self.subtitleDataSource = subtitleDataSource
        self.liftCycleBlock = liftCycleBlock
    }

    public var body: some View {
        if let url = model.url {
            ZStack(alignment: .topLeading) {
                KSCorePlayerView(config: model.config, url: url, options: model.options, title: $model.title, subtitleDataSource: subtitleDataSource)
                    .onAppear {
                        liftCycleBlock?(model.config, false)
                    }
                    .onDisappear {
                        liftCycleBlock?(model.config, true)
                    }
                    // onChange不会马上就回调，会少一些状态的回调。要用onReceive才不会有这个问题
                    .onReceive(model.config.$state) { state in
                        if state == .readyToPlay {
                            if let playerLayer = model.config.playerLayer, playerLayer.player.naturalSize.isHorizonal == true, !UIApplication.isLandscape {
                                KSOptions.supportedInterfaceOrientations = .landscapeLeft
                                UIViewController.attemptRotationToDeviceOrientation()
                            }
                        } else if state == .playedToTheEnd {
                            model.next()
                        }
                    }
                if KSOptions.hudLog, let playerLayer = model.config.playerLayer {
                    HUDLogView(dynamicInfo: playerLayer.player.dynamicInfo)
                }
                // 需要放在这里才能生效
                GestureView { direction in
                    switch direction {
                    case .left:
                        model.config.skip(interval: -15)
                    case .right:
                        model.config.skip(interval: 15)
                    default:
                        model.config.isMaskShow = true
                    }
                } pressAction: { direction in
                    if !model.config.isMaskShow {
                        switch direction {
                        case .left:
                            model.config.skip(interval: -15)
                        case .right:
                            model.config.skip(interval: 15)
                        case .up:
                            model.config.mask(show: true, autoHide: false)
                        case .down:
                            model.showVideoSetting = true
                        default:
                            break
                        }
                    }
                }
                .ksIsFocused($model.focusableView, equals: .play)
                .opacity(!model.config.isMaskShow ? 1 : 0)
                controllerView
            }
            // 要放在这里才可以生效
            .onTapGesture {
                model.config.isMaskShow.toggle()
            }
            .preferredColorScheme(.dark)
            .tint(.white)
            .persistentSystemOverlays(.hidden)
            .toolbar(.hidden, for: .automatic)
            .toolbar(.hidden, for: .tabBar)
            .statusBar(hidden: !model.config.isMaskShow)
            .focusedObject(model.config)
            .onChange(of: model.config.isMaskShow) { newValue in
                if newValue {
                    model.focusableView = .slider
                } else {
                    model.focusableView = .play
                }
            }
            // iOS: 要放在最上面的view。这样才不会被controllerView盖住
            .onHover { new in
                model.config.isMaskShow = new
            }
        } else {
            controllerView
        }
    }

    @MainActor
    public func openURL(_ url: URL, options: KSOptions? = nil) {
        if url.isSubtitle {
            let info = URLSubtitleInfo(url: url)
            model.config.playerLayer?.select(subtitleInfo: info)
        } else {
            if let options {
                model.options = options
            }
            model.url = url
            model.title = url.lastPathComponent
        }
    }

    private var controllerView: some View {
        VideoControllerView(model: model)
            // 要放在最上面才能修改url
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers -> Bool in
                providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    if let data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) {
                        Task { @MainActor in
                            openURL(url)
                        }
                    }
                }
                return true
            }
    }
}

public extension KSVideoPlayerView {
    init(url: URL, options: KSOptions, title: String? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        self.init(url: url, options: options, title: title, subtitleDataSource: nil, liftCycleBlock: liftCycleBlock)
    }

    // xcode 15.2还不支持对MainActor参数设置默认值
    init(coordinator: KSVideoPlayer.Coordinator? = nil, url: URL, options: KSOptions, title: String? = nil, subtitleDataSource: SubtitleDataSource? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        let config = coordinator ?? KSVideoPlayer.Coordinator()
        self.init(
            model: KSVideoPlayerModel(title: title ?? url.lastPathComponent, config: config, options: options, url: url),
            subtitleDataSource: subtitleDataSource,
            liftCycleBlock: liftCycleBlock
        )
    }

    init(playerLayer: KSPlayerLayer) {
        let coordinator = KSVideoPlayer.Coordinator(playerLayer: playerLayer)
        self.init(coordinator: coordinator, url: playerLayer.url, options: playerLayer.options)
    }
}

public class KSVideoPlayerModel: ObservableObject {
    @Published
    public var title: String
    public var config: KSVideoPlayer.Coordinator
    public var options: KSOptions
    public var urls = [URL]()
    @MainActor
    @Published
    public var url: URL? {
        didSet {
            if let url {
                options.videoFilters.removeAll()
                options.audioFilters.removeAll()
                title = url.lastPathComponent
            }
        }
    }

    @Published
    var focusableView: KSVideoPlayerModel.FocusableView? = .play
    enum FocusableView {
        case play, controller, slider
    }

    @Published
    var showVideoSetting = false
    private var cancellables = Set<AnyCancellable>()
    @MainActor
    public init(title: String, config: KSVideoPlayer.Coordinator, options: KSOptions, url: URL? = nil) {
        self.title = title
        self.config = config
        self.options = options
        self.url = url
        // 嵌套属性无法触发UI更新，所以需要进行绑定，手动触发。
        config.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    @MainActor
    public func next() {
        if let url, urls.count > 1, let index = urls.firstIndex(of: url) {
            if index == urls.count - 1 {
                self.url = urls[0]
            } else if index < urls.count - 1 {
                self.url = urls[index + 1]
            }
        }
    }

    @MainActor
    public func previous() {
        if let url, urls.count > 1, let index = urls.firstIndex(of: url), index > 0 {
            self.url = urls[index - 1]
        }
    }
}

#if DEBUG
struct KSVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "https://raw.githubusercontent.com/kingslay/TestVideo/main/subrip.mkv")!
        KSVideoPlayerView(url: url, options: KSOptions())
    }
}

// struct AVContentView: View {
//    var body: some View {
//        StructAVPlayerView().frame(width: UIScene.main.bounds.width, height: 400, alignment: .center)
//    }
// }
//
// struct StructAVPlayerView: UIViewRepresentable {
//    let playerVC = AVPlayerViewController()
//    typealias UIViewType = UIView
//    func makeUIView(context _: Context) -> UIView {
//        playerVC.view
//    }
//
//    func updateUIView(_: UIView, context _: Context) {
//        playerVC.player = AVPlayer(url: URL(string: "https://bitmovin-a.akamaihd.net/content/dataset/multi-codec/hevc/stream_fmp4.m3u8")!)
//    }
// }
#endif
