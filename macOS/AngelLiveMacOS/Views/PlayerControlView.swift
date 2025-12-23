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
import Kingfisher
internal import AVFoundation

struct PlayerControlView: View {
    let room: LiveModel
    @Bindable var viewModel: RoomInfoViewModel
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @State private var isHovering = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var showDanmakuSettings = false
    @State private var isFavoriteAnimating = false
    @State private var isFullscreen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager: FullscreenPlayerManager?

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == room.roomId })
    }

    var body: some View {
        ZStack {
            // 控制按钮层（带 padding）- 强制 dark mode
            ZStack {
                // 左上角：关闭按钮和主播信息
                VStack {
                    HStack(spacing: 12) {
                        // 关闭按钮
                        Button {
                            closePlayer()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .adaptiveGlassEffect(in: .circle)

                        // 主播信息卡片
                        streamerInfoCard

                        Spacer()
                    }
                    .frame(height: 44)  // 固定高度确保对齐
                    Spacer()
                }
                .environment(\.colorScheme, .dark)

                // 右上角：画面平铺、画中画、设置按钮
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // 画中画按钮（系统 PiP）
                            Button {
                                toggleSystemPip()
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .adaptiveGlassEffect()
                    }
                    .frame(height: 44)  // 固定高度与左侧对齐
                    .environment(\.colorScheme, .dark)
                    Spacer()
                }
                .environment(\.colorScheme, .dark)

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
                    .adaptiveGlassEffect(in: .circle)
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
                        .adaptiveGlassEffect()
                        Spacer()
                    }
                }
                .environment(\.colorScheme, .dark)

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
                                                        if viewModel.currentCdnIndex == cdnIndex && viewModel.currentPlayQualityQn == quality.qn {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            Text(cdn.cdn.isEmpty ? "线路 \(cdnIndex + 1)" : cdn.cdn)
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

                            // 全屏按钮
                            Button {
                                toggleFullscreen()
                            } label: {
                                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .adaptiveGlassEffect()
                        .fixedSize(horizontal: true, vertical: true) // macOS 15: 避免过度拉伸导致宽度异常
                    }
                }
                .environment(\.colorScheme, .dark)
            }
            .padding()
            .environment(\.colorScheme, .dark)
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
            DanmakuSettingsPanel(viewModel: viewModel)
        }
    }

    // MARK: - 主播信息卡片
    private var streamerInfoCard: some View {
        HStack(spacing: 10) {
            // 主播头像
            KFImage(URL(string: room.userHeadImg))
                .placeholder {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                // 主播名称
                Text(String(room.userName.prefix(10)))
                    .foregroundStyle(.white)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                // 房间标题
                Text(String(room.roomTitle.prefix(20)))
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.caption)
                    .lineLimit(1)
            }

            // 收藏按钮
            Button {
                Task {
                    await toggleFavorite()
                }
            } label: {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isFavorited ? .red : .white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .adaptiveGlassEffect()
    }

    // MARK: - Helper Methods
    @MainActor
    private func toggleFavorite() async {
        do {
            if isFavorited {
                try await favoriteModel.removeFavoriteRoom(room: room)
            } else {
                try await favoriteModel.addFavorite(room: room)
            }
            isFavoriteAnimating.toggle()
        } catch {
            print("收藏操作失败: \(error)")
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

    private func toggleFullscreen() {
        guard let window = NSApplication.shared.keyWindow else { return }
        window.toggleFullScreen(nil)
        isFullscreen.toggle()
    }

    private func closePlayer() {
        // 如果是全屏模式打开的播放器，关闭时返回主界面
        if let manager = fullscreenPlayerManager, manager.showFullscreenPlayer {
            manager.closeFullscreenPlayer()
        } else {
            // 否则使用 dismiss 关闭窗口
            dismiss()
        }
    }

    private func toggleSystemPip() {
        if let playerLayer = coordinator.playerLayer as? KSComplexPlayerLayer {
            if playerLayer.isPictureInPictureActive {
                playerLayer.pipStop(restoreUserInterface: true)
            } else {
                playerLayer.pipStart()
            }
        } else {
            print("❌ ERROR: playerLayer is not a KSComplexPlayerLayer.")
        }
    }
}

// 设置面板
struct VideoSettingsPanel: View {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @Binding var isShowing: Bool
    @State private var resolvedPlayerLayer: KSPlayerLayer?
    @State private var resolveTask: Task<Void, Never>?

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
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let playerLayer = resolvedPlayerLayer ?? coordinator.playerLayer {
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
        .task(id: isShowing) {
            // 打开面板时尝试获取 playerLayer，避免因未发布的属性导致一直“加载中”
            resolveTask?.cancel()
            guard isShowing else { return }
            resolveTask = Task {
                for _ in 0..<30 {
                    if let layer = coordinator.playerLayer {
                        await MainActor.run {
                            resolvedPlayerLayer = layer
                        }
                        break
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                }
            }
        }
        .onDisappear {
            resolveTask?.cancel()
        }
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

// MARK: - Glass Effect Extension
private extension View {
    @ViewBuilder
    func adaptiveGlassEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func adaptiveGlassEffect(in shape: GlassEffectShape) -> some View {
        if #available(macOS 26.0, *) {
            switch shape {
            case .capsule:
                self.glassEffect(in: .capsule)
            case .circle:
                self.glassEffect(in: .circle)
            }
        } else {
            switch shape {
            case .capsule:
                self.background(.ultraThinMaterial, in: Capsule())
            case .circle:
                self.background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}

private enum GlassEffectShape {
    case capsule
    case circle
}
