//
//  TopShelfSnapshot.swift
//  AngelLiveCore
//
//  A small, credential-free Top Shelf presentation snapshot shared through the
//  tvOS App Group cache. The extension can render it while offline.
//

import Foundation

public struct TopShelfSnapshot: Codable, Equatable, Sendable {
    public let items: [Item]

    public struct Item: Codable, Equatable, Sendable {
        public let identifier: String
        public let title: String
        public let imageURL: URL?
        public let actionURL: URL
    }

    public init(favorites: [LiveModel]) {
        var seenIdentifiers = Set<String>()
        items = favorites
            .filter { $0.liveState == LiveState.live.rawValue }
            .compactMap { room in
                let identifier = "\(Self.encodedPathSegment(room.liveType.rawValue))/\(Self.encodedPathSegment(room.roomId))"
                guard seenIdentifiers.insert(identifier).inserted else { return nil }

                return Item(
                    identifier: identifier,
                    title: "\(room.roomTitle) - \(room.userName)",
                    imageURL: Self.validImageURL(room.roomCover)
                        ?? Self.validImageURL(room.userHeadImg),
                    actionURL: Self.actionURL(for: room)
                )
            }
    }
}

public struct TopShelfSnapshotStore: Sendable {
    public static let appGroupIdentifier = "group.dev.idog.angellivetvos"

    private let containerURL: URL

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public func load() throws -> TopShelfSnapshot? {
        let fileURL = snapshotURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(TopShelfSnapshot.self, from: Data(contentsOf: fileURL))
    }

    @discardableResult
    public func save(_ snapshot: TopShelfSnapshot) throws -> Bool {
        let data = try encoder.encode(snapshot)
        let fileManager = FileManager.default
        let fileURL = snapshotURL

        if fileManager.fileExists(atPath: fileURL.path),
           try Data(contentsOf: fileURL, options: [.mappedIfSafe]) == data {
            return false
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
        return true
    }
}

private extension TopShelfSnapshot {
    static func validImageURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    static func actionURL(for room: LiveModel) -> URL {
        var components = URLComponents()
        components.scheme = "simplelive"
        components.host = "room"
        components.percentEncodedPath = "/\(encodedPathSegment(room.liveType.rawValue))/\(encodedPathSegment(room.roomId))"
        if !room.userId.isEmpty {
            components.queryItems = [URLQueryItem(name: "userId", value: room.userId)]
        }
        return components.url!
    }

    static func encodedPathSegment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

private extension TopShelfSnapshotStore {
    var snapshotURL: URL {
        containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("TopShelf", isDirectory: true)
            .appendingPathComponent("favorites-v1.json", isDirectory: false)
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
