import Foundation

public enum RoomPlaybackPlayerKind: Sendable, Equatable, Hashable {
    case avPlayer
    case mePlayer
}

public struct RoomPlaybackSelection: Sendable {
    public let cdnIndex: Int
    public let qualityIndex: Int
    public let quality: LiveQualityDetail

    public init(cdnIndex: Int, qualityIndex: Int, quality: LiveQualityDetail) {
        self.cdnIndex = cdnIndex
        self.qualityIndex = qualityIndex
        self.quality = quality
    }
}

public struct RoomPlaybackPlan: Sendable {
    public let playerKinds: [RoomPlaybackPlayerKind]
    public let isHLS: Bool
    public let isLive: Bool
    public let streamFormat: LivePlaybackStreamFormat
    public let overrideURL: URL?
    public let overrideTitle: String?
    public let resolvedSelection: RoomPlaybackSelection?

    public init(
        playerKinds: [RoomPlaybackPlayerKind],
        isHLS: Bool,
        isLive: Bool,
        streamFormat: LivePlaybackStreamFormat,
        overrideURL: URL? = nil,
        overrideTitle: String? = nil,
        resolvedSelection: RoomPlaybackSelection? = nil
    ) {
        self.playerKinds = playerKinds
        self.isHLS = isHLS
        self.isLive = isLive
        self.streamFormat = streamFormat
        self.overrideURL = overrideURL
        self.overrideTitle = overrideTitle
        self.resolvedSelection = resolvedSelection
    }
}

public struct RoomPlaybackRequestOptions: Sendable {
    public let userAgent: String
    public let headers: [String: String]

    public init(userAgent: String, headers: [String: String]) {
        self.userAgent = userAgent
        self.headers = headers
    }
}

public struct RoomPlaybackDebugContext: Sendable {
    public let tappedSelection: RoomPlaybackSelection?
    public let effectiveSelection: RoomPlaybackSelection?

    public init(
        tappedSelection: RoomPlaybackSelection?,
        effectiveSelection: RoomPlaybackSelection?
    ) {
        self.tappedSelection = tappedSelection
        self.effectiveSelection = effectiveSelection
    }
}

/// 用户点击被锁定档位时宿主应做的事（登录协议 v1 `authLimit.reason`）。
public enum PlaybackQualityLockAction: Sendable, Equatable {
    /// 未登录：引导登录，登录后刷新播放信息。message 用于无法发起登录时兜底提示。
    case requestLogin(message: String)
    /// 会员等登录也解决不了的限制：只展示 message，不切换。
    case showMessage(String)
}

public enum RoomPlaybackResolver {
    public static func isHLSQuality(_ quality: LiveQualityDetail) -> Bool {
        quality.liveCodeType == .hls || quality.url.lowercased().contains(".m3u8")
    }

    /// 插件显式 latencyMode 优先；仅缺失时才用 URL 中 `llhls.m3u8` 托底。
    /// 这类 master 通常暴露多路 video/audio rendition,FFmpeg(KSMEPlayer)会对每路串行跑
    /// find_stream_info,起播 ~16s 且可能拖过短时效 token 导致 403;故应优先走原生 AVPlayer。
    /// 用 URL 特征判定,不绑任何平台名。
    public static func isLowLatencyHLS(_ quality: LiveQualityDetail) -> Bool {
        guard streamFormat(for: quality) == .hlsLive else { return false }
        switch quality.playbackHints?.latencyMode {
        case .lowLatency:
            return true
        case .standard:
            return false
        case nil:
            return isHLSQuality(quality) && quality.url.lowercased().contains("llhls.m3u8")
        }
    }

    public static func streamFormat(for quality: LiveQualityDetail) -> LivePlaybackStreamFormat {
        if let format = quality.playbackHints?.streamFormat, format != .unknown {
            return format
        }
        if isHLSQuality(quality) {
            return .hlsLive
        }
        if quality.liveCodeType == .flv {
            return .flv
        }
        return .unknown
    }

    public static func streamTypeIdentifier(for quality: LiveQualityDetail) -> String {
        switch streamFormat(for: quality) {
        case .hlsLive, .hlsVod:
            return "hls"
        case .dash:
            return "dash"
        case .flv, .unknown:
            return "flv"
        }
    }

