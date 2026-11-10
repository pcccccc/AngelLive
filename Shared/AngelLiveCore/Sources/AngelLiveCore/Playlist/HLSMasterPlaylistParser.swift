//
//  HLSMasterPlaylistParser.swift
//  AngelLiveCore
//
//  把频道地址返回的 HLS master playlist 展开为可选清晰度。
//

import Foundation

public struct HLSVariant: Equatable, Sendable {
    public let url: String
    public let title: String
    public let bandwidth: Int?
}

public enum HLSMasterPlaylistParser {
    /// 返回 nil 表示不是 master playlist（媒体列表或其他内容）。
    public static func variants(in text: String, baseURL: URL) -> [HLSVariant]? {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U"),
              text.contains("#EXT-X-STREAM-INF") else {
            return nil
        }
        // variant 依赖独立音频 rendition 时，单独播放某一档会没有声音，保留 master 整体播放。
        if hasSeparateAudioRendition(text) {
            return nil
        }

        var result: [HLSVariant] = []
        var pendingAttributes: [String: String]?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pendingAttributes = parseAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
                continue
            }
            if line.hasPrefix("#") { continue }
            guard let attributes = pendingAttributes else { continue }
            pendingAttributes = nil
            // 相对 URI 按 master 的最终地址补全。
            guard let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL,
                  let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                continue
            }
            let bandwidth = attributes["BANDWIDTH"].flatMap(Int.init)
            result.append(HLSVariant(
                url: resolved.absoluteString,
                title: title(for: attributes, bandwidth: bandwidth, index: result.count),
                bandwidth: bandwidth
            ))
        }

        guard !result.isEmpty else { return nil }
        // 同 URL 去重，高码率在前。
        var seen = Set<String>()
        let ordered = result
            .filter { seen.insert($0.url).inserted }
            .enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.bandwidth, rhs.element.bandwidth) {
                case let (l?, r?) where l != r: return l > r
                default: return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
        return disambiguated(ordered)
    }

    static func hasSeparateAudioRendition(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXT-X-MEDIA:") else { return false }
            let attributes = parseAttributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
            return attributes["TYPE"]?.uppercased() == "AUDIO" && !(attributes["URI"] ?? "").isEmpty
        }
    }

    /// 同名档位（如多个 1080p 仅码率不同）追加码率区分。
    private static func disambiguated(_ variants: [HLSVariant]) -> [HLSVariant] {
        var counts: [String: Int] = [:]
        for variant in variants { counts[variant.title, default: 0] += 1 }
        return variants.map { variant in
            guard counts[variant.title, default: 0] > 1, let bandwidth = variant.bandwidth, bandwidth > 0 else {
                return variant
            }
            return HLSVariant(url: variant.url, title: "\(variant.title) · \(bandwidth / 1000)kbps", bandwidth: bandwidth)
        }
    }

    private static func title(for attributes: [String: String], bandwidth: Int?, index: Int) -> String {
        if let name = attributes["NAME"], !name.isEmpty {
            return name
        }
        if let resolution = attributes["RESOLUTION"],
           let height = resolution.lowercased().split(separator: "x").last.flatMap({ Int($0) }) {
            return "\(height)p"
        }
        if let bandwidth, bandwidth > 0 {
            return "\(bandwidth / 1000)kbps"
        }
        return "清晰度 \(index + 1)"
    }

    /// `KEY=value,KEY2="quoted, value"`
    static func parseAttributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingValue = false
        var inQuotes = false

        func commit() {
            let trimmedKey = key.trimmingCharacters(in: .whitespaces).uppercased()
            if !trimmedKey.isEmpty {
                result[trimmedKey] = value.trimmingCharacters(in: .whitespaces)
            }
            key = ""
            value = ""
            readingValue = false
        }

        for character in text {
            if readingValue {
                if character == "\"" {
                    inQuotes.toggle()
                } else if character == ",", !inQuotes {
                    commit()
                } else {
                    value.append(character)
                }
            } else if character == "=" {
                readingValue = true
            } else {
                key.append(character)
            }
        }
        commit()
        return result
    }
}
