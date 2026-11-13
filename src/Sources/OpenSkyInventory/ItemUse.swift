// What using an item does, the same from an inventory row and a favourites hotkey:
// a potion, food, or ingredient is consumed, and a poison goes on the weapon
// (UESP "Skyrim:Potions", <https://en.uesp.net/wiki/Skyrim:Potions>).

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface

extension InventoryCoordinator.Consumables {
    public func use(of item: FormID) -> ItemUse {
        if isPoison(item) {
            return .applyPoison
        }
        let items = coordinator.runtime?.inventory.baselines.items
        if items?.ingestibles[item.rawValue] != nil || items?.ingredients[item.rawValue] != nil {
            return .consume
        }
        let equipped = coordinator.runtime
            .flatMap { coordinator.equipment?.equipped(on: $0.player).contains(item) }
        return equipped == true ? .unequip : .equip
    }
}
