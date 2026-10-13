import Foundation

extension RoomPlaybackResolver {
    /// 首次进房使用；续播和恢复继续使用 automaticSelection 保持当前档位。
    public static func initialSelection(
        in playArgs: [LiveQualityModel],
        preferredCdnIndex: Int,
        preference: DefaultPlaybackQuality
    ) -> (cdnIndex: Int, qualityIndex: Int) {
        let fallback = automaticSelection(
            in: playArgs,
            preferredCdnIndex: preferredCdnIndex,
            preferredQualityIndex: 0
        )
        guard preference != .highest, !playArgs.isEmpty else { return fallback }

        let preferred = min(max(0, preferredCdnIndex), playArgs.count - 1)
        let cdnIndices = [preferred] + playArgs.indices.filter { $0 != preferred }
        for cdnIndex in cdnIndices {
            let qualities = playArgs[cdnIndex].qualitys
            var seenTitles = Set<String>()
            var candidates = qualities.indices.filter { index in
                let quality = qualities[index]
                guard !isLocked(quality), isInitialQualityAvailable(quality) else { return false }
                let title = normalizedQualityTitle(quality.title)
                // 无名称的条目没有足够信息判断是否属于同档，不能因 qn=0 合并。
                return title.isEmpty || seenTitles.insert(title).inserted
            }
            guard !candidates.isEmpty else { continue }

            let resolutions = candidates.map { resolutionRank(qualities[$0].title) }
            let levels = candidates.map { namedQualityRank(qualities[$0].title) }
            let ranks: [Int]?
            if resolutions.allSatisfy({ $0 != nil }) {
                ranks = resolutions.compactMap { $0 }
            } else if levels.allSatisfy({ $0 != nil }) {
                ranks = levels.compactMap { $0 }
            } else {
                ranks = nil
            }
            // 整条线路有同类信号才排序；未知或混合信号保持插件顺序。
            if let ranks {
                candidates = zip(candidates, ranks).sorted {
                    $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1
                }.map { $0.0 }
            }
            let position = preference == .balanced ? candidates.count / 2 : candidates.count - 1
            return (cdnIndex, candidates[position])
        }
        return fallback
    }

    private static func isInitialQualityAvailable(_ quality: LiveQualityDetail) -> Bool {
        if requiresRefreshOnSelect(quality) { return true }
        guard let url = playableURL(for: quality), let scheme = url.scheme, !scheme.isEmpty else { return false }
        if scheme.lowercased() == "http" || scheme.lowercased() == "https" {
            return url.host?.isEmpty == false
        }
        return true
    }

    private static func normalizedQualityTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "(?<![a-z0-9])(hls|flv|dash)(?![a-z0-9])", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(\\s*\\)|\\[\\s*\\]|（\\s*）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_/|")))
    }

    private static func resolutionRank(_ title: String) -> Int? {
        let normalized = title.lowercased()
        for (label, rank) in [("360p", 360), ("480p", 480), ("540p", 540), ("720p", 720), ("1080p", 1080), ("1440p", 1440), ("2160p", 2160), ("2k", 1440), ("4k", 2160)] {
            if normalized.range(of: "(?<![a-z0-9])\(label)(?![a-z0-9])", options: .regularExpression) != nil {
                return rank
            }
        }
        return nil
    }

    private static func namedQualityRank(_ title: String) -> Int? {
        for (label, rank) in [("原画", 5), ("蓝光", 4), ("超清", 3), ("高清", 2), ("标清", 1), ("流畅", 0)] {
            if title.contains(label) { return rank }
        }
        return nil
    }
}
