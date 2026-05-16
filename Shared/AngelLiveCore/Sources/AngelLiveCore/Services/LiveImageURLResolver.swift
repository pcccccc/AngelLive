import Foundation

/// Normalizes room image URLs before UI code hands them to Kingfisher.
///
/// Plugins should ideally return final absolute image URLs. This resolver keeps
/// host-side compatibility for older plugin versions and saved records that may
/// contain empty, scheme-relative, or legacy-domain image values.
public enum LiveImageURLResolver {
    public static func roomCoverURLString(
        rawValue: String,
        liveType: LiveType,
        roomId: String
    ) -> String {
        let normalizedRaw = normalizedURLString(rawValue)
        if !normalizedRaw.isEmpty {
            return normalizedRaw
        }

        guard isSOOP(liveType), isNumericRoomId(roomId) else {
            return ""
        }

        // SOOP sometimes omits thumbnails on authenticated/detail paths while
        // the CDN still exposes previews deterministically by broad_no.
        let fallback = "https://liveimg.sooplive.com/m/\(roomId)"
        Logger.debug("[ImageResolver][SOOP] fallback=\(fallback)", category: .general)
        return fallback
    }

    public static func avatarURLString(rawValue: String) -> String {
        normalizedURLString(rawValue)
    }

    public static func normalizedURLString(_ rawValue: String) -> String {
        var value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\/", with: "/")

        guard !value.isEmpty else { return "" }

        if value.hasPrefix("//") {
            value = "https:" + value
        } else if !hasScheme(value),
                  looksLikeHostPath(value) {
            value = "https://" + value
        }

        guard var components = URLComponents(string: value) else {
            return value
        }

        if components.scheme?.lowercased() == "http", isSOOPImageHost(components.host) {
            components.scheme = "https"
        }

        if components.host?.lowercased() == "liveimg.sooplive.co.kr" {
            components.host = "liveimg.sooplive.com"
        }

        return components.string ?? value
    }

    private static func hasScheme(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9+\-.]*://"#, options: .regularExpression) != nil
    }

    private static func looksLikeHostPath(_ value: String) -> Bool {
        guard let first = value.split(separator: "/", maxSplits: 1).first else {
            return false
        }
        return first.contains(".")
    }

    private static func isSOOP(_ liveType: LiveType) -> Bool {
        let raw = liveType.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw == "8" || raw == "soop"
    }

    private static func isSOOPImageHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "liveimg.sooplive.com" || host == "liveimg.sooplive.co.kr"
    }

    private static func isNumericRoomId(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)
    }
}

public extension LiveModel {
    var displayRoomCover: String {
        LiveImageURLResolver.roomCoverURLString(
            rawValue: roomCover,
            liveType: liveType,
            roomId: roomId
        )
    }

    var displayUserHeadImg: String {
        LiveImageURLResolver.avatarURLString(rawValue: userHeadImg)
    }
}