    public static func streamTypeDisplayName(for quality: LiveQualityDetail) -> String {
        switch streamFormat(for: quality) {
        case .hlsLive:
            return "HLS"
        case .hlsVod:
            return "HLS VOD"
        case .dash:
            return "DASH"
        case .flv, .unknown:
            return "FLV"
        }
    }

    public static func selection(
        in playArgs: [LiveQualityModel]?,
        cdnIndex: Int,
        qualityIndex: Int
    ) -> RoomPlaybackSelection? {
        guard let playArgs,
              playArgs.indices.contains(cdnIndex),
              playArgs[cdnIndex].qualitys.indices.contains(qualityIndex) else {
            return nil
        }

        return RoomPlaybackSelection(
            cdnIndex: cdnIndex,
            qualityIndex: qualityIndex,
            quality: playArgs[cdnIndex].qualitys[qualityIndex]
        )
    }

    /// 将偏好的线路/清晰度索引夹到可用范围内。
    /// 用于重新拉取播放参数后尽量保持用户当前选择,避免无感续播时跳回默认档。
    public static func clampedSelection(
        in playArgs: [LiveQualityModel],
        preferredCdnIndex: Int,
        preferredQualityIndex: Int
    ) -> (cdnIndex: Int, qualityIndex: Int) {
        guard !playArgs.isEmpty else { return (0, 0) }
        let cdnIndex = min(max(0, preferredCdnIndex), playArgs.count - 1)
        let qualities = playArgs[cdnIndex].qualitys
        guard !qualities.isEmpty else { return (cdnIndex, 0) }
        let qualityIndex = min(max(0, preferredQualityIndex), qualities.count - 1)
        return (cdnIndex, qualityIndex)
    }

    // MARK: - 画质锁（登录协议 v1 playbackHints.authLimit）

    /// 插件对该档画质标记的登录/会员限制；nil 表示当前用户可用。
    public static func authLimit(of quality: LiveQualityDetail) -> LivePlaybackAuthLimit? {
        quality.playbackHints?.authLimit
    }

    /// 当前用户拿不到该档（插件仍给出降级 url），自动选择时应跳过。
    public static func isLocked(_ quality: LiveQualityDetail) -> Bool {
        authLimit(of: quality) != nil
    }

    /// 画质行上「锁」徽标的文案。
    public static func lockBadgeTitle(for quality: LiveQualityDetail) -> String? {
        guard let limit = authLimit(of: quality) else { return nil }
        return limit.message ?? "登录后可用"
    }

    /// 用户点击该档位时的拦截动作；未锁定返回 nil，按原逻辑切换。
    public static func lockAction(for quality: LiveQualityDetail) -> PlaybackQualityLockAction? {
        guard let limit = authLimit(of: quality) else { return nil }
        if limit.requiresLogin {
            return .requestLogin(message: limit.message ?? "登录后可用")
        }
        return .showMessage(limit.message ?? "当前账号暂无法观看该画质")
    }

    /// 自动选择（进房 / 重新取参）使用的线路与清晰度：
    /// 先按 `clampedSelection` 保持当前选择，命中被锁定的档位时改选最近的未锁定档位
    /// （同线路内优先往后找更低档，再往前；同线路全锁时再看其他线路）。
    /// 全部被锁定时退回 `clampedSelection` 的结果，保持原播放逻辑。
    /// `allowsOtherCDN` 为 false 时只在偏好线路内挑选（恢复协调器切线路时使用，避免跳回原线路）。
    public static func automaticSelection(
        in playArgs: [LiveQualityModel],
        preferredCdnIndex: Int,
        preferredQualityIndex: Int,
        allowsOtherCDN: Bool = true
    ) -> (cdnIndex: Int, qualityIndex: Int) {
        let clamped = clampedSelection(
            in: playArgs,
            preferredCdnIndex: preferredCdnIndex,
            preferredQualityIndex: preferredQualityIndex
        )
        guard playArgs.indices.contains(clamped.cdnIndex) else { return clamped }
        let preferredQualities = playArgs[clamped.cdnIndex].qualitys
        guard preferredQualities.indices.contains(clamped.qualityIndex),
              isLocked(preferredQualities[clamped.qualityIndex]) else {
            return clamped
        }

        func nearestUnlockedIndex(in qualities: [LiveQualityDetail], around index: Int) -> Int? {
            guard !qualities.isEmpty else { return nil }
            let pivot = min(max(0, index), qualities.count - 1)
            let after = qualities.indices.filter { $0 > pivot }
            let before = qualities.indices.filter { $0 < pivot }.reversed()
            return ([pivot] + after + before).first { !isLocked(qualities[$0]) }
        }

        if let qualityIndex = nearestUnlockedIndex(in: preferredQualities, around: clamped.qualityIndex) {
            return (clamped.cdnIndex, qualityIndex)
        }
        guard allowsOtherCDN else { return clamped }
        for (cdnIndex, cdn) in playArgs.enumerated() where cdnIndex != clamped.cdnIndex {
            if let qualityIndex = nearestUnlockedIndex(in: cdn.qualitys, around: clamped.qualityIndex) {
                return (cdnIndex, qualityIndex)
            }
        }
        return clamped
    }

