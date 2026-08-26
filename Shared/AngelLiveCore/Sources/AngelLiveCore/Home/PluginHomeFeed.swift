import Foundation

// MARK: - Plugin wire protocol

public struct PluginHomeFeedRequest: Encodable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let locale: String
    public let region: String?

    public init(
        schemaVersion: Int = Self.supportedSchemaVersion,
        locale: String,
        region: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.locale = locale
        self.region = region
    }

    public static var current: Self {
        let locale = Locale.current
        return Self(
            locale: locale.identifier.replacingOccurrences(of: "_", with: "-"),
            region: locale.region?.identifier
        )
    }

    var pluginPayload: [String: Any] {
        var payload: [String: Any] = [
            "schemaVersion": schemaVersion,
            "locale": locale
        ]
        if let region, !region.isEmpty {
            payload["region"] = region
        }
        return payload
    }
}

public struct PluginHomeFeedDTO: Decodable, Sendable {
    public let schemaVersion: Int
    public let revision: String?
    public let generatedAt: Date?
    public let ttlSeconds: Int?
    public let banners: [PluginHomeBannerDTO]
    public let sections: [PluginHomeSectionDTO]

    let rejectedBannerCount: Int
    let rejectedSectionCount: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case generatedAt
        case ttlSeconds
        case banners
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = container.decodeLossyStringIfPresent(forKey: .revision)
        ttlSeconds = container.decodeLossyIntIfPresent(forKey: .ttlSeconds)

        if let generatedAtValue = container.decodeLossyStringIfPresent(forKey: .generatedAt) {
            generatedAt = Self.parseISO8601Date(generatedAtValue)
        } else {
            generatedAt = nil
        }

        let decodedBanners: LossyDecodableArray<PluginHomeBannerDTO> = container.decodeLossyArray(forKey: .banners)
        banners = decodedBanners.elements
        rejectedBannerCount = decodedBanners.rejectedCount

        let decodedSections: LossyDecodableArray<PluginHomeSectionDTO> = container.decodeLossyArray(forKey: .sections)
        sections = decodedSections.elements
        rejectedSectionCount = decodedSections.rejectedCount
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        do {
            return try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
        } catch {
            do {
                return try Date.ISO8601FormatStyle().parse(value)
            } catch {
                return nil
            }
        }
    }
}

public struct PluginHomeBannerDTO: Decodable, Sendable {
    public let id: String
    public let imageURL: String
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let target: PluginHomeTargetDTO

    private enum CodingKeys: String, CodingKey {
        case id
        case imageURL
        case title
        case subtitle
        case badge
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyStringIfPresent(forKey: .id) ?? ""
        imageURL = container.decodeLossyStringIfPresent(forKey: .imageURL) ?? ""
        title = container.decodeLossyStringIfPresent(forKey: .title) ?? ""
        subtitle = container.decodeLossyStringIfPresent(forKey: .subtitle)
        badge = container.decodeLossyStringIfPresent(forKey: .badge)
        target = try container.decode(PluginHomeTargetDTO.self, forKey: .target)
    }
}

public enum PluginHomeTargetDTO: Decodable, Sendable {
    case room(PluginRoomDTO)
    case category(PluginHomeCategoryDTO)

    private enum CodingKeys: String, CodingKey {
        case type
        case room
        case category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)

        switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "room":
            self = .room(try container.decode(PluginRoomDTO.self, forKey: .room))
        case "category":
            self = .category(try container.decode(PluginHomeCategoryDTO.self, forKey: .category))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported home target type: \(rawType)"
            )
        }
    }
}

public struct PluginHomeCategoryDTO: Decodable, Equatable, Sendable {
    public let id: String
    public let parentId: String
    public let title: String
    public let icon: String
    public let biz: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case parentId
        case title
        case icon
        case biz
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyStringIfPresent(forKey: .id) ?? ""
        parentId = container.decodeLossyStringIfPresent(forKey: .parentId) ?? ""
        title = container.decodeLossyStringIfPresent(forKey: .title) ?? ""
        icon = container.decodeLossyStringIfPresent(forKey: .icon) ?? ""
        biz = container.decodeLossyStringIfPresent(forKey: .biz)
    }
}

