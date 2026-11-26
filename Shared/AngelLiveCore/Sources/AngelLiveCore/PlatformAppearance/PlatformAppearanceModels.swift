import Foundation

public enum PlatformDeviceIdiom: String, Codable, Sendable, CaseIterable, Hashable {
    case phone, pad, mac, tv

    public var columnRange: ClosedRange<Int> {
        switch self {
        case .phone: 1...3
        case .pad: 2...5
        case .mac: 2...6
        case .tv: 3...5
        }
    }

    public var cardHeightRange: ClosedRange<Double> {
        switch self {
        case .phone: 84...180
        case .pad: 96...220
        case .mac: 100...240
        case .tv: 180...300
        }
    }

    public var cornerRadiusRange: ClosedRange<Double> {
        switch self {
        case .phone, .pad: 12...28
        case .mac: 10...24
        case .tv: 16...32
        }
    }

    public var defaultMetrics: PlatformIdiomCustomMetrics {
        switch self {
        case .phone: .init(columns: 2, cardHeight: 118, cornerRadius: 20)
        case .pad: .init(columns: 3, cardHeight: 144, cornerRadius: 20)
        case .mac: .init(columns: 3, cardHeight: 136, cornerRadius: 14)
        case .tv: .init(columns: 4, cardHeight: 230, cornerRadius: 18)
        }
    }
}

public enum PlatformGridDensity: String, Codable, Sendable, CaseIterable, Hashable {
    case comfortable, standard, compact

    public func columns(for idiom: PlatformDeviceIdiom, availableWidth: Double, spacing: Double) -> Int {
        let offset: Int = switch self {
        case .comfortable: 0
        case .standard: 1
        case .compact: 2
        }
        switch idiom {
        case .phone: return 1 + offset
        case .pad: return 2 + offset
        case .tv: return 3 + offset
        case .mac:
            let minimumWidth: Double = switch self {
            case .comfortable: 280
            case .standard: 220
            case .compact: 176
            }
            let lowerBound = 2 + offset
            let upperBound = lowerBound + 1
            let width = max(0, availableWidth.isFinite ? availableWidth : 0)
            let gap = max(0, spacing.isFinite ? spacing : 0)
            let fitting = min(Double(upperBound), (width + gap) / (minimumWidth + gap))
            // A narrow window can show fewer columns so individual cards retain a usable width.
            return max(1, Int(fitting))
        }
    }
}

public enum PlatformCardAspectPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case wide, classic, compact, square

    public var heightToWidth: Double {
        switch self {
        case .wide: 9.0 / 16
        case .classic: 3.0 / 5
        case .compact: 0.5
        case .square: 1
        }
    }
}

public enum PlatformBackgroundPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case graphite, ocean, dusk, forest, ember

    public var colors: (PlatformRGBAColor, PlatformRGBAColor) {
        switch self {
        case .graphite: (.init(rgb: 0x334155), .init(rgb: 0x172033))
        case .ocean: (.init(rgb: 0x28546B), .init(rgb: 0x102937))
        case .dusk: (.init(rgb: 0x4B4676), .init(rgb: 0x211D3A))
        case .forest: (.init(rgb: 0x365B51), .init(rgb: 0x162D27))
        case .ember: (.init(rgb: 0x784B45), .init(rgb: 0x3C2430))
        }
    }
}

public enum PlatformBackgroundStyle: Codable, Equatable, Sendable, Hashable {
    case defaultAsset
    case dominantIconAura
    case systemSurface
    case preset(PlatformBackgroundPreset)
    case customImage(assetID: String, focalY: Double)

    var normalized: Self {
        if case let .customImage(id, focalY) = self {
            guard PlatformAppearanceAssetCache.isValidID(id) else { return .defaultAsset }
            return .customImage(assetID: id, focalY: (0...1).clamping(focalY, fallback: 0.5))
        }
        return self
    }

    public var assetID: String? {
        guard case let .customImage(id, _) = self else { return nil }
        return id
    }
}

public enum PlatformLogoMode: Codable, Equatable, Sendable, Hashable {
    case auto
    case symbol(name: String, tintHex: String?)
    case monogramBadge(text: String, tintHex: String?)
    case customImage(assetID: String)

    var normalized: Self {
        switch self {
        case .auto: return self
        case let .symbol(name, tint):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .auto }
            return .symbol(name: String(name.prefix(80)), tintHex: Self.validTint(tint))
        case let .monogramBadge(text, tint):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return .monogramBadge(text: String(text.prefix(3)), tintHex: Self.validTint(tint))
        case let .customImage(assetID):
            return PlatformAppearanceAssetCache.isValidID(assetID) ? self : .auto
        }
    }

    private static func validTint(_ tint: String?) -> String? {
        guard let tint, PlatformRGBAColor(hex: tint) != nil else { return nil }
        return tint
    }

    public var assetID: String? {
        guard case let .customImage(id) = self else { return nil }
        return id
    }
}

public enum PlatformTitleVisibility: String, Codable, Sendable, CaseIterable, Hashable {
    case auto, always, hidden
}

public struct PlatformIdiomCustomMetrics: Codable, Equatable, Sendable, Hashable {
    public var useCustomMetrics: Bool
    public var columns: Int
    public var cardHeight: Double
    public var cornerRadius: Double

    public init(useCustomMetrics: Bool = false, columns: Int, cardHeight: Double, cornerRadius: Double) {
        self.useCustomMetrics = useCustomMetrics
        self.columns = columns
        self.cardHeight = cardHeight
        self.cornerRadius = cornerRadius
    }

