// An NPC's picked attack reaches its blow: the power kind, the attack event, and the
// knockdown. Rules: docs/engine/attack-data.md.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import Testing

@MainActor
struct NPCAttackLandingTests {
    private static func attack(_ event: String, knockdown: Float) -> NPCAttack {
        var data = RaceAttack.Properties()
        data.flags = .powerAttack
        data.knockdown = knockdown
        data.attackChance = 1
        return NPCAttack(event: event, data: data)
    }

    @Test func aPickedPowerAttackSetsTheBlowKindAndEvent() {
        let blow = CombatNPCBlowLanding.blow(
            by: CombatLoopFixture.opponent, weapon: .unarmed,
            attack: Self.attack("attackPowerStartForward", knockdown: 0)
        )
        #expect(blow.kind == .power)
        #expect(blow.attackEvent == "attackPowerStartForward")
        let plain = CombatNPCBlowLanding.blow(by: CombatLoopFixture.opponent, weapon: .unarmed)
        #expect(plain.kind == .normal)
        #expect(plain.attackEvent == nil)
    }

    @Test func aLandedAttackWithKnockdownPushesTheTargetDown() {
        let world = FakeCombatWorld()
        let landing = CombatNPCBlowLanding(
            world: world, settings: .synthetic, skillUses: .vanilla, staggers: .vanilla
        )
        var random = ConditionRandom(seed: 3)
        _ = landing.land(
            from: (CombatLoopFixture.opponent, .zero),
            weapon: (.unarmed, Self.attack("attackPowerStart", knockdown: 40)),
            to: .player, random: &random
        )
        #expect(world.knockdowns.map(\.magnitude) == [40])
        _ = landing.land(
            from: (CombatLoopFixture.opponent, .zero),
            weapon: (.unarmed, Self.attack("attackPowerStart", knockdown: 0)),
            to: .player, random: &random
        )
        #expect(world.knockdowns.count == 1)
    }

    @Test func anEngagedActorSwingsWithItsRaceAttack() {
        let (runtime, world) = CombatLoopFixture.session()
        var data = RaceAttack.Properties()
        data.attackChance = 1
        data.strikeAngle = 180
        data.knockdown = 25
        world.raceAttacks[CombatLoopFixture.opponent] = [
            RaceAttack(properties: data, event: "attackStart")
        ]
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: CombatLoopFixture.cycleSeconds * 2)
        #expect(runtime.attackUses[CombatLoopFixture.opponent]?["attackstart"] != nil)
        #expect(world.knockdowns.first?.magnitude == 25)
    }
}