    public static func firstSelection(in playArgs: [LiveQualityModel]?) -> RoomPlaybackSelection? {
        guard let playArgs else { return nil }
        for (cdnIndex, cdn) in playArgs.enumerated() {
            if let quality = cdn.qualitys.first {
                return RoomPlaybackSelection(cdnIndex: cdnIndex, qualityIndex: 0, quality: quality)
            }
        }
        return nil
    }

    public static func firstSelection(
        in playArgs: [LiveQualityModel]?,
        where predicate: (LiveQualityDetail) -> Bool
    ) -> RoomPlaybackSelection? {
        guard let playArgs else { return nil }
        for (cdnIndex, cdn) in playArgs.enumerated() {
            for (qualityIndex, quality) in cdn.qualitys.enumerated() where predicate(quality) {
                return RoomPlaybackSelection(cdnIndex: cdnIndex, qualityIndex: qualityIndex, quality: quality)
            }
        }
        return nil
    }

    public static func findHLSQuality(in playArgs: [LiveQualityModel]?) -> LiveQualityDetail? {
        firstSelection(in: playArgs, where: isHLSQuality)?.quality
    }

    public static func findFirstQuality(in playArgs: [LiveQualityModel]?) -> LiveQualityDetail? {
        firstSelection(in: playArgs)?.quality
    }

    public static func firstPlayableURL(from playArgs: [LiveQualityModel]) -> URL? {
        for cdn in playArgs {
            for quality in cdn.qualitys {
                if let url = playableURL(for: quality) {
                    return url
                }
            }
        }
        return nil
    }

    public static func playableURL(for quality: LiveQualityDetail) -> URL? {
        let normalizedURL = quality.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedURL.isEmpty else { return nil }
        return URL(string: normalizedURL)
    }

    public static func playbackContext(cdn: LiveQualityModel, quality: LiveQualityDetail) -> [String: Any] {
        var context: [String: Any] = [:]

        for (key, value) in cdn.requestContext ?? [:] {
            context[key] = value
        }
        for (key, value) in quality.requestContext ?? [:] {
            context[key] = value
        }

        if context["qn"] == nil {
            context["qn"] = quality.qn
        }
        if context["rate"] == nil {
            context["rate"] = quality.qn
        }
        if context["quality"] == nil {
            context["quality"] = quality.title
        }
        if context["title"] == nil {
            context["title"] = quality.title
        }
        if context["liveCodeType"] == nil {
            context["liveCodeType"] = quality.liveCodeType.rawValue
        }

        let streamType = streamTypeIdentifier(for: quality)
        if context["streamType"] == nil {
            context["streamType"] = streamType
        }
        if context["format"] == nil {
            context["format"] = streamType
        }

        let normalizedCDN = cdn.cdn.trimmingCharacters(in: .whitespacesAndNewlines)
        if context["cdn"] == nil, !normalizedCDN.isEmpty {
            context["cdn"] = normalizedCDN
        }

        if context["gear"] == nil {
            context["gear"] = quality.qn
        }
        return context
    }

    public static func selectionBehavior(for quality: LiveQualityDetail) -> LivePlaybackSelectionBehavior {
        quality.playbackHints?.selectionBehavior ?? .direct
    }

    public static func requiresRefreshOnSelect(_ quality: LiveQualityDetail) -> Bool {
        selectionBehavior(for: quality) == .refreshOnSelect
    }

    public static func shouldRefreshPlaybackOnSelection(
        _ quality: LiveQualityDetail,
        currentPlayURL: URL?
    ) -> Bool {
        guard requiresRefreshOnSelect(quality) else { return false }
        return currentPlayURL != nil || playableURL(for: quality) == nil
    }