    public func clamped(for idiom: PlatformDeviceIdiom) -> Self {
        let defaults = idiom.defaultMetrics
        return .init(
            useCustomMetrics: useCustomMetrics,
            columns: min(idiom.columnRange.upperBound, max(idiom.columnRange.lowerBound, columns)),
            cardHeight: idiom.cardHeightRange.clamping(cardHeight, fallback: defaults.cardHeight),
            cornerRadius: idiom.cornerRadiusRange.clamping(cornerRadius, fallback: defaults.cornerRadius)
        )
    }
}

public struct PlatformCardAppearanceOverride: Codable, Equatable, Sendable, Hashable {
    public var pluginId: String
    public var logoMode: PlatformLogoMode
    public var titleVisibility: PlatformTitleVisibility
    public var backgroundOverride: PlatformBackgroundStyle?
    public var spansTwoColumns: Bool
    public var updatedAt: Date

    public init(
        pluginId: String,
        logoMode: PlatformLogoMode = .auto,
        titleVisibility: PlatformTitleVisibility = .auto,
        backgroundOverride: PlatformBackgroundStyle? = nil,
        spansTwoColumns: Bool = false,
        updatedAt: Date = .distantPast
    ) {
        self.pluginId = pluginId
        self.logoMode = logoMode
        self.titleVisibility = titleVisibility
        self.backgroundOverride = backgroundOverride
        self.spansTwoColumns = spansTwoColumns
        self.updatedAt = updatedAt
    }

    var normalized: Self {
        var value = self
        value.logoMode = logoMode.normalized
        value.backgroundOverride = backgroundOverride?.normalized
        return value
    }
}

public struct PlatformAppearanceSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Self.currentSchemaVersion
    public var globalBackground: PlatformBackgroundStyle = .defaultAsset
    public var backgroundBlurRadius: Double = 0
    public var contrastScrimEnabled = true
    public var gridDensity: PlatformGridDensity = .standard
    public var cardAspect: PlatformCardAspectPreset = .classic
    public var globalUpdatedAt: Date = .distantPast
    public var idiomMetrics: [PlatformDeviceIdiom: PlatformIdiomCustomMetrics] = [:]
    public var idiomUpdatedAt: [PlatformDeviceIdiom: Date] = [:]
    public var orderedPluginIds: [String] = []
    public var orderUpdatedAt: Date = .distantPast
    public var cardOverrides: [String: PlatformCardAppearanceOverride] = [:]
    public var resetTombstones: [String: Date] = [:]
    var allCardsResetAt: Date?

    public init() {}

    public func metrics(for idiom: PlatformDeviceIdiom) -> PlatformIdiomCustomMetrics {
        idiomMetrics[idiom]?.clamped(for: idiom) ?? idiom.defaultMetrics
    }

    public func cardCornerRadius(for idiom: PlatformDeviceIdiom) -> Double {
        let metrics = metrics(for: idiom)
        return metrics.useCustomMetrics ? metrics.cornerRadius : idiom.defaultMetrics.cornerRadius
    }

    public func appearance(for pluginId: String) -> PlatformCardAppearanceOverride {
        cardOverrides[pluginId] ?? .init(pluginId: pluginId)
    }

    public func ordered<Element>(_ elements: [Element], id: KeyPath<Element, String>) -> [Element] {
        let ranks = Dictionary(uniqueKeysWithValues: orderedPluginIds.preservingFirstOccurrence.enumerated().map {
            ($0.element, $0.offset)
        })
        return elements.sorted { ranks[$0[keyPath: id], default: .max] < ranks[$1[keyPath: id], default: .max] }
    }

    public var referencedAssetIDs: Set<String> {
        var result = Set([globalBackground.assetID].compactMap { $0 })
        for card in cardOverrides.values {
            if let id = card.logoMode.assetID { result.insert(id) }
            if let id = card.backgroundOverride?.assetID { result.insert(id) }
        }
        return result
    }

    var normalized: Self {
        var value = self
        value.globalBackground = globalBackground.normalized
        value.backgroundBlurRadius = (0...20).clamping(backgroundBlurRadius, fallback: 0)
        value.orderedPluginIds = orderedPluginIds.preservingFirstOccurrence
        for (idiom, metrics) in idiomMetrics {
            value.idiomMetrics[idiom] = metrics.clamped(for: idiom)
        }
        value.cardOverrides = cardOverrides.filter { id, card in
            guard !id.isEmpty, id == card.pluginId else { return false }
            if let reset = latestReset(for: id) { return card.updatedAt > reset }
            return true
        }.mapValues(\.normalized)
        return value
    }

    func latestReset(for pluginID: String) -> Date? {
        [allCardsResetAt, resetTombstones[pluginID]].compactMap { $0 }.max()
    }

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == currentSchemaVersion else { throw PlatformAppearanceStorageError.unsupportedVersion }
        return value
    }
}

enum PlatformAppearanceStorageError: Error {
    case unsupportedVersion
    case invalidCloudRecord
    case accountChanged
    case unresolvedConflict
}

public struct PlatformRGBAColor: Equatable, Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }

    /// Accepts RGB or RGBA in three, six or eight hexadecimal digits.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.first == "#" { digits.removeFirst() }
        guard [3, 6, 8].contains(digits.utf8.count),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        if digits.count == 3 {
            digits = digits.map { String(repeating: String($0), count: 2) }.joined()
        }
        guard let number = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 8 {
            self.init(red: Double((number >> 24) & 255) / 255,
                      green: Double((number >> 16) & 255) / 255,
                      blue: Double((number >> 8) & 255) / 255,
                      alpha: Double(number & 255) / 255)
        } else {
            self.init(rgb: number)
        }
    }
}

extension ClosedRange<Double> {
    func clamping(_ value: Double, fallback: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value.isFinite ? value : fallback))
    }
}

extension Array where Element == String {
    var preservingFirstOccurrence: [String] {
        var seen = Set<String>()
        return filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
