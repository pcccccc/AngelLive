//
//  VideoControllerView.swift
//  AngelLive
//
//  Forked and modified from KSPlayer by kintan
//  Created by pangchong on 10/26/25.
//

import Foundation
import SwiftUI
import KSPlayer
internal import AVFoundation
import AngelLiveCore
import AngelLiveDependencies

struct VideoControllerView: View {
    @ObservedObject
    private var model: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.isVerticalLiveMode) private var isVerticalLiveMode
    @State private var showDanmakuSettings = false

    private var playerWidth: CGFloat {
        model.config.playerLayer?.player.view.frame.width ?? 0
    }

    /// 检测是否为横屏
    private var isLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    init(model: KSVideoPlayerModel) {
        self.model = model
    }

    // MARK: - Helper Methods

    /// 处理返回按钮点击
    /// - iPad 全屏时：退出全屏
    /// - iPhone 横屏时：退出全屏（切换到竖屏）
    /// - 其他情况：返回上一页
    private func handleBackButton() {
        if AppConstants.Device.isIPad && isIPadFullscreen.wrappedValue {
            // iPad 全屏，退出全屏（不改变方向）
            isIPadFullscreen.wrappedValue = false
            return
        } else if !AppConstants.Device.isIPad && UIApplication.isLandscape {
            // iPhone 横屏，切换回竖屏
            KSOptions.supportedInterfaceOrientations = .portrait

            // 使用 iOS 16+ API
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else {
                    return
                }

                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: .portrait
                )

                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    print("❌ 退出全屏失败: \(error)")
                }

                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            } else {
                // iOS 16 以下降级方案
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        } else {
            // 竖屏，返回上一页
            dismiss()
            KSOptions.supportedInterfaceOrientations = .portrait
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        // 根据模式选择不同的控制层
        if isVerticalLiveMode {
            VerticalLiveControllerView(model: model)
        } else {
            ZStack {
            // 控制按钮层（带 padding）
            ZStack {
                // 左上角：返回按钮（横屏或 iPad 全屏时显示）
                if isLandscape || isIPadFullscreen.wrappedValue {
                    VStack {
                        HStack {
                            Button {
                                handleBackButton()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .ksBorderlessButton()
                            Spacer()
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // 右上角：投屏、画面平铺、画中画、设置按钮
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // AirPlay 和画面平铺仅在横屏/全屏时显示
                            if isLandscape || isIPadFullscreen.wrappedValue {
                                if model.config.playerLayer?.player.allowsExternalPlayback == true {
                                    AirPlayView()
                                        .frame(width: 30, height: 30)
                                }
                                KSVideoPlayerViewBuilder.contentModeButton(config: model.config)
                            }
                            KSVideoPlayerViewBuilder.pipButton(config: model.config)
                            SettingsButton(
                                showVideoSetting: $model.showVideoSetting,
                                showDanmakuSettings: $showDanmakuSettings
                            )
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .adaptiveGlassEffect()
                    }
                    Spacer()
                }

                // 中间：播放/暂停按钮（播放时隐藏）
                if !viewModel.isPlaying {
                    KSVideoPlayerViewBuilder.playButton(config: model.config, isPlaying: viewModel.isPlaying)
                }

                // 左下角：播放/暂停、刷新按钮
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 16) {
                            KSVideoPlayerViewBuilder.playButton(config: model.config, isToolbar: true, isPlaying: viewModel.isPlaying)
                            KSVideoPlayerViewBuilder.refreshButton(isLoading: viewModel.isLoading) {
                                viewModel.refreshPlayback()
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .adaptiveGlassEffect()
                        Spacer()
                    }
                }

                // 右下角：弹幕开关、清晰度设置、竖屏按钮（可选）、全屏按钮
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // 弹幕开关按钮
                            KSVideoPlayerViewBuilder.danmakuButton(showDanmu: $viewModel.danmuSettings.showDanmu)

                            // 清晰度设置菜单
                            KSVideoPlayerViewBuilder.qualityMenuButton(viewModel: viewModel)

                            // 竖屏按钮（仅在视频为竖屏时显示）
                            if let naturalSize = model.config.playerLayer?.player.naturalSize,
                               !naturalSize.isHorizonal {
                                KSVideoPlayerViewBuilder.portraitButton
                            }

                            // 全屏按钮
                            KSVideoPlayerViewBuilder.landscapeButton(isIPadFullscreen: isIPadFullscreen)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .adaptiveGlassEffect()
                    }
                }
            }
            .padding()
            .opacity(model.config.isMaskShow ? 1 : 0)

            // HUD 设置面板（右侧滑入，无 padding）
            if model.showVideoSetting {
                VideoSettingHUDView(model: model, isShowing: $model.showVideoSetting)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .ignoresSafeArea(edges: [.trailing, .bottom])
            }
        }
        .ksIsFocused($model.focusableView, equals: .controller)
        .font(.body)
        .buttonStyle(.borderless)
        .animation(.easeInOut(duration: 0.3), value: model.showVideoSetting)
        .sheet(isPresented: $showDanmakuSettings) {
            DanmakuSettingsSheet(isPresented: $showDanmakuSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        }
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

// HUD 样式的设置视图
struct VideoSettingHUDView: View {
    @ObservedObject
    var model: KSVideoPlayerModel
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("视频信息统计")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    isShowing = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.black.opacity(0.8))

            // 内容区域 - 使用 TimelineView 实现定期刷新
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let playerLayer = model.config.playerLayer {
                            videoInfoSection(playerLayer: playerLayer)
                            performanceInfoSection(playerLayer: playerLayer)
                        } else {
                            Text("加载中...")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.7))
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.5))
    }

    // 视频信息分组
    @ViewBuilder
    private func videoInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let videoTrack = playerLayer.player.tracks(mediaType: .video).first { $0.isEnabled }
        let videoType = (videoTrack?.dynamicRange ?? .sdr).description
        let decodeType = playerLayer.options.decodeType.rawValue

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "视频类型", value: videoType)
                InfoRow(title: "解码方式", value: decodeType)
                let naturalSize = playerLayer.player.naturalSize
                if naturalSize.width > 0 && naturalSize.height > 0 {
                    let sizeText = "\(Int(naturalSize.width)) x \(Int(naturalSize.height))"
                    InfoRow(title: "视频尺寸", value: sizeText)
                }
            }
        } label: {
            Label("视频信息", systemImage: "film")
                .foregroundStyle(.white)
        }
        .backgroundStyle(Color.black.opacity(0.3))
    }

    // 性能信息分组
    @ViewBuilder
    private func performanceInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let dynamicInfo = playerLayer.player.dynamicInfo
        let fpsText = String(format: "%.1f fps", dynamicInfo.displayFPS)
        let droppedFrames = dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount
        let syncText = String(format: "%.3f s", dynamicInfo.audioVideoSyncDiff)
        let networkSpeed = Self.formatBytes(Int64(dynamicInfo.networkSpeed)) + "/s"
        let videoBitrate = Self.formatBytes(Int64(dynamicInfo.videoBitrate)) + "ps"
        let audioBitrate = Self.formatBytes(Int64(dynamicInfo.audioBitrate)) + "ps"

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "显示帧率", value: fpsText)
                InfoRow(title: "丢帧数", value: "\(droppedFrames)")
                InfoRow(title: "音视频同步", value: syncText)
                InfoRow(title: "网络速度", value: networkSpeed)
                InfoRow(title: "视频码率", value: videoBitrate)
                InfoRow(title: "音频码率", value: audioBitrate)
            }
        } label: {
            Label("性能信息", systemImage: "speedometer")
                .foregroundStyle(.white)
        }
        .backgroundStyle(Color.black.opacity(0.3))
    }

    // 格式化字节数
    private static func formatBytes(_ bytes: Int64) -> String {
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

// HUD 信息行
struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.7))
                .font(.caption)
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .font(.caption.monospacedDigit())
        }
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

// MARK: - Glass Effect Extension
private extension View {
    @ViewBuilder
    func adaptiveGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
