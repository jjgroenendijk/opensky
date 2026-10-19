// Favourites and their hotkeys: the inventory menu marks an item, a number key 1 to
// 8 uses it. See docs/engine/inventory-menu.md.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// What a favourite or hotkey action did, for the readout.
nonisolated public enum FavouriteOutcome: Error, Equatable, Sendable {
    case unavailable
    case marked(String)
    case unmarked(String)
    case bound(String, slot: Int)
    case badSlot(Int)
    case emptySlot(Int)
    case notCarried(String)

    public var text: String {
        switch self {
        case .unavailable: InventoryCore.noRuntimeText
        case let .marked(name): "\(name) is a favourite."
        case let .unmarked(name): "\(name) is no longer a favourite."
        case let .bound(name, slot): "Hotkey \(slot) uses \(name)."
        case let .badSlot(slot): "Hotkey \(slot) does not exist; use 1 to 8."
        case let .emptySlot(slot): "Hotkey \(slot) has no favourite."
        case let .notCarried(name): "The player carries no \(name)."
        }
    }
}

extension InventoryCoordinator {
    public var playerFavourites: FavouritesState {
        runtime?.store.component(FavouritesState.self, for: .player) ?? FavouritesState()
    }

    @discardableResult
    public func toggleFavourite(_ item: FormID) -> FavouriteOutcome {
        guard let runtime else { return .unavailable }
        let favourites = playerFavourites
        runtime.store.set(favourites.toggling(item), for: .player)
        return favourites.contains(item) ? .unmarked(name(of: item)) : .marked(name(of: item))
    }

    /// Binds `slot` to `item`, which becomes a favourite if it was not one.
    @discardableResult
    public func bindHotkey(_ slot: Int, to item: FormID) -> FavouriteOutcome {
        guard let runtime else { return .unavailable }
        guard let bound = playerFavourites.binding(item, to: slot) else { return .badSlot(slot) }
        runtime.store.set(bound, for: .player)
        return .bound(name(of: item), slot: slot)
    }

    /// The carried item `slot` names, or why there is none.
    public func hotkeyItem(_ slot: Int) -> Result<FormID, FavouriteOutcome> {
        guard let runtime else { return .failure(.unavailable) }
        guard FavouritesState.hotkeySlots.contains(slot) else { return .failure(.badSlot(slot)) }
        guard let item = playerFavourites.hotkeys[slot] else { return .failure(.emptySlot(slot)) }
        guard runtime.inventory.count(of: item, in: runtime.player) > 0 else {
            return .failure(.notCarried(name(of: item)))
        }
        return .success(item)
    }
}
