import Foundation

public struct RoomSearchOutcome: Sendable {
    public let rooms: [LiveModel]
    public let authenticationRequiredPluginIDs: [String]

    public init(rooms: [LiveModel], authenticationRequiredPluginIDs: [String] = []) {
        self.rooms = rooms
        self.authenticationRequiredPluginIDs = Self.stablePluginIDs(authenticationRequiredPluginIDs)
    }

    private static func stablePluginIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}

public struct PluginAuthenticationRequiredError: Error, LocalizedError, Sendable {
    public let pluginIDs: [String]

    public init(pluginIDs: [String]) {
        self.pluginIDs = RoomSearchOutcome(
            rooms: [],
            authenticationRequiredPluginIDs: pluginIDs
        ).authenticationRequiredPluginIDs
    }

    public var errorDescription: String? {
        "当前内容需要登录账号后才能访问，请登录对应平台后重试。"
    }
}

public struct AuthenticationRecoveryRequest: Identifiable, Sendable {
    public let id: UUID
    public let pluginIDs: [String]

    public init(pluginIDs: [String]) {
        id = UUID()
        self.pluginIDs = RoomSearchOutcome(
            rooms: [],
            authenticationRequiredPluginIDs: pluginIDs
        ).authenticationRequiredPluginIDs
    }
}
