// A press of either attack button with the weapon sheathed only draws it.
// See docs/engine/attack-input.md#each-button.

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
}