public struct PluginHomeSectionDTO: Decodable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let subtitle: String?
    public let personalized: Bool
    public let items: [PluginHomeRoomItemDTO]
    public let seeAllTarget: PluginHomeTargetDTO?

    let rejectedItemCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case subtitle
        case personalized
        case items
        case seeAllTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyStringIfPresent(forKey: .id) ?? ""
        let decodedKind = container.decodeLossyStringIfPresent(forKey: .kind) ?? ""
        kind = decodedKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard kind == "rooms" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported home section kind: \(decodedKind)"
            )
        }

        title = container.decodeLossyStringIfPresent(forKey: .title) ?? ""
        subtitle = container.decodeLossyStringIfPresent(forKey: .subtitle)
        personalized = (try? container.decode(Bool.self, forKey: .personalized)) ?? false

        let decodedItems: LossyDecodableArray<PluginHomeRoomItemDTO> = container.decodeLossyArray(forKey: .items)
        items = decodedItems.elements
        rejectedItemCount = decodedItems.rejectedCount

        do {
            seeAllTarget = try container.decodeIfPresent(PluginHomeTargetDTO.self, forKey: .seeAllTarget)
        } catch {
            seeAllTarget = nil
        }
    }
}

public struct PluginHomeRoomItemDTO: Decodable, Sendable {
    public let id: String
    public let room: PluginRoomDTO
    public let reason: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case room
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyStringIfPresent(forKey: .id) ?? ""
        room = try container.decode(PluginRoomDTO.self, forKey: .room)
        reason = container.decodeLossyStringIfPresent(forKey: .reason)
    }
}

private struct LossyDecodableElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        do {
            value = try Element(from: decoder)
        } catch {
            value = nil
        }
    }
}

private struct LossyDecodableArray<Element: Decodable> {
    let elements: [Element]
    let rejectedCount: Int
}

private extension KeyedDecodingContainer {
    func decodeLossyArray<Element: Decodable>(forKey key: Key) -> LossyDecodableArray<Element> {
        do {
            let decoded = try decodeIfPresent([LossyDecodableElement<Element>].self, forKey: key) ?? []
            let elements = decoded.compactMap(\.value)
            return LossyDecodableArray(
                elements: elements,
                rejectedCount: decoded.count - elements.count
            )
        } catch {
            return LossyDecodableArray(elements: [], rejectedCount: 1)
        }
    }
}

// MARK: - Validated host model

public struct PluginHomeFeed: Codable, Sendable {
    public let pluginId: String
    public let pluginDisplayName: String
    public let schemaVersion: Int
    public let revision: String?
    public let generatedAt: Date?
    public let ttlSeconds: Int
    public let banners: [PluginHomeBanner]
    public let sections: [PluginHomeSection]
    public let diagnostics: PluginHomeFeedDiagnostics
}

public struct PluginHomeBanner: Identifiable, Codable, Sendable {
    public let id: String
    public let imageURL: URL?
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let target: PluginHomeTarget
}

public enum PluginHomeTarget: Codable, Sendable {
    case room(LiveModel)
    case category(LiveCategoryModel)

    private enum CodingKeys: String, CodingKey {
        case type
        case room
        case category
    }

    private enum Kind: String, Codable {
        case room
        case category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .room:
            self = .room(try container.decode(LiveModel.self, forKey: .room))
        case .category:
            self = .category(try container.decode(LiveCategoryModel.self, forKey: .category))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .room(let room):
            try container.encode(Kind.room, forKey: .type)
            try container.encode(room, forKey: .room)
        case .category(let category):
            try container.encode(Kind.category, forKey: .type)
            try container.encode(category, forKey: .category)
        }
    }
}

public struct PluginHomeSection: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let personalized: Bool
    public let items: [PluginHomeRoomItem]
    public let seeAllTarget: LiveCategoryModel?
}

public struct PluginHomeRoomItem: Identifiable, Codable, Sendable {
    public let id: String
    public let room: LiveModel
    public let reason: String?
}

public struct PluginHomeFeedDiagnostics: Codable, Equatable, Sendable {
    public let droppedBanners: Int
    public let droppedSections: Int
    public let droppedItems: Int
}

