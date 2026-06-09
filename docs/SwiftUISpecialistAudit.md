# SwiftUI Specialist Audit

Date: 2026-06-09
Scope: static, read-only SwiftUI review for AngelLive using the `swiftui-specialist` guidance.

## Summary

This audit focused on SwiftUI data flow, identity stability, view invalidation boundaries, and common list/focus pitfalls. No files were changed during the scan.

Key project facts:

- SwiftUI-related files scanned: 185
- `struct ...: View` declarations found: 174
- Codebase language mix from the prior security scan: Swift-only app code in this workspace scan
- Highest-risk areas: tvOS card/list focus flows, shared live model identity, large player views

## Findings

### P1: tvOS `LiveCardView` stores parent inputs in `@State`

Files:

- `TV/AngelLiveTVOS/Source/List/LiveCardView.swift:17`
- `TV/AngelLiveTVOS/Source/List/LiveCardView.swift:20`

Current pattern:

```swift
@State var index: Int
@State var currentLiveModel: LiveModel?
```

Why this matters:

`index` and `currentLiveModel` are inputs from the parent view, not view-owned state. SwiftUI preserves `@State` across view updates, so when list data refreshes, filters, or reorders, the card can keep stale state while the parent believes it passed a new value.

Potential symptoms:

- Card displays stale room data after refresh/search/favorite sync.
- Focus index and displayed room diverge.
- Clicking a card can enter the wrong room.
- Row/card state is preserved for the wrong item when SwiftUI reuses the view.

Recommended direction:

- Make parent-provided values plain stored inputs:

```swift
let index: Int
let currentLiveModel: LiveModel?
```

- Keep only truly local UI state as `@State`, such as `isLive`.
- Prefer passing the concrete `LiveModel` into the card where possible, and use a stable room id for identity.

### P1: `LiveModel` has inconsistent `Equatable` and `Hashable`

File:

- `Shared/AngelLiveCore/Sources/AngelLiveCore/LiveParse/LiveModel.swift:12`

Current pattern:

```swift
public struct LiveModel: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id = UUID()
    ...

    public static func ==(lhs: LiveModel, rhs: LiveModel) -> Bool {
        return lhs.roomId == rhs.roomId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

Why this matters:

`Hashable` requires equal values to produce equal hashes. Here, equality uses `roomId`, but hashing uses a random UUID. Two `LiveModel` values with the same `roomId` can compare equal while producing different hashes.

Potential symptoms:

- Incorrect behavior in `Set`, `Dictionary`, diffing, and SwiftUI identity.
- `ForEach(..., id: \.self)` can become unstable or expensive.
- Focus, selection, and row state can reset or attach to the wrong item.

Recommended direction:

Use one stable identity consistently. If `roomId` is the real domain identity, prefer:

```swift
public var id: String { roomId }

public static func ==(lhs: LiveModel, rhs: LiveModel) -> Bool {
    lhs.roomId == rhs.roomId
}

