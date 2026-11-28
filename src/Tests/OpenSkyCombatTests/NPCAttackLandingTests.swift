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
        #expect(world.knockdownStaggerMults == [1])
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

    /// The damage the first blow deals. With `movesBehind`, the player steps behind the
    /// opponent once the swing is chosen, which is the pick for a race attack and the
    /// windup for a plain swing.
    private static func firstBlow(attack: RaceAttack.Properties?, movesBehind: Bool) -> Float? {
        let (runtime, world) = CombatLoopFixture.session()
        world.actors = [CombatActorObservation(
            key: CombatLoopFixture.opponent, feet: CombatLoopFixture.closeFeet,
            heading: -.pi / 2, name: "Opponent"
        )]
        world.turnsActors = false
        if let attack {
            world.raceAttacks[CombatLoopFixture.opponent] = [
                RaceAttack(properties: attack, event: "attackStart")
            ]
        }
        CombatLoopFixture.engage(runtime, world)
        func chosen() -> Bool {
            attack == nil ? runtime.behaviors[CombatLoopFixture.opponent]?.phase == .windup
                : runtime.pickedAttacks[CombatLoopFixture.opponent] != nil
        }
        var elapsed: Float = 0
        while !chosen(), elapsed < 10 {
            CombatLoopFixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
        }
        if movesBehind {
            world.player = MeleeAttacker(key: .player, feet: SIMD3(120, 0, 0), facing: 0)
        }
        while runtime.behaviors[CombatLoopFixture.opponent]?.contactCount ?? 0 < 1, elapsed < 10 {
            CombatLoopFixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
        }
        return world.damage[.player]
    }

    /// A swing whose target stepped out of its cone after the pick misses at contact.
    @Test func aBlowLandsOnlyInsideTheStrikeAngleAtContact() {
        var data = RaceAttack.Properties()
        data.attackChance = 1
        data.strikeAngle = 30
        #expect(Self.firstBlow(attack: data, movesBehind: false) != nil)
        #expect(Self.firstBlow(attack: data, movesBehind: true) == nil)
    }

    /// A swing without attack data lands only inside the default 35 degree cone.
    @Test func aPlainSwingLandsOnlyInsideTheDefaultCone() {
        #expect(Self.firstBlow(attack: nil, movesBehind: false) != nil)
        #expect(Self.firstBlow(attack: nil, movesBehind: true) == nil)
    }
}
