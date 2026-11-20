import Foundation

public enum PlaybackDisplay {
    public static func compactQualityTitle(_ title: String) -> String {
        let separators: Set<Character> = ["_", " ", "-", "·", "(", "（", "/"]
        let prefix = title.prefix { !separators.contains($0) }
        return prefix.isEmpty ? title : String(prefix)
    }

    public static func popularityTitle(_ count: String?) -> String? {
        guard let value = count?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let number = Double(value), !number.isFinite || number <= 0 {
            return nil
        }
        guard let integer = Int(value) else { return value }
        if integer >= 10_000 {
            return String(format: "%.1f万", Double(integer) / 10_000)
        }
        if integer >= 1_000 {
            return String(format: "%.1fk", Double(integer) / 1_000)
        }
        return String(integer)
    }

    public static func lineTitle(for cdn: LiveQualityModel, index: Int) -> String {
        if let name = cdn.displayName.flatMap(readableLineTitle), !isShortLineIdentifier(name) {
            return name
        }

        // Legacy plugins may supply a human-readable label in the line identifier field.
        if let name = readableLineTitle(cdn.cdn), isReadableLegacyLineTitle(name) {
            return name
        }
        return String(localized: "线路 \(index + 1)")
    }

    public static func qualityTitle(_ quality: LiveQualityDetail, in playArgs: [LiveQualityModel]?) -> String {
        guard !quality.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "清晰度")
        }
        return RoomPlaybackResolver.qualityDisplayTitle(quality, in: playArgs)
    }

    private static func readableLineTitle(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let reservedCharacters = CharacterSet(charactersIn: ".:/@?#=%\\").union(.controlCharacters)
        guard name.contains(where: \.isLetter), name.rangeOfCharacter(from: reservedCharacters) == nil else {
            return nil
        }
        return name
    }

    private static func isShortLineIdentifier(_ name: String) -> Bool {
        name.utf8.count <= 16 && name.utf8.allSatisfy { byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
        }
    }

    private static func isReadableLegacyLineTitle(_ name: String) -> Bool {
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0.isWhitespace }) else { return false }
        return name.contains { $0.isLetter && !$0.isASCII }
            || name.contains(where: \.isWhitespace)
    }
}

public struct BracketSafeName: Sendable {
    private static let delimiters: [Character: Character] = [
        "(": ")", "（": "）", "[": "]", "【": "】", "「": "」", "『": "』",
        "“": "”", "‘": "’", "«": "»", "\"": "\"", "'": "'"
    ]
    private static let closingDelimiters = Set(delimiters.values)
    private static let ellipsis = "…"

    private let characters: [Character]
    private let safeEndOffsets: [Int]
    private let enclosedFirstCharacter: Character?

    public var fullTitle: String { String(characters) }

    public init(_ name: String) {
        let source = Array(name.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines))
        let delimiters = source.indices.map { Self.delimiter(at: $0, in: source) }
        var open: [(index: Int, closing: Character)] = []
        var pairs: [Int: Int] = [:]
        for (index, delimiter) in delimiters.enumerated() {
            guard let delimiter else { continue }
            if let last = open.last, last.closing == delimiter {
                pairs[last.index] = index
                open.removeLast()
            } else if let closing = Self.delimiters[delimiter] {
                open.append((index, closing))
            }
        }

        let matchedClosers = Set(pairs.values)
        var matchedDepth = 0
        var visible: [Character] = []
        var endOffsets: [Int] = []
        for index in source.indices {
            if pairs[index] != nil {
                matchedDepth += 1
            } else if matchedClosers.contains(index) {
                matchedDepth -= 1
            } else if delimiters[index] != nil {
                continue
            }
            visible.append(source[index])
            if matchedDepth == 0 && !source[index].isWhitespace {
                endOffsets.append(visible.count)
            }
        }

        while visible.last?.isWhitespace == true { visible.removeLast() }
        characters = visible
        safeEndOffsets = endOffsets
        if let last = source.indices.last, pairs[0] == last {
            enclosedFirstCharacter = source.indices.first { delimiters[$0] == nil && !source[$0].isWhitespace }
                .map { source[$0] }
        } else {
            enclosedFirstCharacter = nil
        }
    }

    /// Uses the caller’s font measurement to choose a complete prefix.
    public func title(fitting fits: (String) -> Bool) -> String {
        let title = fullTitle
        guard !fits(title) else { return title }
        guard fits(Self.ellipsis) else { return "" }
        var best = Self.ellipsis
        for offset in safeEndOffsets where offset < characters.count {
            let candidate = String(characters.prefix(offset)) + Self.ellipsis
            guard fits(candidate) else { break }
            best = candidate
        }
        if best == Self.ellipsis, let enclosedFirstCharacter {
            let candidate = String(enclosedFirstCharacter) + Self.ellipsis
            if fits(candidate) { return candidate }
        }
        return best
    }

    private static func delimiter(at index: Int, in characters: [Character]) -> Character? {
        let character = characters[index]
        // Apostrophes within words are text, not quotation marks.
        if (character == "'" || character == "’"), index > 0, index < characters.count - 1,
           characters[index - 1].isLetter, characters[index + 1].isLetter {
            return nil
        }
        return delimiters[character] != nil || closingDelimiters.contains(character) ? character : nil
    }
}
