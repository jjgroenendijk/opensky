// The player's favourite items and the number keys bound to them. UESP
// "Skyrim:Controls" (<https://en.uesp.net/wiki/Skyrim:Controls>): a favourite can take
// one of the hotkeys 1 to 8. See docs/engine/inventory-menu.md.

import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public struct FavouritesState: WorldStateComponent, Sendable {
    public static let hotkeySlots = 1 ... 8

    /// In the order they were marked, which the Favorites tab lists them in.
    public private(set) var items: [FormID]
    /// Slot to item. Every bound item is a favourite.
    public private(set) var hotkeys: [Int: FormID]

    public static var componentKind: WorldStateComponentKind {
        .favourites
    }

    /// Drops repeats, slots outside 1 to 8, and slots bound to no favourite.
    public init(items: [FormID] = [], hotkeys: [Int: FormID] = [:]) {
        var seen: Set<FormID> = []
        self.items = items.filter { seen.insert($0).inserted }
        let favourites = seen
        self.hotkeys = hotkeys.filter {
            Self.hotkeySlots.contains($0.key) && favourites.contains($0.value)
        }
    }

    public func contains(_ item: FormID) -> Bool {
        items.contains(item)
    }

    public func hotkey(of item: FormID) -> Int? {
        hotkeys.first { $0.value == item }?.key
    }

    /// Marks or unmarks `item`. Unmarking also frees its hotkey.
    public func toggling(_ item: FormID) -> FavouritesState {
        contains(item)
            ? FavouritesState(items: items.filter { $0 != item }, hotkeys: hotkeys)
            : FavouritesState(items: items + [item], hotkeys: hotkeys)
    }

    /// Binds `slot` to `item`, which becomes a favourite. The item leaves any slot it
    /// held. Nil for a slot outside 1 to 8.
    public func binding(_ item: FormID, to slot: Int) -> FavouritesState? {
        guard Self.hotkeySlots.contains(slot) else { return nil }
        var updated = hotkeys.filter { $0.value != item }
        updated[slot] = item
        return FavouritesState(items: contains(item) ? items : items + [item], hotkeys: updated)
    }
}

nonisolated extension WorldStateComponentKind {
    public static let favourites = Self(rawValue: "favourites", order: 40, affectsCellBuild: false)
}
