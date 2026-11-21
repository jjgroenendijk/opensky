// A press of either attack button with the weapon sheathed only draws it, and a
// drawn bow's attack button starts no melee swing.
// See docs/engine/attack-input.md#each-button.

import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import Testing

@MainActor
struct MeleeSheathedPressTests {
    @Test func anAttackPressWithTheWeaponSheathedOnlyDraws() {
        let world = FakeMeleeWorld()
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)

        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true))

        #expect(world.raised.suffix(2) == [CombatGraphNames.weaponDraw, CombatGraphNames.weapEquip])
        #expect(!world.raised.contains(CombatGraphNames.attackStart))
        runtime.handleGraphEvents([CombatGraphNames.weaponDraw])
        let raised = world.raised.count
        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true))
        #expect(world.raised.count == raised, "a press during the draw is dropped")
    }

    @Test func aBlockPressWithTheWeaponSheathedDraws() {
        let world = FakeMeleeWorld()
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)

        runtime.acceptFrame(MeleeIntent(block: true))

        #expect(world.raised.contains(CombatGraphNames.weaponDraw))
    }

    @Test func aDrawnBowsAttackButtonStartsNoMeleeSwing() {
        let world = FakeMeleeWorld()
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)
        runtime.weapon = MeleeWeaponProfile(damage: 6, reach: 1, handType: .bow)
        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true))
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)
        let raised = world.raised.count
        runtime.acceptFrame(MeleeIntent(attack: false, attackHeld: false))
        for _ in 0 ..< 60 {
            runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true, deltaTime: 1.0 / 60))
        }
        #expect(world.raised.count == raised, "a bow press raised \(world.raised.suffix(3))")
        #expect(runtime.state.swingID == 0)
    }
}
