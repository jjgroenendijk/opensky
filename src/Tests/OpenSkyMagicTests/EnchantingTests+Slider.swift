// The arcane enchanter's magnitude slider on a weapon, the chosen magnitude, and the
// name typed for the item.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import Testing

extension EnchantingTests {
    /// The fire base's full magnitude is the maximum; a lower magnitude costs less per
    /// hit, so the same soul gives more uses.
    @Test func aWeaponOffersTheSliderAndALowerMagnitudeGivesMoreUses() throws {
        let trial = try session(carrying: [Records.ironSword, Gems.grandFilled])
        trial.knowing([Records.fireBase])
        let enchanter = trial.coordinator.enchanter
        var selection = EnchanterSelection()
        selection.item = Records.ironSword
        selection.bases = [trial.key(Records.fireBase)]
        let full = try #require(enchanter.slider(of: selection))
        #expect(full.value == full.maximum)
        #expect(full.step == 1)
        selection.magnitude = max(1, full.maximum / 2)
        let half = try #require(enchanter.slider(of: selection))
        #expect(half.value == selection.magnitude)
        #expect(half.uses > full.uses)
        selection.gem = enchanter.enchanterChoices.gems.first
        selection.name = "Biter"
        #expect(enchanter.enchant(selection).done)
        let copy = try #require(trial.inventory.copies(of: Records.ironSword, in: .player).first)
        #expect(copy.name == "Biter")
        #expect(copy.enchantment != nil)
    }

    /// An effect-priced base keeps its fraction: 10^1.1 = 12.59, so at skill 100 a use
    /// costs 3 * 12.59^1.1 * 0.2929 = 14.27, where a whole 12 would give 13.
    @Test func anEffectPricedBaseKeepsTheFractionOfItsCost() throws {
        let trial = try session(carrying: [Records.ironSword, Gems.grandFilled])
        trial.knowing([Records.fireAutoBase])
        try trial.coordinator.enchantingTable.enchant(
            Records.ironSword, with: [trial.key(Records.fireAutoBase)],
            gem: trial.gem(Gems.grandFilled)
        )
        let charge = try #require(trial.coordinator.weaponEnchantments.enchantmentCharge(
            of: Records.ironSword, on: .player
        ))
        #expect(charge.costPerUse == 14)
    }

    @Test func apparelAndAnUnfinishedChoiceShowNoSlider() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.healthBase])
        let enchanter = trial.coordinator.enchanter
        var selection = EnchanterSelection()
        #expect(enchanter.slider(of: selection) == nil)
        selection.item = Records.ring
        selection.bases = [trial.key(Records.healthBase)]
        #expect(enchanter.slider(of: selection) == nil)
    }
}

extension EnchantingTests {
    /// Each hit takes one dose off the poison on the wielded copy, and the poison goes at 0.
    @Test func aHitSpendsADoseFromTheWieldedCopy() throws {
        let trial = try session(carrying: [Records.ironSword])
        trial.world.holders[.player] = .player
        let sword = Records.ironSword
        let poison = WeaponPoison(poison: FormID(0x0003_EB2E), doses: 2)
        trial.inventory.editCopy(
            of: sword,
            in: .player,
            where: { _ in true },
            { $0.poison = poison }
        )
        let hit = WeaponPoisonHit(attacker: .player, weapon: sword, target: .player)
        trial.coordinator.weaponEnchantments.applyWeaponPoison(hit)
        #expect(trial.inventory.copies(of: sword, in: .player).first?.poison?.doses == 1)
        trial.coordinator.weaponEnchantments.applyWeaponPoison(hit)
        #expect(trial.inventory.copies(of: sword, in: .player).first?.poison == nil)
    }
}
