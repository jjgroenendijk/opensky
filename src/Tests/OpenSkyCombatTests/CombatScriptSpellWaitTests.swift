// An NPC that casts a spell with a Script effect waits before any such spell again.

@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import Testing

@MainActor
struct CombatScriptSpellWaitTests {
    private static let caster = ReferenceKey.generated(1)

    @Test func aScriptSpellMakesItsCasterWaitForAnyOtherScriptSpell() {
        let world = FakeCoordinatorWorld()
        var scripted = CombatSpellOption(spell: .generated(3), cost: 10, range: 1000)
        scripted.scriptDelay = 2
        let plain = CombatSpellOption(spell: .generated(4), cost: 10, range: 1000)
        let candidates = [scripted, plain].map {
            CombatSpellCandidate(
                option: $0, isSpell: true, targetsSelf: false, isDeliverable: true,
                isHostile: true, fitsHand: true
            )
        }
        world.casting[Self.caster] = CombatCastingFacts(magicka: 50, spells: candidates)
        let coordinator = CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
        #expect(coordinator.loopWorld.combatCasting(of: Self.caster).options.count == 2)
        #expect(coordinator.loopWorld.releaseCombatCast(scripted, by: Self.caster))
        #expect(coordinator.loopWorld.combatCasting(of: Self.caster).options.map(\.spell)
            == [.generated(4)])
        _ = coordinator.advanceLoop(by: 1.5)
        #expect(coordinator.loopWorld.combatCasting(of: Self.caster).options.count == 1)
        _ = coordinator.advanceLoop(by: 1)
        #expect(coordinator.loopWorld.combatCasting(of: Self.caster).options.count == 2)
    }
}
