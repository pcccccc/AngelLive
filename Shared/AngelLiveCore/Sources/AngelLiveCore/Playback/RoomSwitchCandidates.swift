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
        category: [LiveModel]
    ) -> [LiveModel] {
        orderedRooms(for: source, favorites: favorites, history: history, category: category)
            .filter { $0 != currentRoom }
    }

    public static func orderedRooms(
        for source: RoomSwitchSource,
        favorites: [LiveModel],
        history: [LiveModel],
        category: [LiveModel]
    ) -> [LiveModel] {
        let sourceRooms: [LiveModel]
        switch source {
        case .favorite:
            sourceRooms = favorites.filter { $0.liveState == LiveState.live.rawValue }
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
        category: [LiveModel]
    ) -> LiveModel? {
        let rooms = orderedRooms(for: source, favorites: favorites, history: history, category: category)
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
        category: [LiveModel]
    ) -> Int {
        var rooms = Set<LiveModel>()
        rooms.formUnion(favorites.filter { $0.liveState == LiveState.live.rawValue })
        rooms.formUnion(history)
        rooms.formUnion(category)
        rooms.remove(currentRoom)
        return rooms.count
    }
}
