// An enchanted hit from a trap's `Weapon.Fire`: the trap holds no copy of the
// weapon, so the effects apply and no charge is spent.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct EnchantmentTrapHitTests {
    @Test func aTrapHitAppliesItsEnchantmentWithoutSpendingCharge() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let target = EnchantmentRuntimeFixture.target
        let hit = WeaponEnchantmentHit(
            profile: blade, attacker: .generated(90), target: target.key
        )
        for _ in 0 ... EnchantmentRuntimeFixture.bladeUses {
            let report = WeaponEnchantmentApplication.apply(
                hit, owner: nil, target: target, using: &world.effects
            )
            #expect(report.didFire)
            #expect(report.charge.remaining == blade.capacity)
        }
        let uses = Float(EnchantmentRuntimeFixture.bladeUses + 1)
        #expect(
            world.effects.values.current(of: target).health
                == 100 - EnchantmentRuntimeFixture.bladeDamage * uses
        )
    }
}
