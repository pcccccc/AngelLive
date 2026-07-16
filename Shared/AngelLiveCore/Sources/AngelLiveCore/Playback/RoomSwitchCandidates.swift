import Foundation

public enum RoomSwitchSource: String, CaseIterable, Sendable {
    case favorite
    case history
    case category
}

public enum RoomSwitchCandidates {
    public static func rooms(
        for source: RoomSwitchSource,
        currentRoom: LiveModel,
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
        return sourceRooms.filter { room in
            guard room != currentRoom else { return false }
            return seen.insert(room).inserted
        }
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
