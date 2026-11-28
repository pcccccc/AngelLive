import AngelLiveDependencies
internal import AVFoundation
import SwiftUI

struct MacPlayerVideoInfoDrawer: View {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    let qualityTitle: String?
    let streamURL: URL?
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                MacPlayerDrawer(title: "视频信息统计", onClose: onClose) {
                    Text("实时查看当前流、解码方式和播放性能。")
                } content: {
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            VStack(alignment: .leading, spacing: 16) {
                                streamInfoSection
                                if let layer = coordinator.playerLayer {
                                    videoInfoSection(playerLayer: layer)
                                    performanceInfoSection(playerLayer: layer)
                                } else {
                                    ProgressView("正在读取播放器统计信息…")
                                }
                            }
                        }
                    }
                }
                .macPlayerDrawerPlacement(in: geometry.size)
            }
        }
    }

    private var currentPlayerType: MediaPlayerProtocol.Type {
        if let player = coordinator.playerLayer?.player {
            return type(of: player)
        }
        return KSOptions.firstPlayerType
    }

    private var streamInfoSection: some View {
        sectionCard(title: "当前流", systemImage: "dot.radiowaves.left.and.right") {
            InfoRow(title: "播放方案", value: Self.playerDisplayName(for: currentPlayerType))

            if let quality = qualityTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !quality.isEmpty, quality != "清晰度" {
                InfoRow(title: "当前清晰度", value: quality)
            }

            if let streamURL {
                InfoRow(title: "流协议", value: Self.streamProtocol(for: streamURL))
                InfoRow(title: "流地址", value: Self.formatStreamURL(streamURL))
            }
        }
    }

    private func videoInfoSection(playerLayer: KSPlayerLayer) -> some View {
        let videoTrack = playerLayer.player.tracks(mediaType: .video).first { $0.isEnabled }
        let videoType = (videoTrack?.dynamicRange ?? .sdr).description
        let decodeType = playerLayer.options.videoDecodeType.rawValue
        let naturalSize = playerLayer.player.naturalSize
        let sizeText: String? = naturalSize.width > 0 && naturalSize.height > 0
            ? "\(Int(naturalSize.width)) x \(Int(naturalSize.height))"
            : nil

        return sectionCard(title: "视频信息", systemImage: "film") {
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
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
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
        let host = url.host() ?? url.scheme ?? ""
        return url.lastPathComponent.isEmpty ? host : "\(host)/\(url.lastPathComponent)"
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