    public static func requestOptions(
        for quality: LiveQualityDetail,
        fallbackUserAgent: String
    ) -> RoomPlaybackRequestOptions {
        let customUA = quality.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userAgent = (customUA?.isEmpty == false) ? customUA! : fallbackUserAgent

        var headers = quality.headers ?? [:]
        if headers["User-Agent"] == nil && headers["user-agent"] == nil {
            headers["user-agent"] = userAgent
        }

        return RoomPlaybackRequestOptions(userAgent: userAgent, headers: headers)
    }

    public static func cdnDisplayName(for cdn: LiveQualityModel) -> String {
        let displayName = cdn.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty {
            return displayName
        }

        let normalizedCDN = cdn.cdn.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedCDN.isEmpty ? "未设置" : normalizedCDN
    }

    public static func qualityDisplayTitle(
        _ quality: LiveQualityDetail,
        in playArgs: [LiveQualityModel]?
    ) -> String {
        let normalizedTitle = quality.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = normalizedTitle.isEmpty ? "未命名清晰度" : normalizedTitle
        guard hasDuplicateTitleWithDifferentStreamType(
            in: playArgs,
            title: normalizedTitle,
            targetStreamTypeIdentifier: streamTypeIdentifier(for: quality)
        ) else {
            return baseTitle
        }

        return "\(baseTitle) \(streamTypeDisplayName(for: quality))"
    }

    public static func qualityDisplayTitle(
        in playArgs: [LiveQualityModel]?,
        selection: RoomPlaybackSelection?
    ) -> String {
        guard let selection else { return "清晰度" }
        return qualityDisplayTitle(selection.quality, in: playArgs)
    }

    public static func qualityDisplayTitle(
        in playArgs: [LiveQualityModel]?,
        cdnIndex: Int,
        qualityIndex: Int
    ) -> String {
        qualityDisplayTitle(
            in: playArgs,
            selection: selection(in: playArgs, cdnIndex: cdnIndex, qualityIndex: qualityIndex)
        )
    }

    public static func debugSelectionSummary(
        in playArgs: [LiveQualityModel]?,
        selection: RoomPlaybackSelection?
    ) -> String {
        guard let selection else { return "未设置" }

        let cdnName: String
        if let playArgs, playArgs.indices.contains(selection.cdnIndex) {
            cdnName = cdnDisplayName(for: playArgs[selection.cdnIndex])
        } else {
            cdnName = "未知线路"
        }

        let displayTitle = qualityDisplayTitle(in: playArgs, selection: selection)
        let streamType = streamTypeIdentifier(for: selection.quality)

        return "cdn[\(selection.cdnIndex)]=\(cdnName), quality[\(selection.qualityIndex)]=\(displayTitle)(qn=\(selection.quality.qn), type=\(streamType))"
    }

    public static func matchingSelection(
        in playArgs: [LiveQualityModel],
        preferredQuality: LiveQualityDetail,
        preferredCDN: LiveQualityModel? = nil
    ) -> RoomPlaybackSelection? {
        if let selection = firstSelection(in: playArgs, where: { $0.url == preferredQuality.url }) {
            return selection
        }

        let preferredTitle = preferredQuality.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredType = streamTypeIdentifier(for: preferredQuality)
        let preferredCDNName = preferredCDN.map(cdnDisplayName(for:))

        var bestSelection: RoomPlaybackSelection?
        var bestScore = Int.min

        for (cdnIndex, cdn) in playArgs.enumerated() {
            for (qualityIndex, quality) in cdn.qualitys.enumerated() {
                var score = 0

                if streamTypeIdentifier(for: quality) == preferredType {
                    score += 400
                }

                if preferredQuality.qn != 0, quality.qn == preferredQuality.qn {
                    score += 180
                }

                if !preferredTitle.isEmpty,
                   quality.title.trimmingCharacters(in: .whitespacesAndNewlines) == preferredTitle {
                    score += 120
                }

                if let preferredCDNName,
                   cdnDisplayName(for: cdn) == preferredCDNName {
                    score += 80
                }

                if score > bestScore {
                    bestScore = score
                    bestSelection = RoomPlaybackSelection(
                        cdnIndex: cdnIndex,
                        qualityIndex: qualityIndex,
                        quality: quality
                    )
                }
            }
        }

        if let selection = bestSelection, bestScore > 0 {
            return selection
        }

        if isHLSQuality(preferredQuality),
           let selection = firstSelection(in: playArgs, where: isHLSQuality) {
            return selection
        }

        if let selection = firstSelection(
            in: playArgs,
            where: { streamTypeIdentifier(for: $0) == preferredType }
        ) {
            return selection
        }

        return firstSelection(in: playArgs)
    }

