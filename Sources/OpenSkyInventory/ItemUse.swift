// What using an item does, the same from an inventory row and a favourites hotkey:
// a potion, food, or ingredient is consumed, and a poison goes on the weapon
// (UESP "Skyrim:Potions", <https://en.uesp.net/wiki/Skyrim:Potions>).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The action a use of one carried item runs.
nonisolated public enum ItemUse: Equatable, Sendable {
    case applyPoison
    case consume
    case equip
    case unequip
}

extension InventoryCoordinator {
    public func use(of item: FormID) -> ItemUse {
        if isPoison(item) {
            return .applyPoison
        }
        let items = runtime?.inventory.baselines.items
        if items?.ingestibles[item.rawValue] != nil || items?.ingredients[item.rawValue] != nil {
            return .consume
        }
        let equipped = runtime.flatMap { equipment?.equipped(on: $0.player).contains(item) }
        return equipped == true ? .unequip : .equip
    }
}
