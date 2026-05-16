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

        guard isSOOP(liveType),
              let fallback = soopLivePreviewURLString(roomId: roomId) else {
            return ""
        }

        // SOOP sometimes omits thumbnails on authenticated/detail paths while
        // the CDN still exposes previews deterministically by broad_no.
        Logger.debug("[ImageResolver][SOOP] fallback=\(fallback)", category: .general)
        return fallback
    }

    public static func soopLivePreviewURLString(roomId: String, refreshToken: String? = nil) -> String? {
        let trimmedRoomId = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNumericRoomId(trimmedRoomId) else { return nil }

        var preview = "https://liveimg.sooplive.com/m/\(trimmedRoomId)?320"
        if let refreshToken = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !refreshToken.isEmpty {
            preview += "&_al_preview=\(refreshToken)"
        }
        return preview
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
        let resolvedCover = LiveImageURLResolver.roomCoverURLString(
            rawValue: roomCover,
            liveType: liveType,
            roomId: roomId
        )
        if !resolvedCover.isEmpty {
            return resolvedCover
        }

        let rawLiveType = liveType.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rawLiveType == "8" || rawLiveType == "soop" {
            // Older SOOP favorites may only have bjId/station id, not broad_no.
            // Use the avatar as a visible fallback instead of a blank card.
            return LiveImageURLResolver.avatarURLString(rawValue: userHeadImg)
        }
        return ""
    }

    var displayUserHeadImg: String {
        LiveImageURLResolver.avatarURLString(rawValue: userHeadImg)
    }
}