public enum PluginHomeFeedError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "不支持的首页数据版本：\(version)"
        }
    }
}

public struct PluginHomeFeedService: Sendable {
    typealias HomeFeedCall = @Sendable (String, PluginHomeFeedRequest) async throws -> PluginHomeFeedDTO

    private let callHomeFeed: HomeFeedCall

    public init(manager: LiveParsePluginManager = LiveParsePlugins.shared) {
        callHomeFeed = { pluginId, request in
            try await manager.callDecodable(
                pluginId: pluginId,
                function: "getHomeFeed",
                payload: request.pluginPayload
            )
        }
    }

    init(callHomeFeed: @escaping HomeFeedCall) {
        self.callHomeFeed = callHomeFeed
    }

    public func fetch(
        platform: LiveParseJSPlatform,
        request: PluginHomeFeedRequest = .current
    ) async throws -> PluginHomeFeed {
        try Task.checkCancellation()
        let response = try await callHomeFeed(platform.pluginId, request)
        try Task.checkCancellation()
        return try Self.validate(response, for: platform)
    }
}

private extension PluginHomeFeedService {
    enum Limits {
        static let defaultTTLSeconds = 15 * 60
        static let minimumTTLSeconds = 60
        static let maximumTTLSeconds = 24 * 60 * 60
        static let sectionsPerPlugin = 8
        static let roomsPerSection = 20
        static let idLength = 128
        static let titleLength = 120
        static let subtitleLength = 240
        static let badgeLength = 32
        static let reasonLength = 200
        static let revisionLength = 256
    }

    static func validate(
        _ response: PluginHomeFeedDTO,
        for platform: LiveParseJSPlatform
    ) throws -> PluginHomeFeed {
        guard response.schemaVersion == PluginHomeFeedRequest.supportedSchemaVersion else {
            throw PluginHomeFeedError.unsupportedSchemaVersion(response.schemaVersion)
        }

        var droppedBanners = response.rejectedBannerCount
        var bannerIDs = Set<String>()
        var banners: [PluginHomeBanner] = []

        for banner in response.banners {
            let rawID = normalized(banner.id, maximumLength: Limits.idLength)
            let namespacedID = namespace(pluginId: platform.pluginId, kind: "banner", id: rawID)
            guard !rawID.isEmpty,
                  bannerIDs.insert(namespacedID).inserted,
                  let target = validatedTarget(banner.target, liveType: platform.liveType) else {
                droppedBanners += 1
                continue
            }

            banners.append(
                PluginHomeBanner(
                    id: namespacedID,
                    imageURL: secureURL(banner.imageURL),
                    title: normalized(banner.title, maximumLength: Limits.titleLength),
                    subtitle: normalizedOptional(banner.subtitle, maximumLength: Limits.subtitleLength),
                    badge: normalizedOptional(banner.badge, maximumLength: Limits.badgeLength),
                    target: target
                )
            )
        }

        var droppedSections = response.rejectedSectionCount
        var droppedItems = response.sections.reduce(0) { $0 + $1.rejectedItemCount }
        var sectionIDs = Set<String>()
        var sections: [PluginHomeSection] = []

        for section in response.sections {
            guard sections.count < Limits.sectionsPerPlugin else {
                droppedSections += 1
                droppedItems += section.items.count
                continue
            }

            let rawSectionID = normalized(section.id, maximumLength: Limits.idLength)
            let namespacedSectionID = namespace(pluginId: platform.pluginId, kind: "section", id: rawSectionID)
            let title = normalized(section.title, maximumLength: Limits.titleLength)
            guard !rawSectionID.isEmpty,
                  !title.isEmpty,
                  sectionIDs.insert(namespacedSectionID).inserted else {
                droppedSections += 1
                droppedItems += section.items.count
                continue
            }

            var itemIDs = Set<String>()
            var items: [PluginHomeRoomItem] = []
            for item in section.items {
                guard items.count < Limits.roomsPerSection else {
                    droppedItems += 1
                    continue
                }

                let rawItemID = normalized(item.id, maximumLength: Limits.idLength)
                let namespacedItemID = "\(platform.pluginId):section:\(rawSectionID):item:\(rawItemID)"
                guard !rawItemID.isEmpty,
                      itemIDs.insert(namespacedItemID).inserted,
                      let room = validatedRoom(item.room, liveType: platform.liveType) else {
                    droppedItems += 1
                    continue
                }

                items.append(
                    PluginHomeRoomItem(
                        id: namespacedItemID,
                        room: room,
                        reason: normalizedOptional(item.reason, maximumLength: Limits.reasonLength)
                    )
                )
            }

            let seeAllTarget: LiveCategoryModel?
            if case .category(let category)? = section.seeAllTarget {
                seeAllTarget = validatedCategory(category)
            } else {
                seeAllTarget = nil
            }

            sections.append(
                PluginHomeSection(
                    id: namespacedSectionID,
                    title: title,
                    subtitle: normalizedOptional(section.subtitle, maximumLength: Limits.subtitleLength),
                    personalized: section.personalized,
                    items: items,
                    seeAllTarget: seeAllTarget
                )
            )
        }

        let requestedTTL = response.ttlSeconds ?? Limits.defaultTTLSeconds
        let ttlSeconds = min(max(requestedTTL, Limits.minimumTTLSeconds), Limits.maximumTTLSeconds)

        return PluginHomeFeed(
            pluginId: platform.pluginId,
            pluginDisplayName: platform.displayName,
            schemaVersion: response.schemaVersion,
            revision: normalizedOptional(response.revision, maximumLength: Limits.revisionLength),
            generatedAt: response.generatedAt,
            ttlSeconds: ttlSeconds,
            banners: banners,
            sections: sections,
            diagnostics: PluginHomeFeedDiagnostics(
                droppedBanners: droppedBanners,
                droppedSections: droppedSections,
                droppedItems: droppedItems
            )
        )
    }

