#if canImport(KSPlayer)

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
import AngelLiveCore
import AngelLiveDependencies

@MainActor
public struct KSVideoPlayerView: View {
    @StateObject
    private var model: KSVideoPlayerModel
    private let providedURL: URL?
    private let subtitleDataSource: SubtitleDataSource?
    private let liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)?
    @Environment(\.dismiss)
    private var dismiss
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.isVerticalLiveMode) private var isVerticalLiveMode
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var hasAutoRotatedForCurrentRoom = false // 当前直播间是否已自动旋转
    @State private var actualPlayerHeight: CGFloat = 0 // 实际播放器高度

    /// 是否处于全屏模式（iPad全屏 或 iPhone横屏）
    private var isFullscreen: Bool {
        if AppConstants.Device.isIPad {
            return isIPadFullscreen.wrappedValue
        } else {
            // iPhone 横屏判断
            return horizontalSizeClass == .compact && verticalSizeClass == .compact ||
                   horizontalSizeClass == .regular && verticalSizeClass == .compact
        }
    }

    public init(model: KSVideoPlayerModel, subtitleDataSource: SubtitleDataSource? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        _model = StateObject(wrappedValue: model)
        self.providedURL = model.url
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
                    .onChange(of: viewModel.currentRoom.roomId) { _, _ in
                        // 切换直播间时重置自动旋转标志
                        hasAutoRotatedForCurrentRoom = false
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

                // 弹幕层（在控制层下方）
                if viewModel.danmuSettings.showDanmu && !isVerticalLiveMode {
                    GeometryReader { geometry in
                        let playerHeight = geometry.size.height
                        let config = danmuAreaConfiguration(
                            areaIndex: viewModel.danmuSettings.danmuAreaIndex,
                            containerHeight: playerHeight
                        )

                        DanmuView(
                            coordinator: viewModel.danmuCoordinator,
                            displayHeight: config.height,
                            fontSize: CGFloat(viewModel.danmuSettings.danmuFontSize),
                            alpha: viewModel.danmuSettings.danmuAlpha,
                            showColorDanmu: viewModel.danmuSettings.showColorDanmu,
                            speed: viewModel.danmuSettings.danmuSpeed,
                            areaIndex: viewModel.danmuSettings.danmuAreaIndex
                        )
                        .frame(width: geometry.size.width, height: config.height)
                        .position(x: geometry.size.width / 2, y: config.yOffset + config.height / 2)
                        .allowsHitTesting(false)
                        .clipped()
                    }
                }

                // 手势层（亮度、音量、双击全屏）
                PlayerGestureView(onSingleTap: {
                    model.config.isMaskShow.toggle()
                }, isLocked: $model.isLocked)

                controllerView
            }
            .tint(.white)
            .persistentSystemOverlays(.hidden)
            .toolbar(.hidden, for: .automatic)
            .toolbar(.hidden, for: .tabBar)
            .focusedObject(model.config)
            .statusBar(hidden: isFullscreen)
            .ignoresSafeArea(isFullscreen ? .container : [], edges: .top)
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
            // 父层传入的新 URL 时，复用同一个模型，只更新 URL，避免重复创建播放器
            .onChange(of: providedURL) { newValue in
                if let newValue, model.url != newValue {
                    model.url = newValue
                }
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

    // 计算弹幕显示区域配置
    private func danmuAreaConfiguration(areaIndex: Int, containerHeight: CGFloat) -> (height: CGFloat, yOffset: CGFloat) {
        let padding: CGFloat = 5

        switch areaIndex {
        case 0: // 顶部1/4
            let height = containerHeight * 0.25
            return (height, padding)

        case 1: // 顶部1/2
            let height = containerHeight * 0.5
            return (height, padding)

        case 2: // 全屏
            return (containerHeight - padding, padding)

        case 3: // 底部1/2
            let height = containerHeight * 0.5
            let yOffset = containerHeight - height
            return (height, yOffset)

        case 4: // 底部1/4
            let height = containerHeight * 0.25
            let yOffset = containerHeight - height
            return (height, yOffset)

        default: // 默认全屏
            return (containerHeight - padding, padding)
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

    /// 锁定状态 - 锁定后禁用所有手势和控制按钮
    @Published
    var isLocked = false
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

#endif