    public static func resolvePlan(
        selectedQuality: LiveQualityDetail
    ) -> RoomPlaybackPlan {
        let hints = selectedQuality.playbackHints
        let format = streamFormat(for: selectedQuality)
        let requiresCustomSegmentLoader = hints?.requiresCustomSegmentLoader == true
        let isHLS = format == .hlsLive || format == .hlsVod
        let isLive = hints?.isLive ?? (format != .hlsVod)

        if requiresCustomSegmentLoader {
            return RoomPlaybackPlan(
                playerKinds: [.mePlayer],
                isHLS: isHLS,
                isLive: isLive,
                streamFormat: format
            )
        }

        if let preferredKinds = compatiblePreferredPlayerKinds(hints?.preferredEngines, format: format),
           !preferredKinds.isEmpty {
            return RoomPlaybackPlan(
                playerKinds: preferredKinds,
                isHLS: isHLS,
                isLive: isLive,
                streamFormat: format
            )
        }

        switch format {
        case .hlsLive:
            // 多档位 LL-HLS:FFmpeg 对每路 rendition 串行探测起播极慢(~16s),还可能拖过
            // 短时效 token 导致 403。AVPlayer 原生单档起播 + 吃 EXT-X-PART,秒级起播,
            // 故此类主路走 AVPlayer,KSMEPlayer 兜底。
            if isLowLatencyHLS(selectedQuality) {
                return RoomPlaybackPlan(
                    playerKinds: [.avPlayer, .mePlayer],
                    isHLS: true,
                    isLive: isLive,
                    streamFormat: format
                )
            }
            // 普通 HLS live 主路走 KSMEPlayer:统计面板 byteRate/networkSpeed 可读、
            // rw_timeout 可控,国外 CDN 卡第一帧场景下零吞吐 watchdog 才能生效。
            // AV 作为兜底:KSPlayerLayer.finish 在 ME 报错时会自动按 playerTypes
            // 顺序起下一个(KSPlayerLayer.swift:683),无需打开 isSecondOpen(那是"预开"开关)。
            return RoomPlaybackPlan(
                playerKinds: [.mePlayer, .avPlayer],
                isHLS: true,
                isLive: isLive,
                streamFormat: format
            )
        case .hlsVod:
            return RoomPlaybackPlan(
                playerKinds: [.mePlayer],
                isHLS: true,
                isLive: isLive,
                streamFormat: format
            )
        case .flv, .dash, .unknown:
            // FLV/DASH/未知 协议 AV 不能直接解,固定走 KSMEPlayer。
            return RoomPlaybackPlan(
                playerKinds: [.mePlayer],
                isHLS: false,
                isLive: isLive,
                streamFormat: format
            )
        }
    }

    private static func compatiblePreferredPlayerKinds(
        _ engines: [LivePlaybackEngine]?,
        format: LivePlaybackStreamFormat
    ) -> [RoomPlaybackPlayerKind]? {
        guard let engines, !engines.isEmpty else { return nil }

        let allowsAVPlayer = format == .hlsLive || format == .hlsVod
        var seen = Set<RoomPlaybackPlayerKind>()
        return engines.compactMap { engine in
            let kind: RoomPlaybackPlayerKind
            switch engine {
            case .mePlayer:
                kind = .mePlayer
            case .avPlayer:
                guard allowsAVPlayer else { return nil }
                kind = .avPlayer
            case .unknown:
                return nil
            }
            return seen.insert(kind).inserted ? kind : nil
        }
    }

    private static func hasDuplicateTitleWithDifferentStreamType(
        in playArgs: [LiveQualityModel]?,
        title: String,
        targetStreamTypeIdentifier: String
    ) -> Bool {
        guard let playArgs, !title.isEmpty else { return false }

        for cdn in playArgs {
            for quality in cdn.qualitys {
                let candidateTitle = quality.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard candidateTitle == title else { continue }
                if streamTypeIdentifier(for: quality) != targetStreamTypeIdentifier {
                    return true
                }
            }
        }

        return false
    }
}
