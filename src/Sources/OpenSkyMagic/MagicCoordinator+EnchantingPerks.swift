// The perk entry points a new enchantment runs through: its power, its base cost, and the
// soul's charge, each with the base bound to the enchantment tab and the item to the item
// tab. See docs/engine/enchanting.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

/// The player's perks over one item at the enchanter.
struct EnchantingPerks {
    let table: MagicCoordinator.EnchantingTable
    let item: FormID
    let store: EnchantmentStore

    /// `Mod Enchantment Power` (77), as a factor.
    func power(of base: ResolvedEnchantment) -> Float {
        modified(1, at: .modEnchantmentPower, base: base, tab: .enchantment)
    }

    /// The `ENIT` cost under the manual cost flag, else the effects' sum with no
    /// fraction dropped, then `Mod Spell Cost` (38).
    func cost(of base: ResolvedEnchantment) -> Float {
        let raw = base.cost.isManual
            ? Float(base.cost.cost) : base.effects.reduce(0) { $0 + $1.cost }
        return modified(raw, at: .modSpellCost, base: base, tab: .spell)
    }

    /// The soul's charge through `Mod Soul Gem Enchanting` (79), at least 0.
    func charge(of soul: SoulLevel, first base: ResolvedEnchantment) -> Float {
        max(0, modified(
            SoulTrap.charge(of: soul),
            at: .modSoulGemEnchanting,
            base: base,
            tab: .enchantment
        ))
    }

    private func modified(
        _ value: Float, at entryPoint: PerkEntryPoint, base: ResolvedEnchantment,
        tab: PerkConditionSubject
    ) -> Float {
        let world = table.coordinator.world
        let subject = world.inventory?.baselines.items.conditionSubject(of: item)
        return world.perkModified(
            value, at: entryPoint, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player)
                .binding(tab, to: store.conditionSubject(of: base))
                .binding(.item, to: subject),
            seams: ConditionContext()
        )
    }
}
