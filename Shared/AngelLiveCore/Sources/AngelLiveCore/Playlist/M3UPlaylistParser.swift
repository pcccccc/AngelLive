//
//  M3UPlaylistParser.swift
//  AngelLiveCore
//
//  宿主原生的 m3u 播放列表解析（IPTV）。纯函数、无 I/O，便于 fixture 测试。
//

import Foundation

public struct M3UPlaylistLine: Equatable, Sendable {
    public let url: String
    public let userAgent: String?
    public let headers: [String: String]

    public init(url: String, userAgent: String? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.userAgent = userAgent
        self.headers = headers
    }
}

public struct M3UPlaylistChannel: Equatable, Sendable {
    public let group: String
    public let name: String
    public let logo: String?
    /// 同一 (分组, 频道名) 的多条地址按出现顺序合并为多条线路。
    public internal(set) var lines: [M3UPlaylistLine]
}

public struct M3UPlaylist: Equatable, Sendable {
    public let title: String?
    public let channels: [M3UPlaylistChannel]

    /// 分组按首次出现顺序排列。
    public var groups: [String] {
        var seen = Set<String>()
        return channels.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }
}

public enum M3UPlaylistError: Error, Equatable, LocalizedError {
    case notPlaylist
    case unsupportedEncoding
    case noChannels
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .notPlaylist: "内容不是 m3u 播放列表。"
        case .unsupportedEncoding: "无法识别播放列表的文本编码。"
        case .noChannels: "播放列表中没有识别到频道。"
        case .tooLarge: "播放列表过大，无法加载。"
        }
    }
}

public enum M3UPlaylistParser {
    public static let defaultGroupName = "未分组"
    /// 防止把非播放列表的大文件读入内存；按真实列表量级留足余量。
    public static let maxByteCount = 20 * 1024 * 1024
    public static let maxChannelCount = 50_000

    private static let playableSchemes: Set<String> = ["http", "https"]

    /// 去掉 BOM 与前导空白后是否以 `#EXTM3U` 开头。只看内容，不看扩展名。
    public static func looksLikePlaylist(_ data: Data) -> Bool {
        let prefix = data.prefix(64)
        var bytes = Array(prefix)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        while let first = bytes.first, first == 0x20 || first == 0x09 || first == 0x0A || first == 0x0D {
            bytes.removeFirst()
        }
        return bytes.starts(with: Array("#EXTM3U".utf8))
    }

