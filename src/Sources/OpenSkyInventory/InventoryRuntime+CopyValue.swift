// What one copy of an item is worth: the record's value with its own enchantment, the
// worth of a made enchantment on the copy, and its temper. See docs/engine/barter.md
// and docs/engine/enchanting.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

extension InventoryRuntime {
    /// `copy`'s gold value. Zero when no loaded plugin describes `item`.
    public func value(of item: FormID, copy: ItemCopy) -> Int32 {
        let items = baselines.items
        var value = Int64(items.gameValue(of: item))
        if
            let id = copy.enchantment, let made = madeEnchantment(id),
            let definition = items.definition(item)
        {
            value += Int64(made.addedValue(
                isWeapon: definition.family == .weapon, settings: items.enchantedValueSettings
            ))
        }
        let clamped = Int32(clamping: value)
        guard copy.level > 0 else { return clamped }
        let tempered = (Float(clamped) * Tempering.valueMultiplier(level: copy.level))
            .rounded(.down)
        return Int32(clamping: Int(min(tempered, Float(Int32.max))))
    }

    /// The best held copy's value, which is the copy an item card shows.
    public func bestCopyValue(of item: FormID, in holder: InventoryHolder) -> Int32 {
        value(of: item, copy: copies(of: item, in: holder).first ?? .plain)
    }

    /// The player made every made enchantment, so the player's component holds it.
    private func madeEnchantment(_ id: FormID) -> MadeEnchantment? {
        store.component(EnchantingState.self, for: ReferenceKey.player)?.made[id]
    }
}
