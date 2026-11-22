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
        #expect(first.attacks)
        var watch = AggroWatch()
        var attacks = false
        for _ in 0 ..< 3 {
            (watch, attacks) = AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 5)
            #expect(!attacks)
        }
        #expect(watch.warnings == 3)
        (watch, attacks) = AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 5)
        #expect(attacks)
    }

    @Test func aWarningCountsOnlyInTheMiddleZoneAndLeavingClearsTheWatch() {
        var watch = AggroWatch()
        for _ in 0 ..< 6 {
            let step = AggroRadiusRule.advance(watch, zone: .warn, by: 5)
            #expect(!step.attacks)
            watch = step.watch
        }
        #expect(watch.warnings == 0)
        watch = AggroRadiusRule.advance(watch, zone: .warnOrAttack, by: 5).watch
        #expect(watch.warnings == 1)
        #expect(AggroRadiusRule.advance(watch, zone: .outside, by: 1).watch == AggroWatch())
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
