//
//  PlayerControlView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/12/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
internal import AVFoundation

struct PlayerControlView: View {
    let room: LiveModel
    @Bindable var viewModel: RoomInfoViewModel
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @State private var isHovering = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var showDanmakuSettings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 控制按钮层（带 padding）
            ZStack {
                // 左上角：返回按钮
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 30, height: 30)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }

                // 右上角：画面平铺、画中画、设置按钮
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // 画面平铺按钮
                            Button {
                                coordinator.isScaleAspectFill.toggle()
                            } label: {
                                Image(systemName: coordinator.isScaleAspectFill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            // 画中画按钮
                            Button {
                                if let playerLayer = coordinator.playerLayer as? KSComplexPlayerLayer {
                                    if playerLayer.isPictureInPictureActive {
                                        playerLayer.pipStop(restoreUserInterface: true)
                                    } else {
                                        playerLayer.pipStart()
                                    }
                                }
                            } label: {
                                Image(systemName: "pip")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            // 设置按钮
                            Button {
                                showSettings.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }

                // 中间：播放/暂停大按钮（暂停时显示）
                if !viewModel.isPlaying {
                    Button {
                        if viewModel.isPlaying {
                            coordinator.playerLayer?.pause()
                        } else {
                            coordinator.playerLayer?.play()
                        }
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(20)
                    }
                    .buttonStyle(.plain)
                }

                // 左下角：播放/暂停、刷新按钮
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 16) {
                            // 播放/暂停按钮
                            Button {
                                if viewModel.isPlaying {
                                    coordinator.playerLayer?.pause()
                                } else {
                                    coordinator.playerLayer?.play()
                                }
                            } label: {
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            // 刷新按钮
                            Button {
                                Task {
                                    await viewModel.refreshPlayback()
                                }
                            } label: {
                                Image(systemName: "arrow.trianglehead.2.counterclockwise")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                                    .animation(
                                        viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                        value: viewModel.isLoading
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                }

                // 右下角：弹幕开关、清晰度设置
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // 弹幕开关
                            Button {
                                viewModel.toggleDanmuDisplay()
                            } label: {
                                Image(systemName: viewModel.danmuSettings.showDanmu ? "captions.bubble.fill" : "captions.bubble")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .contentTransition(.symbolEffect(.replace))
                            .buttonStyle(.plain)

                            // 弹幕设置
                            Button {
                                showDanmakuSettings.toggle()
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            // 清晰度设置菜单
                            if let playArgs = viewModel.currentRoomPlayArgs, !playArgs.isEmpty {
                                Menu {
                                    ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                                        Menu {
                                            ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                                                Button {
                                                    Task { @MainActor in
                                                        viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                                                    }
                                                } label: {
                                                    HStack {
                                                        Text(quality.title)
                                                        if viewModel.currentPlayQualityString == quality.title {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            Text("线路 \(cdnIndex + 1)")
                                        }
                                    }
                                } label: {
                                    Text(viewModel.currentPlayQualityString)
                                        .frame(width: 60, height: 30)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
            .opacity(isHovering ? 1 : 0)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                    resetHideTimer()
                case .ended:
                    isHovering = false
                }
            }

            // 设置面板（右侧滑入）
            if showSettings {
                HStack {
                    Spacer()
                    VideoSettingsPanel(coordinator: coordinator, isShowing: $showSettings)
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: showSettings)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isHovering)
        .sheet(isPresented: $showDanmakuSettings) {
            DanmakuSettingsPanel()
        }
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    isHovering = false
                }
            }
        }
    }
}

// 设置面板
struct VideoSettingsPanel: View {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
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

            // 内容区域
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let playerLayer = coordinator.playerLayer {
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
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.5))
    }

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

    @ViewBuilder
    private func performanceInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let dynamicInfo = playerLayer.player.dynamicInfo
        let fpsText = String(format: "%.1f fps", dynamicInfo.displayFPS)
        let droppedFrames = dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount
        let syncText = String(format: "%.3f s", dynamicInfo.audioVideoSyncDiff)
        let networkSpeed = formatBytes(Int64(dynamicInfo.networkSpeed)) + "/s"
        let videoBitrate = formatBytes(Int64(dynamicInfo.videoBitrate)) + "ps"
        let audioBitrate = formatBytes(Int64(dynamicInfo.audioBitrate)) + "ps"

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

// 信息行
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
