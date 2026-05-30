import Foundation

public enum RoomPlaybackPlayerKind: Sendable {
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
    public let overrideURL: URL?
    public let overrideTitle: String?
    public let resolvedSelection: RoomPlaybackSelection?

    public init(
        playerKinds: [RoomPlaybackPlayerKind],
        isHLS: Bool,
        overrideURL: URL? = nil,
        overrideTitle: String? = nil,
        resolvedSelection: RoomPlaybackSelection? = nil
    ) {
        self.playerKinds = playerKinds
        self.isHLS = isHLS
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

public enum RoomPlaybackResolver {
    public static func isHLSQuality(_ quality: LiveQualityDetail) -> Bool {
        quality.liveCodeType == .hls || quality.url.lowercased().contains(".m3u8")
    }

    /// 低延迟 HLS(LL-HLS)特征判定:URL 含 `llhls.m3u8` 标记。
    /// 这类 master 通常暴露多路 video/audio rendition,FFmpeg(KSMEPlayer)会对每路串行跑
    /// find_stream_info,起播 ~16s 且可能拖过短时效 token 导致 403;故应优先走原生 AVPlayer。
    /// 用 URL 特征判定,不绑任何平台名。
    public static func isLowLatencyHLS(_ quality: LiveQualityDetail) -> Bool {
        isHLSQuality(quality) && quality.url.lowercased().contains("llhls.m3u8")
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

        if requiresCustomSegmentLoader {
            return RoomPlaybackPlan(
                playerKinds: [.mePlayer],
                isHLS: format == .hlsLive
            )
        }

        switch format {
        case .hlsLive:
            // 多档位 LL-HLS:FFmpeg 对每路 rendition 串行探测起播极慢(~16s),还可能拖过
            // 短时效 token 导致 403。AVPlayer 原生单档起播 + 吃 EXT-X-PART,秒级起播,
            // 故此类主路走 AVPlayer,KSMEPlayer 兜底。
            if isLowLatencyHLS(selectedQuality) {
                return RoomPlaybackPlan(playerKinds: [.avPlayer, .mePlayer], isHLS: true)
            }
            // 普通 HLS live 主路走 KSMEPlayer:统计面板 byteRate/networkSpeed 可读、
            // rw_timeout 可控,国外 CDN 卡第一帧场景下零吞吐 watchdog 才能生效。
            // AV 作为兜底:KSPlayerLayer.finish 在 ME 报错时会自动按 playerTypes
            // 顺序起下一个(KSPlayerLayer.swift:683),无需打开 isSecondOpen(那是"预开"开关)。
            return RoomPlaybackPlan(playerKinds: [.mePlayer, .avPlayer], isHLS: true)
        case .hlsVod:
            return RoomPlaybackPlan(playerKinds: [.mePlayer], isHLS: false)
        case .flv, .dash, .unknown:
            // FLV/DASH/未知 协议 AV 不能直接解,固定走 KSMEPlayer。
            return RoomPlaybackPlan(playerKinds: [.mePlayer], isHLS: false)
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
