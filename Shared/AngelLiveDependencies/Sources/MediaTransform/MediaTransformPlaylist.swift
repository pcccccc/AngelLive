import Foundation

/// URI roles are established by HLS syntax, never by a URL's filename extension.
struct MediaTransformPlaylist {
    enum Role: Equatable { case playlist, segment }
    let references: [URL: Role]

    init(data: Data, baseURL: URL) throws {
        guard let text = String(data: data, encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first == "#EXTM3U" else {
            throw MediaTransformIOError.invalidPlaylist
        }
        var references: [URL: Role] = [:]
        var nextRole: Role?
        func register(_ uri: String, role: Role) throws {
            guard let url = URL(string: uri, relativeTo: baseURL)?.absoluteURL else {
                throw MediaTransformIOError.invalidPlaylist
            }
            if let existing = references[url], existing != role {
                throw MediaTransformIOError.ambiguousResource
            }
            references[url] = role
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let tag = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? line
            switch tag {
            case "#EXT-X-BYTERANGE", "#EXT-X-MAP", "#EXT-X-PART", "#EXT-X-PART-INF", "#EXT-X-PRELOAD-HINT", "#EXT-X-SKIP", "#EXT-X-I-FRAMES-ONLY", "#EXT-X-DEFINE":
                throw MediaTransformIOError.unsupportedPlaylistFeature(tag)
            case "#EXT-X-KEY", "#EXT-X-SESSION-KEY":
                let attributes = try Self.attributes(line)
                guard attributes["METHOD"] == "NONE" else {
                    throw MediaTransformIOError.unsupportedPlaylistFeature(tag)
                }
            case "#EXT-X-STREAM-INF":
                nextRole = .playlist
            case "#EXTINF":
                nextRole = .segment
            case "#EXT-X-MEDIA", "#EXT-X-I-FRAME-STREAM-INF":
                if let uri = try Self.attributes(line)["URI"] { try register(uri, role: .playlist) }
            default:
                if !line.hasPrefix("#") {
                    guard let role = nextRole else { throw MediaTransformIOError.invalidPlaylist }
                    try register(line, role: role)
                    nextRole = nil
                }
            }
        }
        guard nextRole == nil else { throw MediaTransformIOError.invalidPlaylist }
        self.references = references
    }

    private static func attributes(_ line: String) throws -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        var result: [String: String] = [:]
        var field = ""
        var quoted = false
        func appendField() {
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                result[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
            field = ""
        }
        for character in line[line.index(after: colon)...] {
            if character == "\"" { quoted.toggle() }
            if character == ",", !quoted { appendField() } else { field.append(character) }
        }
        guard !quoted else { throw MediaTransformIOError.invalidPlaylist }
        appendField()
        return result
    }
}

enum MediaTransformIOError: Error, LocalizedError {
    case allocation, invalidPlaylist, ambiguousResource, unknownResource, playlistTooLarge, unsupportedMediaContainer
    case unsupportedPlaylistFeature(String)
    case ffmpeg(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .allocation: "Media input allocation failed."
        case .invalidPlaylist: "Media transform requires a valid HLS playlist."
        case .ambiguousResource: "An HLS resource has conflicting roles."
        case .unknownResource: "An HLS resource was not declared by its playlist."
        case .playlistTooLarge: "The HLS playlist exceeds the supported size."
        case .unsupportedMediaContainer: "Media transform currently supports independent MPEG-TS segments only."
        case let .unsupportedPlaylistFeature(tag): "Media transform does not support \(tag)."
        case let .ffmpeg(operation, code): "Media input \(operation) failed (\(code))."
        }
    }
}
