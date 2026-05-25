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
import AppKit
internal import AVFoundation

struct PlayerControlView: View {
    let room: LiveModel
    @Bindable var viewModel: RoomInfoViewModel
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @State private var isHovering = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var showDanmakuSettings = false
    @State private var showStreamerInfo = false
    @State private var isFavoriteAnimating = false
    @State private var isFavoriteLoading = false
    @State private var isFullscreen = false
    @State private var isPinned = false
    @State private var showVolumeSlider = false
    @Binding var volume: Float  // 独立音量控制
    @Binding var isMuted: Bool      // 独立静音状态
    @Environment(\.dismiss) private var dismiss
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager: FullscreenPlayerManager?
    @Environment(ToastManager.self) private var toastManager: ToastManager?

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == room.roomId })
    }

    /// 流首次加载或缓冲中：避免在 loading overlay 之上又叠一个中间播放按钮。
    private var isStreamLoadingOrBuffering: Bool {
        let state = coordinator.state
        if state == .buffering { return true }
        if coordinator.playerLayer?.player.playbackState == .seeking { return true }
        switch state {
        case .initialized, .preparing, .readyToPlay:
            return !viewModel.isPlaying
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            // 顶部拖动区域（放在最底层，不影响控件点击）
            VStack {
                WindowDragArea()
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
                    .background(Color.black.opacity(0.001))
                Spacer()
            }

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
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .adaptiveGlassEffect(in: .circle)

                        // 主播信息卡片
                        streamerInfoCard

                        Spacer()
                    }
                    .frame(height: 44)  // 固定高度确保对齐
                    Spacer()
                }
                .environment(\.colorScheme, .dark)

                // 右上角：置顶、设置按钮
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            // 置顶按钮
                            Button {
                                toggleWindowPin()
                            } label: {
                                Image(systemName: isPinned ? "pin.fill" : "pin")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .contentTransition(.opacity)
                                    .animation(.easeInOut(duration: 0.15), value: isPinned)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())

                            // 设置按钮
                            Button {
                                showSettings.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .frame(width: 30, height: 30)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
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

                // 中间：播放/暂停大按钮（暂停时显示；加载/缓冲时让位给 loading overlay）
                if !viewModel.isPlaying && !isStreamLoadingOrBuffering {
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
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .adaptiveGlassEffect(in: .circle)
                }

                // 左下角：播放/暂停、刷新、音量按钮
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
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())

                            // 刷新按钮
                            Button {
                                viewModel.refreshPlayback()
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
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .disabled(viewModel.isLoading)

                            // 音量控制（悬停展开）
                            HStack(spacing: 12) {
                                // 音量按钮（点击静音/取消静音）
                                Button {
                                    isMuted.toggle()
                                    coordinator.playerLayer?.player.isMuted = isMuted
                                } label: {
                                    Image(systemName: isMuted ? "speaker.slash.fill" : (volume > 0.5 ? "speaker.wave.2.fill" : (volume > 0 ? "speaker.wave.1.fill" : "speaker.fill")))
                                        .frame(width: 30, height: 30)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())

                                // 音量滑块（悬停时显示）
                                if showVolumeSlider {
                                    HStack(spacing: 8) {
                                        VolumeSlider(value: $volume)
                                            .frame(width: 80, height: 20)
                                            .onChange(of: volume) { _, newValue in
                                                if isMuted, newValue > 0 {
                                                    isMuted = false
                                                    coordinator.playerLayer?.player.isMuted = false
                                                }
                                                coordinator.playerLayer?.player.playbackVolume = newValue
                                            }

                                        Text("\(Int(volume * 100))%")
                                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.8))
                                            .frame(width: 36, alignment: .trailing)
                                    }
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                                        removal: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity)
                                    ))
                                }
                            }
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showVolumeSlider = hovering
                                }
                            }
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
                            if viewModel.supportsDanmu {
                                // 弹幕开关
                                Button {
                                    viewModel.toggleDanmuDisplay()
                                } label: {
                                    Image(systemName: viewModel.danmuSettings.showDanmu ? "captions.bubble.fill" : "captions.bubble")
                                        .frame(width: 30, height: 30)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .contentShape(Rectangle())
                                }
                                .contentTransition(.symbolEffect(.replace))
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())

                                // 弹幕设置
                                Button {
                                    showDanmakuSettings.toggle()
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .frame(width: 30, height: 30)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }

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
                                                        if viewModel.currentCdnIndex == cdnIndex && viewModel.currentQualityIndex == urlIndex {
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
                                        .frame(height: 30)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
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
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
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
            .animation(.easeInOut(duration: 0.3), value: isHovering)
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
                    VideoSettingsPanel(
                        coordinator: coordinator,
                        qualityTitle: viewModel.currentPlayQualityString,
                        streamURL: viewModel.currentPlayURL,
                        isShowing: $showSettings
                    )
                        .frame(width: 380)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: showSettings)
            }
        }
        .sheet(isPresented: $showDanmakuSettings) {
            DanmakuSettingsPanel(viewModel: viewModel)
        }
        // 鼠标自动隐藏:绑在 NSView 生命周期上,视图析构时一定恢复
        .background(PlayerCursorAutoHide(hideDelay: 2.5))
        .onAppear {
            syncPinnedState()
        }
        .onDisappear {
            hideTask?.cancel()
        }
    }

    // MARK: - 主播信息卡片
    private var streamerInfoCard: some View {
        HStack(spacing: 10) {
            // 主播头像 + 文本（可点击查看主播信息）
            Button {
                showStreamerInfo.toggle()
            } label: {
                HStack(spacing: 10) {
                    RemoteAvatarView(url: URL(string: room.userHeadImg), size: 36) {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(5)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        // 主播名称
                        Text(String(room.userName.prefix(10)).orDash)
                            .foregroundStyle(.white)
                            .font(.subheadline.bold())
                            .lineLimit(1)

                        // 房间标题
                        Text(String(room.roomTitle.prefix(20)).orDash)
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看主播信息")
            .popover(isPresented: $showStreamerInfo, arrowEdge: .bottom) {
                StreamerInfoPopover(room: room)
                    .environment(\.colorScheme, .light)
            }

            // 收藏按钮
            Button {
                Task {
                    await toggleFavorite()
                }
            } label: {
                Group {
                    if isFavoriteLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(isFavorited ? .red : .white)
                            .frame(width: 28, height: 28)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(isFavoriteLoading)
            .changeEffect(
                .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart.slash.fill")
                        .foregroundStyle(.red)
                }, value: isFavoriteAnimating
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .adaptiveGlassEffect()
    }

    // MARK: - Helper Methods
    @MainActor
    private func toggleFavorite() async {
        guard !isFavoriteLoading else { return }
        isFavoriteLoading = true
        defer { isFavoriteLoading = false }

        do {
            if isFavorited {
                try await favoriteModel.removeFavoriteRoom(room: room)
            } else {
                try await favoriteModel.addFavorite(room: room)
            }
            isFavoriteAnimating.toggle()
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            toastManager?.show(icon: "xmark.circle.fill", message: isFavorited ? "取消收藏失败：\(errorMessage)" : "收藏失败：\(errorMessage)", type: .error)
            print("收藏操作失败: \(error)")
        }
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
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
        // 鼠标显示由 PlayerCursorAutoHide 视图的析构自动处理
        if let manager = fullscreenPlayerManager, manager.showFullscreenPlayer {
            manager.closeFullscreenPlayer()
        } else {
            dismiss()
        }
    }

    private func toggleWindowPin() {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
        isPinned.toggle()
        window.level = isPinned ? .floating : .normal
    }

    private func syncPinnedState() {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
        isPinned = window.level == .floating
    }
}

// 设置面板
struct VideoSettingsPanel: View {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    let qualityTitle: String?
    let streamURL: URL?
    @Binding var isShowing: Bool
    @State private var resolvedPlayerLayer: KSPlayerLayer?
    @State private var resolveTask: Task<Void, Never>?

    private var normalizedQualityTitle: String? {
        guard let qualityTitle else { return nil }
        let trimmed = qualityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "清晰度" else { return nil }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        streamInfoSection

                        if let playerLayer = resolvedPlayerLayer ?? coordinator.playerLayer {
                            videoInfoSection(playerLayer: playerLayer)
                            performanceInfoSection(playerLayer: playerLayer)
                        } else {
                            loadingState
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .task(id: isShowing) {
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
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        .onDisappear {
            resolveTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("视频信息统计")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("实时查看当前流、解码方式和播放性能。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 12)

            Button {
                isShowing = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .adaptiveGlassEffect(in: .circle)
        }
    }

    private var streamInfoSection: some View {
        sectionCard(title: "当前流", systemImage: "dot.radiowaves.left.and.right") {
            InfoRow(title: "播放方案", value: Self.playerDisplayName(for: KSOptions.firstPlayerType))

            if let normalizedQualityTitle {
                InfoRow(title: "当前清晰度", value: normalizedQualityTitle)
            }

            if let streamURL {
                InfoRow(title: "流协议", value: Self.streamProtocol(for: streamURL))
                InfoRow(title: "流地址", value: Self.formatStreamURL(streamURL))
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("正在读取播放器统计信息...")
                .foregroundStyle(.white.opacity(0.72))
                .font(.system(size: 15, weight: .medium))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 20)
    }

    @ViewBuilder
    private func videoInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let videoTrack = playerLayer.player.tracks(mediaType: .video).first { $0.isEnabled }
        let videoType = (videoTrack?.dynamicRange ?? .sdr).description
        let decodeType = playerLayer.options.decodeType.rawValue
        let naturalSize = playerLayer.player.naturalSize
        let sizeText: String? = naturalSize.width > 0 && naturalSize.height > 0
            ? "\(Int(naturalSize.width)) x \(Int(naturalSize.height))"
            : nil

        sectionCard(title: "视频信息", systemImage: "film") {
            InfoRow(title: "视频类型", value: videoType)
            InfoRow(title: "解码方式", value: decodeType)
            if let sizeText {
                InfoRow(title: "视频尺寸", value: sizeText)
            }
        }
    }

    @ViewBuilder
    private func performanceInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let dynamicInfo = playerLayer.player.dynamicInfo
        let fpsText = String(format: "%.1f fps", dynamicInfo.displayFPS)
        let droppedFrames = dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount
        let syncText = String(format: "%.3f s", dynamicInfo.audioVideoSyncDiff)
        let networkSpeed = Self.formatBytes(Int64(dynamicInfo.networkSpeed)) + "/s"
        let videoBitrate = Self.formatBytes(Int64(dynamicInfo.videoBitrate)) + "ps"
        let audioBitrate = Self.formatBytes(Int64(dynamicInfo.audioBitrate)) + "ps"

        sectionCard(title: "性能信息", systemImage: "speedometer") {
            InfoRow(title: "显示帧率", value: fpsText)
            InfoRow(title: "丢帧数", value: "\(droppedFrames)")
            InfoRow(title: "音视频同步", value: syncText)
            InfoRow(title: "网络速度", value: networkSpeed)
            InfoRow(title: "视频码率", value: videoBitrate)
            InfoRow(title: "音频码率", value: audioBitrate)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 20)
    }

    private static func playerDisplayName(for playerType: MediaPlayerProtocol.Type) -> String {
        let name = String(describing: playerType)
        if name.contains("KSAVPlayer") {
            return "AVPlayer"
        }
        if name.contains("KSMEPlayer") {
            return "MEPlayer"
        }
        return name
            .replacingOccurrences(of: "AngelLiveDependencies.", with: "")
            .replacingOccurrences(of: "KSPlayer.", with: "")
    }

    private static func streamProtocol(for url: URL) -> String {
        let lowercasedPath = url.path.lowercased()
        if lowercasedPath.contains(".m3u8") {
            return "HLS"
        }
        if lowercasedPath.contains(".flv") {
            return "FLV"
        }
        return url.scheme?.uppercased() ?? "未知"
    }

    private static func formatStreamURL(_ url: URL) -> String {
        let host = url.host() ?? url.host ?? url.absoluteString
        let lastPathComponent = url.lastPathComponent
        guard !lastPathComponent.isEmpty else { return host }

        if lastPathComponent.count <= 36 {
            return "\(host)/\(lastPathComponent)"
        }

        let prefix = lastPathComponent.prefix(16)
        let suffix = lastPathComponent.suffix(12)
        return "\(host)/\(prefix)...\(suffix)"
    }

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

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.white.opacity(0.72))
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Glass Effect Extension
private extension View {
    @ViewBuilder
    func adaptiveGlassEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func adaptiveGlassEffect(in shape: GlassEffectShape) -> some View {
        if #available(macOS 26.0, *) {
            switch shape {
            case .capsule:
                self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)), in: .capsule)
            case .circle:
                self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)), in: .circle)
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

    @ViewBuilder
    func adaptiveGlassEffectRoundedRect(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private enum GlassEffectShape {
    case capsule
    case circle
}

// MARK: - Volume Slider (AppKit)
/// 使用 AppKit NSSlider 实现的音量滑块
private struct VolumeSlider: NSViewRepresentable {
    @Binding var value: Float

    func makeNSView(context: Context) -> NSSlider {
        let slider = NoWindowDragSlider(value: Double(value), minValue: 0, maxValue: 1, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.trackFillColor = .white.withAlphaComponent(0.8)
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.doubleValue = Double(value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: VolumeSlider

        init(_ parent: VolumeSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = Float(sender.doubleValue)
        }
    }
}

private final class NoWindowDragSlider: NSSlider {
    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableView {
        DraggableView()
    }

    func updateNSView(_ nsView: DraggableView, context: Context) {}
}

private final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Player Cursor Auto Hide
// 把"鼠标静止 N 秒后隐藏,有活动立即显示"绑在 NSView 生命周期上。
// 关键点:NSView 的 deinit 和 viewWillMove(toWindow: nil) 是确定性回调,
// SwiftUI 退出播放器视图时一定会触发 -> 一定会恢复鼠标。

struct PlayerCursorAutoHide: NSViewRepresentable {
    let hideDelay: TimeInterval

    func makeNSView(context: Context) -> CursorAutoHideNSView {
        CursorAutoHideNSView(hideDelay: hideDelay)
    }

    func updateNSView(_ nsView: CursorAutoHideNSView, context: Context) {
        nsView.hideDelay = hideDelay
    }
}

final class CursorAutoHideNSView: NSView {
    var hideDelay: TimeInterval
    private var monitor: Any?
    private var hideTimer: Timer?
    private var didHide = false

    init(hideDelay: TimeInterval) {
        self.hideDelay = hideDelay
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // 离开窗口时立刻拆除并恢复鼠标
        if newWindow == nil {
            teardown()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            install()
        }
    }

    deinit {
        // 终极兜底:就算 viewWillMove 没被触发,deinit 也一定会触发
        if let m = monitor { NSEvent.removeMonitor(m) }
        hideTimer?.invalidate()
        if didHide {
            NSCursor.unhide()
        }
    }

    // MARK: setup/teardown

    private func install() {
        guard monitor == nil else { return }
        window?.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
            .keyDown
        ]) { [weak self] event in
            self?.handleActivity()
            return event
        }
        // 首次出现:启动隐藏计时器(此时鼠标可见)
        scheduleHide()
    }

    private func teardown() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        hideTimer?.invalidate()
        hideTimer = nil
        showCursorNow()
    }

    // MARK: handlers

    private func handleActivity() {
        showCursorNow()
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            self?.hideCursorNow()
        }
    }

    private func hideCursorNow() {
        guard !didHide else { return }
        guard let window = window, window.isVisible else { return }
        // 仅在鼠标处于本窗口范围内时才隐藏,避免影响其他窗口
        let mouseLocation = NSEvent.mouseLocation
        guard window.frame.contains(mouseLocation) else { return }
        NSCursor.hide()
        didHide = true
    }

    private func showCursorNow() {
        guard didHide else { return }
        NSCursor.unhide()
        didHide = false
    }
}
