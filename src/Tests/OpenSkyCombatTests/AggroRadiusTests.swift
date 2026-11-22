// The aggro radius: the zones, the warn timer, and the loop turning a warned actor
// hostile (docs/engine/combat-behavior.md#aggro-radius).

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
struct AggroRadiusTests {
    private typealias Fixture = CombatLoopFixture

    private let radius = AggroRadius(warn: 2048, warnOrAttack: 1024, attack: 256)

    @Test func theInnermostZoneThatHoldsTheDistanceWins() {
        #expect(AggroRadiusRule.zone(distance: 3000, radius: radius) == .outside)
        #expect(AggroRadiusRule.zone(distance: 2000, radius: radius) == .warn)
        #expect(AggroRadiusRule.zone(distance: 1000, radius: radius) == .warnOrAttack)
        #expect(AggroRadiusRule.zone(distance: 100, radius: radius) == .attack)
        #expect(AggroRadiusRule.zone(distance: .nan, radius: radius) == .outside)
        let off = AggroRadius(warn: 0, warnOrAttack: 0, attack: 0)
        #expect(AggroRadiusRule.zone(distance: 0, radius: off) == .outside)
    }

    @Test func theAttackZoneAttacksAtOnceAndTheMiddleZoneAfterThreeWarnings() {
        let first = AggroRadiusRule.advance(AggroWatch(), zone: .attack, by: 0.1)
        #expect(first.outcome == .attacks)
        var watch = AggroWatch()
        for _ in 0 ..< 3 {
            let step = AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 5)
            #expect(step.outcome == .warns)
            watch = step.watch
        }
        #expect(watch.warnings == 3)
        #expect(AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 4).outcome == .waits)
        #expect(AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 5).outcome == .attacks)
    }

    @Test func aWarningCountsOnlyInTheMiddleZoneAndLeavingClearsTheWatch() {
        var watch = AggroWatch()
        for _ in 0 ..< 6 {
            let step = AggroRadiusRule.advance(watch, zone: .warn, by: 5)
            #expect(step.outcome == .warns)
            watch = step.watch
        }
        #expect(watch.warnings == 0)
        watch = AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 5).watch
        #expect(watch.warnings == 1)
        #expect(AggroRadiusRule.advance(watch, zone: .outside, by: 1).watch == AggroWatch())
    }

    @Test func theLineNeedsTheActorToFaceItsTargetWithinTwentyDegrees() {
        let target = SIMD3<Float>(100, 0, 0)
        #expect(AggroRadiusRule.faces(target, from: .zero, yaw: 0))
        #expect(AggroRadiusRule.faces(target, from: .zero, yaw: 19 * .pi / 180))
        #expect(!AggroRadiusRule.faces(target, from: .zero, yaw: 21 * .pi / 180))
        #expect(!AggroRadiusRule.faces(target, from: .zero, yaw: .pi))
        #expect(AggroRadiusRule.faces(.zero, from: .zero, yaw: 2))
    }

    /// The actor at +X looks along -X at the player: it draws, says a line at each
    /// interval, and sheathes when the player leaves.
    @Test func aWarningActorDrawsSpeaksAndSheathesWhenTheTargetLeaves() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.actors = [CombatActorObservation(
            key: Fixture.opponent, feet: SIMD3(500, 0, 0), heading: -.pi / 2
        )]
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: .zero)

        Fixture.run(runtime, seconds: AggroRadiusRule.warnInterval + 0.5)
        #expect(world.raised.contains(AggroRadiusRule.drawEvent))
        #expect(world.warningLines == [[Fixture.opponent, .player]])
        #expect(runtime.aggroWatches[Fixture.opponent]?.warnings == 1)
        #expect(runtime.aggroWatches[Fixture.opponent]?.target == .player)

        world.player = MeleeAttacker(key: .player, feet: SIMD3(-5000, 0, 0), facing: 0)
        Fixture.run(runtime, seconds: 0.5)
        #expect(runtime.aggroWatches.isEmpty)
        #expect(world.raised.contains(AggroRadiusRule.sheatheEvent))
    }

    @Test func anActorThatFacesAwayOrOnlySuspectsGivesItsWarningInSilence() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: .zero)
        Fixture.run(runtime, seconds: AggroRadiusRule.warnInterval + 0.5)
        #expect(world.warningLines.isEmpty)
        #expect(runtime.aggroWatches[Fixture.opponent]?.warnings == 1)
    }

    /// A cowardly actor is provoked like any other, and its Confidence then makes it flee.
    @Test func aCowardlyActorFleesWhereAnotherWouldAttack() {
        let (runtime, world) = Fixture.session(feet: SIMD3(100, 0, 0))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: .zero)
        world.temperaments[Fixture.opponent] = CombatTemperament(confidence: 0, strengthRatio: 1)

        Fixture.run(runtime, seconds: 1)
        #expect(runtime.hostility(of: Fixture.opponent) == .hostile)
        #expect(runtime.phase(of: Fixture.opponent) == .fleeing)
    }

    /// The player is far away, but a teammate of the player stands near the actor.
    @Test func aTeammateOfThePlayerIsWarnedAndAttackedToo() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        let teammate = ReferenceKey.generated(2)
        world.actors.append(CombatActorObservation(key: teammate, feet: SIMD3(1000, 0, 0)))
        world.player = MeleeAttacker(key: .player, feet: SIMD3(-9000, 0, 0), facing: 0)
        runtime.command(teammate, by: .player)
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = .detected(at: SIMD3(1000, 0, 0))

        Fixture.run(runtime, seconds: 1)
        #expect(runtime.aggroWatches[Fixture.opponent]?.target == teammate)
        #expect(runtime.aggroZone(of: Fixture.opponent) == .warnOrAttack)
        #expect(runtime.aggroWatches[teammate] == nil)
        Fixture.run(runtime, seconds: AggroRadiusRule.warnInterval * 4)
        #expect(runtime.hostility(of: Fixture.opponent) == .hostile)
    }

    @Test func aNeutralActorThatDetectsThePlayerNearbyWarnsThenAttacks() {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.aggroRadii[Fixture.opponent] = radius
        world.awareness[Fixture.opponent] = CombatAwareness(
            state: .detected, lastKnownPosition: nil
        )

        Fixture.run(runtime, seconds: 1)
        #expect(runtime.aggroZone(of: Fixture.opponent) == .warnOrAttack)
        #expect(runtime.hostility(of: Fixture.opponent) == .neutral)

        Fixture.run(runtime, seconds: AggroRadiusRule.warnInterval * 4)
        #expect(runtime.hostility(of: Fixture.opponent) == .hostile)
        #expect(runtime.aggroZone(of: Fixture.opponent) == nil)
    }

    @Test func aFriendOrAnActorThatDoesNotDetectThePlayerNeverWarns() {
        let (runtime, world) = Fixture.session(feet: SIMD3(100, 0, 0))
        world.aggroRadii[Fixture.opponent] = radius

        Fixture.run(runtime, seconds: 1)
        #expect(runtime.aggroZone(of: Fixture.opponent) == nil)

        world.awareness[Fixture.opponent] = CombatAwareness(
            state: .detected, lastKnownPosition: nil
        )
        world.reactions[Fixture.opponent] = .friend
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.hostility(of: Fixture.opponent) == .neutral)
    }
}
