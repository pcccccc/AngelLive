import SwiftUI
import AngelLiveDependencies

struct TVPlayerStatisticsPanel: View {
    @ObservedObject var playerCoordinator: KSVideoPlayer.Coordinator
    let qualityTitle: String?
    let streamURL: URL?
    let onClose: () -> Void

    @FocusState private var isCloseButtonFocused: Bool

    init(
        playerCoordinator: KSVideoPlayer.Coordinator,
        qualityTitle: String? = nil,
        streamURL: URL? = nil,
        onClose: @escaping () -> Void
    ) {
        self.playerCoordinator = playerCoordinator
        self.qualityTitle = qualityTitle
        self.streamURL = streamURL
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                VStack(alignment: .leading, spacing: 20) {
                    streamInfoSection

                    if let playerLayer = playerCoordinator.playerLayer {
                        videoInfoSection(playerLayer: playerLayer)
                        performanceInfoSection(playerLayer: playerLayer)
                    } else {
                        loadingState
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .onAppear {
            isCloseButtonFocused = true
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("视频信息统计")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)

                Text("实时查看当前解码、码率和播放性能。")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(TVStatsPanelCloseButtonStyle(isFocused: isCloseButtonFocused))
            .focused($isCloseButtonFocused)
            .accessibilityLabel("关闭统计信息")
        }
    }

    private var currentPlayerType: MediaPlayerProtocol.Type {
        if let player = playerCoordinator.playerLayer?.player {
            return type(of: player)
        }
        return KSOptions.firstPlayerType
    }

    private var streamInfoSection: some View {
        sectionCard(title: "当前流", systemImage: "dot.radiowaves.left.and.right") {
            StatisticsRow(title: "播放方案", value: Self.playerDisplayName(for: currentPlayerType))

            if let qualityTitle, !qualityTitle.isEmpty {
                StatisticsRow(title: "当前清晰度", value: qualityTitle)
            }

            if let streamURL {
                StatisticsRow(title: "流协议", value: Self.streamProtocol(for: streamURL))
                StatisticsRow(title: "流地址", value: Self.formatStreamURL(streamURL))
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("正在读取播放器统计信息...")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 22)
    }

    @ViewBuilder
    private func videoInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let videoTrack = playerLayer.player.tracks(mediaType: .video).first { $0.isEnabled }
        let videoType = (videoTrack?.dynamicRange ?? .sdr).description
        let decodeType = playerLayer.options.videoDecodeType.rawValue
        let naturalSize = playerLayer.player.naturalSize
        let sizeText: String? = naturalSize.width > 0 && naturalSize.height > 0
            ? "\(Int(naturalSize.width)) x \(Int(naturalSize.height))"
            : nil

        sectionCard(title: "视频信息", systemImage: "film") {
            StatisticsRow(title: "视频类型", value: videoType)
            StatisticsRow(title: "解码方式", value: decodeType)
            if let sizeText {
                StatisticsRow(title: "视频尺寸", value: sizeText)
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
            StatisticsRow(title: "显示帧率", value: fpsText)
            StatisticsRow(title: "丢帧数", value: "\(droppedFrames)")
            StatisticsRow(title: "音视频同步", value: syncText)
            StatisticsRow(title: "网络速度", value: networkSpeed)
            StatisticsRow(title: "视频码率", value: videoBitrate)
            StatisticsRow(title: "音频码率", value: audioBitrate)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 22)
    }

    private static func playerDisplayName(for playerType: MediaPlayerProtocol.Type) -> String {
        let name = String(describing: playerType)
        return name.replacingOccurrences(of: "AngelLiveDependencies.", with: "")
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

private struct StatisticsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// 关闭按钮样式：圆形 glass 背景 + 聚焦缩放，与清晰度面板对齐
private struct TVStatsPanelCloseButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(isFocused ? 0.3 : 0.1))
            }
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}
