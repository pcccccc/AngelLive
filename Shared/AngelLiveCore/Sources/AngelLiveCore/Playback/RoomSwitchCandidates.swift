import Foundation

public enum RoomSwitchSource: String, CaseIterable, Sendable {
    case favorite
    case history
    case category
}

public enum RoomSwitchCandidates {
    public enum Direction: Sendable {
        case previous
        case next
    }

    public static func rooms(
        for source: RoomSwitchSource,
        currentRoom: LiveModel,
        favorites: [LiveModel],
        history: [LiveModel],
        category: [LiveModel],
        includesOnDemand: Bool = false
    ) -> [LiveModel] {
        orderedRooms(for: source, favorites: favorites, history: history,
                     category: category, includesOnDemand: includesOnDemand)
            .filter { $0 != currentRoom }
    }

    public static func orderedRooms(
        for source: RoomSwitchSource,
        favorites: [LiveModel],
        history: [LiveModel],
        category: [LiveModel],
        includesOnDemand: Bool = false
    ) -> [LiveModel] {
        let sourceRooms: [LiveModel]
        switch source {
        case .favorite:
            sourceRooms = playableFavorites(favorites, includesOnDemand: includesOnDemand)
        case .history:
            sourceRooms = history
        case .category:
            sourceRooms = category
        }

        var seen = Set<LiveModel>()
        return sourceRooms.filter { seen.insert($0).inserted }
    }

    public static func adjacentRoom(
        _ direction: Direction,
        for source: RoomSwitchSource,
        currentRoom: LiveModel,
        favorites: [LiveModel],
        history: [LiveModel],
        category: [LiveModel],
        includesOnDemand: Bool = false
    ) -> LiveModel? {
        let rooms = orderedRooms(for: source, favorites: favorites, history: history,
                                 category: category, includesOnDemand: includesOnDemand)
        guard let currentIndex = rooms.firstIndex(of: currentRoom) else {
            return direction == .next ? rooms.first : nil
        }
        let targetIndex = currentIndex + (direction == .next ? 1 : -1)
        return rooms.indices.contains(targetIndex) ? rooms[targetIndex] : nil
    }

    public static func totalSwitchableCount(
        currentRoom: LiveModel,
        favorites: [LiveModel],
        history: [LiveModel],
        category: [LiveModel],
        includesOnDemand: Bool = false
    ) -> Int {
        var rooms = Set<LiveModel>()
        rooms.formUnion(playableFavorites(favorites, includesOnDemand: includesOnDemand))
        rooms.formUnion(history)
        rooms.formUnion(category)
        rooms.remove(currentRoom)
        return rooms.count
    }

    static func playableFavorites(
        _ favorites: [LiveModel],
        includesOnDemand: Bool,
        isOnDemand: (LiveType) -> Bool = { liveType in
            let plugin = SandboxPluginCatalog.platform(for: liveType)
                .flatMap { try? LiveParsePlugins.shared.resolve(pluginId: $0.pluginId) }
            return plugin.map { PlatformHostBehavior.declaresOnDemand($0.manifest) } ?? false
        }
    ) -> [LiveModel] {
        var onDemandByType: [LiveType: Bool] = [:]
        return favorites.filter { room in
            if room.liveState == LiveState.live.rawValue { return true }
            guard includesOnDemand else { return false }
            if let declared = onDemandByType[room.liveType] { return declared }
            let declared = isOnDemand(room.liveType)
            onDemandByType[room.liveType] = declared
            return declared
        }
    }
}