    /// UTF-8 严格解码，失败回退 GB18030；仍失败不做静默乱码解析。
    public static func decodeText(_ data: Data) throws -> String {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) { payload = payload.dropFirst(3) }
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        if let text = String(data: payload, encoding: gb18030) {
            return text
        }
        throw M3UPlaylistError.unsupportedEncoding
    }

    public static func parse(_ data: Data) throws -> M3UPlaylist {
        guard data.count <= maxByteCount else { throw M3UPlaylistError.tooLarge }
        guard looksLikePlaylist(data) else { throw M3UPlaylistError.notPlaylist }
        return try parse(text: decodeText(data))
    }

    public static func parse(text: String) throws -> M3UPlaylist {
        var title: String?
        var channels: [M3UPlaylistChannel] = []
        var indexByKey: [String: Int] = [:]

        var pending: (attributes: [String: String], name: String)?
        var pendingGroup: String?
        var pendingUserAgent: String?
        var pendingHeaders: [String: String] = [:]
        var sawHeader = false

        func resetPending() {
            pending = nil
            pendingGroup = nil
            pendingUserAgent = nil
            pendingHeaders = [:]
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if !sawHeader {
                guard line.hasPrefix("#EXTM3U") else { throw M3UPlaylistError.notPlaylist }
                sawHeader = true
                continue
            }

            if line.hasPrefix("#EXTINF:") {
                pending = parseExtInf(String(line.dropFirst("#EXTINF:".count)))
                continue
            }
            if line.hasPrefix("#PLAYLIST:") {
                let value = line.dropFirst("#PLAYLIST:".count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, title == nil { title = value }
                continue
            }
            if line.hasPrefix("#EXTGRP:") {
                let value = line.dropFirst("#EXTGRP:".count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { pendingGroup = value }
                continue
            }
            if line.hasPrefix("#EXTVLCOPT:") {
                applyVLCOption(String(line.dropFirst("#EXTVLCOPT:".count)), userAgent: &pendingUserAgent, headers: &pendingHeaders)
                continue
            }
            if line.hasPrefix("#KODIPROP:") {
                applyKodiProperty(String(line.dropFirst("#KODIPROP:".count)), userAgent: &pendingUserAgent, headers: &pendingHeaders)
                continue
            }
            if line.hasPrefix("#") {
                // 非标准扩展指令一律忽略。
                continue
            }

            // URL 行：只接受带 EXTINF 的条目，裸地址没有可展示的频道名。
            guard let info = pending else {
                resetPending()
                continue
            }
            guard let scheme = URL(string: line)?.scheme?.lowercased(), playableSchemes.contains(scheme) else {
                resetPending()
                continue
            }

            let name = info.name
            guard !name.isEmpty else {
                resetPending()
                continue
            }
            let group = nonEmpty(info.attributes["group-title"]) ?? pendingGroup ?? defaultGroupName
            let entry = M3UPlaylistLine(url: line, userAgent: pendingUserAgent, headers: pendingHeaders)
            let key = "\(group)\u{1F}\(name)"

            if let index = indexByKey[key] {
                if !channels[index].lines.contains(where: { $0.url == entry.url }) {
                    channels[index].lines.append(entry)
                }
            } else {
                guard channels.count < maxChannelCount else { throw M3UPlaylistError.tooLarge }
                indexByKey[key] = channels.count
                channels.append(M3UPlaylistChannel(
                    group: group,
                    name: name,
                    logo: nonEmpty(info.attributes["tvg-logo"]),
                    lines: [entry]
                ))
            }
            resetPending()
        }

        guard sawHeader else { throw M3UPlaylistError.notPlaylist }
        guard !channels.isEmpty else { throw M3UPlaylistError.noChannels }
        return M3UPlaylist(title: title, channels: channels)
    }

    // MARK: - EXTINF

    /// `-1 key="value" key2="value, with comma",频道名`：频道名从属性区之后第一个引号外逗号开始，
    /// 名称本身可含 `#`、逗号与全角标点。
    static func parseExtInf(_ body: String) -> (attributes: [String: String], name: String) {
        var inQuotes = false
        var splitIndex: String.Index?
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                splitIndex = index
                break
            }
            index = body.index(after: index)
        }

        let attributePart: Substring
        let name: String
        if let splitIndex {
            attributePart = body[..<splitIndex]
            name = body[body.index(after: splitIndex)...].trimmingCharacters(in: .whitespaces)
        } else {
            attributePart = body[...]
            name = ""
        }

        var attributes: [String: String] = [:]
        var scanner = attributePart[...]
        while let equals = scanner.firstIndex(of: "=") {
            let keyStart = scanner[..<equals].lastIndex(where: { $0 == " " || $0 == "\t" })
                .map { scanner.index(after: $0) } ?? scanner.startIndex
            let key = scanner[keyStart..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let afterEquals = scanner.index(after: equals)
            guard afterEquals < scanner.endIndex, scanner[afterEquals] == "\"" else {
                scanner = scanner[afterEquals...]
                continue
            }
            let valueStart = scanner.index(after: afterEquals)
            guard let valueEnd = scanner[valueStart...].firstIndex(of: "\"") else { break }
            if !key.isEmpty {
                attributes[key] = String(scanner[valueStart..<valueEnd]).trimmingCharacters(in: .whitespaces)
            }
            scanner = scanner[scanner.index(after: valueEnd)...]
        }

        let fallbackName = nonEmpty(attributes["tvg-name"]) ?? ""
        return (attributes, name.isEmpty ? fallbackName : name)
    }

    // MARK: - 请求头类扩展

    private static func applyVLCOption(_ option: String, userAgent: inout String?, headers: inout [String: String]) {
        guard let equals = option.firstIndex(of: "=") else { return }
        let key = option[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        let value = option[option.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        switch key {
        case "http-user-agent":
            userAgent = value
        case "http-referrer", "http-referer":
            headers["Referer"] = value
        case "http-origin":
            headers["Origin"] = value
        default:
            break
        }
    }

    /// `inputstream.adaptive.stream_headers=User-Agent=a&Referer=b`（值为 URL 编码）。
    private static func applyKodiProperty(_ property: String, userAgent: inout String?, headers: inout [String: String]) {
        guard let equals = property.firstIndex(of: "=") else { return }
        let key = property[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        guard key.hasSuffix("stream_headers") || key.hasSuffix("manifest_headers") else { return }
        let value = String(property[property.index(after: equals)...])
        for pair in value.split(separator: "&") {
            guard let pairEquals = pair.firstIndex(of: "=") else { continue }
            let rawName = String(pair[..<pairEquals])
            let rawValue = String(pair[pair.index(after: pairEquals)...])
            let name = (rawName.removingPercentEncoding ?? rawName).trimmingCharacters(in: .whitespaces)
            let headerValue = (rawValue.removingPercentEncoding ?? rawValue).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !headerValue.isEmpty else { continue }
            if name.lowercased() == "user-agent" {
                userAgent = headerValue
            } else {
                headers[name] = headerValue
            }
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}