    static func validatedTarget(_ target: PluginHomeTargetDTO, liveType: LiveType) -> PluginHomeTarget? {
        switch target {
        case .room(let room):
            guard let room = validatedRoom(room, liveType: liveType) else { return nil }
            return .room(room)
        case .category(let category):
            guard let category = validatedCategory(category) else { return nil }
            return .category(category)
        }
    }

    static func validatedRoom(_ room: PluginRoomDTO, liveType: LiveType) -> LiveModel? {
        let roomID = normalized(room.roomId, maximumLength: Limits.idLength)
        guard !roomID.isEmpty else { return nil }

        return LiveModel(
            userName: normalized(room.userName, maximumLength: Limits.titleLength),
            roomTitle: normalized(room.roomTitle, maximumLength: Limits.titleLength),
            roomCover: secureURL(room.roomCover)?.absoluteString ?? "",
            userHeadImg: secureURL(room.userHeadImg)?.absoluteString ?? "",
            liveType: liveType,
            liveState: normalizedOptional(room.liveState, maximumLength: Limits.badgeLength),
            userId: normalized(room.userId, maximumLength: Limits.idLength),
            roomId: roomID,
            liveWatchedCount: normalizedOptional(room.liveWatchedCount, maximumLength: Limits.badgeLength)
        )
    }

    static func validatedCategory(_ category: PluginHomeCategoryDTO) -> LiveCategoryModel? {
        let id = normalized(category.id, maximumLength: Limits.idLength)
        guard !id.isEmpty else { return nil }

        return LiveCategoryModel(
            id: id,
            parentId: normalized(category.parentId, maximumLength: Limits.idLength),
            title: normalized(category.title, maximumLength: Limits.titleLength),
            icon: secureURL(category.icon)?.absoluteString ?? "",
            biz: normalizedOptional(category.biz, maximumLength: Limits.revisionLength)
        )
    }

    static func normalized(_ value: String, maximumLength: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    static func normalizedOptional(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let result = normalized(value, maximumLength: maximumLength)
        return result.isEmpty ? nil : result
    }

    static func secureURL(_ value: String) -> URL? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedValue),
              url.scheme?.lowercased() == "https",
              url.host() != nil else {
            return nil
        }
        return url
    }

    static func namespace(pluginId: String, kind: String, id: String) -> String {
        "\(pluginId):\(kind):\(id)"
    }
}