public func hash(into hasher: inout Hasher) {
    hasher.combine(roomId)
}
```

If `roomId` is not globally unique across platforms, combine it with `liveType` or another stable source key:

```swift
public var id: String { "\(liveType.rawValue)-\(roomId)" }
```

### P2: Dynamic lists use index as SwiftUI identity

Representative files:

- `TV/AngelLiveTVOS/Source/Favorite/FavoriteMainView.swift:76`
- `TV/AngelLiveTVOS/Source/Favorite/FavoriteMainView.swift:96`
- `TV/AngelLiveTVOS/Source/Search/SearchRoomView.swift:89`
- `TV/AngelLiveTVOS/Source/List/SidebarView.swift:93`
- `iOS/AngelLive/AngelLive/FullUI/Views/PlatformDetailView.swift:139`
- `iOS/AngelLive/AngelLive/FullUI/Components/SegmentedControl.swift:20`
- `iOS/AngelLive/AngelLive/FullUI/Components/InteractiveSegmentedControl.swift:34`

Current pattern examples:

```swift
ForEach(section.roomList.indices, id: \.self) { index in
    LiveCardView(index: index, currentLiveModel: section.roomList[index])
}
```

```swift
ForEach(liveViewModel.categories.indices, id: \.self) { index in
    SidebarMenuItem(...)
}
```

Why this matters:

Collection indices describe positions, not elements. When a collection inserts, removes, refreshes, filters, or reorders, the same index can point to a different element. SwiftUI then preserves state/focus for the position instead of the actual item.

Potential symptoms:

- tvOS focus jumps or remains attached to the wrong card.
- Rows animate as replacements instead of moves.
- Per-row state resets after refresh.
- Selection and scroll position become fragile.

Recommended direction:

- For rooms, use stable room identity:

```swift
ForEach(section.roomList, id: \.id) { room in
    LiveCardView(currentLiveModel: room)
}
```

- If the row still needs its visible index, enumerate but keep element identity:

```swift
ForEach(Array(section.roomList.enumerated()), id: \.element.id) { index, room in
    LiveCardView(index: index, currentLiveModel: room)
}
```

- For categories, prefer the category's stable `id`:

```swift
ForEach(viewModel.categories, id: \.id) { category in
    CategoryButton(category: category)
}
```

Notes:

- Fixed ranges for skeleton placeholders, such as `ForEach(0..<6, id: \.self)`, are acceptable.
- Static arrays of strings or enum cases are lower risk if the content never reorders, but stable semantic ids are still clearer.

### P2: Favorite sections use random UUID identity

Files:

- `Shared/AngelLiveCore/Sources/AngelLiveCore/Models/FavoriteStateModel.swift:10`
- `TV/AngelLiveTVOS/Source/Favorite/FavoriteMainView.swift:58`

Current pattern:

```swift
public struct FavoriteLiveSectionModel: Identifiable, Sendable {
    public var id = UUID()
    public var roomList: [LiveModel] = []
    public var title: String = ""
    public var type: LiveType = .placeholder
}
```

Why this matters:

The tvOS favorite page renders sections using `section.id`. If sections are rebuilt during sync and receive fresh UUIDs, SwiftUI treats every section as a new section even when it represents the same logical group.

Potential symptoms:

- Focus resets after favorite sync.
- Section animations appear as full replacement.
- Scroll/focus state is not preserved between refreshes.

Recommended direction:

Use a stable section id based on the logical section:

```swift
public var id: String { "\(type.rawValue)-\(title)" }
```

Or, if `type` is sufficient and unique per group:

```swift
public var id: LiveType { type }
```

### P2: Several `@State` properties are not private or are not true view-local state

Representative files:

- `TV/AngelLiveTVOS/Source/Favorite/FavoriteMainView.swift:18`
- `TV/AngelLiveTVOS/Source/Favorite/FavoriteMainView.swift:19`
- `TV/AngelLiveTVOS/Source/Favorite/FavoriteMainView.swift:20`
- `TV/AngelLiveTVOS/Source/Setting/SettingView.swift:18`
- `TV/AngelLiveTVOS/Tools/Common/SharedComponents/QRCode/QRCodeView.swift:16`
- `iOS/AngelLive/AngelLive/FullUI/Views/DetailPlayerView.swift:14`
- `TV/AngelLiveTVOS/Source/DetailPlayer/PlayerControlView.swift:38`
- `TV/AngelLiveTVOS/Source/DetailPlayer/PlayerControlView.swift:39`

Why this matters:

SwiftUI guidance recommends `@State` be private and used only for view-owned state. Non-private `@State` makes ownership unclear, and using `@State` for parent inputs or constants can create stale UI.

Recommended direction:

- Mark true local state as `@State private var`.
- Convert constants such as settings titles to `private let` or a static constant.
- Convert parent-provided inputs to `let` or `var` stored properties.
- Keep model ownership in `@State` only when the view creates and owns the model lifecycle.

### P3: Large views rely heavily on computed `some View` helpers

Representative files:

- `macOS/AngelLiveMacOS/Views/PlayerControlView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Setting/SyncView.swift`
- `TV/AngelLiveTVOS/Source/DetailPlayer/PlayerControlView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerUI/VideoControllerView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerContainerView.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/Player/UnifiedPlayerControlOverlay.swift`

Why this matters:

Computed `some View` properties and `@ViewBuilder` helper methods improve readability, but they do not create independent SwiftUI invalidation boundaries. When parent state changes, SwiftUI still re-evaluates the parent body and all inlined helper content.

This is most relevant in playback and tvOS focus views where state changes frequently.

Recommended direction:

- Do not attempt a whole-codebase rewrite.
- Pick one hot screen at a time, preferably playback controls or tvOS list/focus screens.
- Extract independent sections into separate `View` structs with narrow inputs.
- Keep high-frequency state dependencies as low in the tree as possible.

Example direction:

```swift
struct PlayerControlView: View {
    var body: some View {
        VStack {
            PlayerTopControls(...)
            PlayerRoomCarousel(...)
            PlayerStatusFooter(...)
        }
    }
}
```

Each child should receive only the values it actually reads.

## Lower-Risk Notes

### `AnyView` appears mostly in UIKit/AppKit hosting boundaries

Representative files:

- `iOS/AngelLive/AngelLive/FullUI/Views/UIKit/ViewControllers/FavoriteListViewController.swift`
- `iOS/AngelLive/AngelLive/FullUI/Views/UIKit/View/LiveRoomCollectionViewCell.swift`
- `iOS/AngelLive/AngelLive/Common/Components/DevConsoleOverlay.swift`
- `macOS/AngelLiveMacOS/Components/MacPanelComponents.swift`

Most `AnyView` usages are at hosting/controller boundaries or type-erased component slots. These are not immediate findings, but avoid introducing more `AnyView` inside pure SwiftUI list rows or high-frequency body paths.

### `NavigationView` appears in an old tvOS file

File:

- `TV/AngelLiveTVOS/Other/ContentView.swift:38`

`NavigationView` is soft-deprecated in modern SwiftUI, but this appears to be under `Other/` and was not treated as an urgent issue. Consider migration only if this file is active and being touched for another reason.

### `.onChange(of:)` usage is widespread

The scan found many `.onChange(of:)` calls, most already use the newer old/new value closure shape. This was not flagged as a problem. When editing related code, keep side effects isolated and avoid putting heavy work directly in high-frequency `onChange` handlers.

## Suggested Remediation Order

1. Fix `LiveModel` identity/hash consistency.
2. Fix `TV/AngelLiveTVOS/Source/List/LiveCardView.swift` so parent inputs are not stored in `@State`.
3. Update tvOS dynamic room/category lists to use stable element ids instead of indices.
4. Stabilize `FavoriteLiveSectionModel.id`.
5. Clean up non-private or non-local `@State` properties opportunistically.
6. Refactor one large playback/focus screen at a time into smaller `View` structs with narrow inputs.

## Validation Plan

After applying fixes, validate with:

- Build iOS, tvOS, and macOS schemes.
- tvOS smoke test:
  - open live list
  - move focus across cards
  - refresh/switch categories
  - open favorite page
  - sync/refresh favorites
  - verify focus and selected room remain correct
- iOS smoke test:
  - search rooms
  - switch search type
  - open a room from search and platform detail
- Regression checks:
  - verify duplicate room handling still works
  - verify favorites grouping still preserves expected order
  - verify room navigation uses the correct room after list refresh
