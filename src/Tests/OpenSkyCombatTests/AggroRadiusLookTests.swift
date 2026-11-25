// A warning actor's head and aim, and a stranger NPC as its target
// (docs/engine/aggro-radius.md).

import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerceptionInterface
import simd
import Testing

@MainActor
struct AggroRadiusLookTests {
    private typealias Fixture = CombatLoopFixture

    private let radius = AggroRadius(warn: 2048, warnOrAttack: 1024, attack: 256)

    @Test func theHeadStaysOnTheTargetForFiveSecondsAfterItLeaves() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: .zero)

        Fixture.run(runtime, seconds: 0.5)
        #expect(world.looks[Fixture.opponent] == AggroLook(target: .player, seconds: nil))
        #expect(world.turns[Fixture.opponent] == .zero)

        world.player = MeleeAttacker(key: .player, feet: SIMD3(-5000, 0, 0), facing: 0)
        Fixture.run(runtime, seconds: 0.5)
        #expect(world.looks[Fixture.opponent] == AggroLook(
            target: .player, seconds: CombatLoopRuntime.aggroLookSeconds
        ))
    }

    @Test func anArcherTurnsToWhereItsArrowWouldMeetTheTarget() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: .zero)
        world.weapons[Fixture.opponent] = MeleeWeaponProfile(damage: 6, reach: 1, handType: .bow)
        world.aimPoints[Fixture.opponent] = SIMD3(0, 40, 0)

        Fixture.run(runtime, seconds: 0.5)
        #expect(world.turns[Fixture.opponent] == SIMD3(0, 40, 0))

        world.weapons[Fixture.opponent] = MeleeWeaponProfile(damage: 6, reach: 1, handType: .staff)
        Fixture.run(runtime, seconds: 0.5)
        #expect(world.turns[Fixture.opponent] == .zero)
    }

    /// Two NPCs that are both strangers to the player: one warns the other, then fights it.
    @Test func aStrangerNPCIsWarnedThenFought() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        let stranger = Fixture.second
        world.player = MeleeAttacker(key: .player, feet: SIMD3(-9000, 0, 0), facing: 0)
        world.actors.append(CombatActorObservation(key: stranger, feet: SIMD3(1000, 0, 0)))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: SIMD3(1000, 0, 0))
        world.pairReactions[CombatFoePair(observer: Fixture.opponent, target: stranger)] = .neutral

        Fixture.run(runtime, seconds: 1)
        #expect(runtime.aggroWatches[Fixture.opponent]?.target == stranger)
        #expect(world.looks[Fixture.opponent] == AggroLook(target: stranger, seconds: nil))

        Fixture.run(runtime, seconds: AggroRadiusRule.warnInterval * 4)
        #expect(runtime.foePairs.contains(CombatFoePair(
            observer: Fixture.opponent,
            target: stranger
        )))
        #expect(runtime.hostility(of: Fixture.opponent) == .neutral)
    }

    @Test func aFriendlyNPCIsNotWarned() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        let friend = Fixture.second
        world.player = MeleeAttacker(key: .player, feet: SIMD3(-9000, 0, 0), facing: 0)
        world.actors.append(CombatActorObservation(key: friend, feet: SIMD3(1000, 0, 0)))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: SIMD3(1000, 0, 0))
        world.pairReactions[CombatFoePair(observer: Fixture.opponent, target: friend)] = .friend

        Fixture.run(runtime, seconds: 1)
        #expect(runtime.aggroWatches[Fixture.opponent] == nil)
    }
}
