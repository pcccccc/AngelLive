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

struct VideoControllerView: View {
    @ObservedObject
    private var model: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    @Environment(RoomInfoViewModel.self) private var viewModel
    private var playerWidth: CGFloat {
        model.config.playerLayer?.player.view.frame.width ?? 0
    }

    init(model: KSVideoPlayerModel) {
        self.model = model
    }

    var body: some View {
        ZStack {
            // 控制按钮层（带 padding）
            ZStack {
                // 左上角：返回按钮
                VStack {
                    HStack {
                        Button {
                            dismiss()
                            KSOptions.supportedInterfaceOrientations = nil
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

                // 右上角：投屏、设置按钮
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            if model.config.playerLayer?.player.allowsExternalPlayback == true {
                                AirPlayView()
                                    .frame(width: 30, height: 30)
                            }
                            KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $model.showVideoSetting)
                        }
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
                        Spacer()
                    }
                }

                // 右下角：清晰度设置、竖屏按钮（可选）、全屏按钮
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // 清晰度设置菜单
                            KSVideoPlayerViewBuilder.qualityMenuButton(viewModel: viewModel)

                            // 竖屏按钮（仅在视频为竖屏时显示）
                            if let naturalSize = model.config.playerLayer?.player.naturalSize,
                               !naturalSize.isHorizonal {
                                KSVideoPlayerViewBuilder.portraitButton
                            }

                            // 全屏按钮
                            KSVideoPlayerViewBuilder.landscapeButton
                        }
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
                Text("播放信息")
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
