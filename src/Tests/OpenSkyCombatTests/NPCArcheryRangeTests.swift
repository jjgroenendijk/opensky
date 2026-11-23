// Where an NPC archer stands and when it shoots, and how a weak bow shot flies.
// See docs/engine/archery.md#npc-archers and docs/engine/archery.md#damage.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyGameData
import simd
import Testing

@MainActor
struct NPCArcheryRangeTests {
    private typealias Fixture = CombatBehaviorFixture

    private static func style(offense: Float, defense: Float) -> CombatStyleTuning {
        CombatStyleTuning(
            offensiveMultiplier: offense, defensiveMultiplier: defense,
            meleeScoreMultiplier: 1, magicScoreMultiplier: 1
        )
    }

    @Test func theStyleSetsThePreferredDistance() {
        #expect(NPCArcheryRange
            .preferredDistance(style: Self.style(offense: 0.5, defense: 0.5)) == 1280)
        #expect(NPCArcheryRange
            .preferredDistance(style: Self.style(offense: 1, defense: 0)) == 1024)
        #expect(NPCArcheryRange
            .preferredDistance(style: Self.style(offense: 0, defense: 1)) == 1536)
        #expect(NPCArcheryRange
            .preferredDistance(style: Self.style(offense: 0.25, defense: 0.75)) == 1408)
    }

    @Test func theRangeAddsTheRadiusAndCapsTheLongestShot() {
        let range = NPCArcheryRange(style: .neutral, radius: 20)

        #expect(range.longest == 4096)
        #expect(range.minimum == 276)
        #expect(range.preferred == 1300)
        #expect(range.farthest == 1812)
        #expect(abs(range.backOffDistance - 207) < 0.001)
    }

    @Test func aShortShotIsNotRanged() {
        let range = NPCArcheryRange(style: .neutral, radius: 0, ballisticRange: 1000)

        #expect(range.longest == 900)
        #expect(range.minimum == 0)
        #expect(range.farthest == 900)
    }

    @Test func theShotChanceGrowsWithTheTimeSinceTheLastShot() {
        let range = NPCArcheryRange(style: Self.style(offense: 0.5, defense: 0.5), radius: 0)

        #expect(abs(range.shotChance(secondsSinceShot: 0) - 0.525) < 0.0001)
        #expect(abs(range.shotChance(secondsSinceShot: 5) - 0.65625) < 0.0001)
        #expect(abs(range.shotChance(secondsSinceShot: 30) - 0.7875) < 0.0001)
    }

    @Test func aBolderStyleHoldsTheDrawShorter() {
        let timid = NPCArcheryRange(style: Self.style(offense: 0, defense: 0.5), radius: 0)
        let bold = NPCArcheryRange(style: Self.style(offense: 1, defense: 0.5), radius: 0)

        #expect(timid.holdCeiling(distance: 1000) == 1.5)
        #expect(bold.holdCeiling(distance: 1000) == 0.25)
        #expect(timid.holdCeiling(distance: 200) == 0.25)
        #expect(timid.hold(distance: 1000, unit: 0) == 0.1)
        #expect(abs(timid.hold(distance: 1000, unit: 0.5) - 0.8) < 0.0001)
    }

    private static func archer(distance: Float) -> CombatBehaviorInputs {
        var inputs = Fixture.inputs(distance: distance)
        let range = NPCArcheryRange(style: .neutral, radius: 0)
        inputs.archery = range
        inputs.reach = range.preferred + Fixture.unblocking.reachSlack
        return inputs
    }

    @Test func anArcherStopsAtItsPreferredDistanceAndShoots() {
        var machine = Fixture.machine(settings: Fixture.unblocking)
        let far = Fixture.run(&machine, seconds: 1, inputs: Self.archer(distance: 3000))
        #expect(machine.phase == .approaching)
        #expect(far.contains { $0.command != nil })

        Fixture.run(&machine, until: { $0.phase == .spacing }, inputs: Self.archer(distance: 1200))
        #expect(machine.phase == .spacing)
        let shots = Fixture.run(&machine, seconds: 20, inputs: Self.archer(distance: 1700))
        #expect(shots.contains { $0.reachedContact })
        #expect(machine.phase != .approaching)
    }

    @Test func anArcherBacksAwayFromATargetTooClose() {
        var machine = Fixture.machine(settings: Fixture.unblocking)
        Fixture.run(&machine, until: { $0.phase == .spacing }, inputs: Self.archer(distance: 1200))

        let steps = Fixture.run(&machine, seconds: 1, inputs: Self.archer(distance: 100))

        #expect(steps.contains {
            if case .flee = $0.command {
                true
            } else {
                false
            }
        })
        #expect(!steps.contains { $0.startedAttack })
    }

    @Test func aWeakShotLeavesSlowerAndFallsFaster() {
        let weak = ArcheryDamageResult(bowDamage: 1, arrowDamage: 1, drawFraction: 0.35, applied: 1)
        let full = ArcheryDamageResult(bowDamage: 1, arrowDamage: 1, drawFraction: 1, applied: 1)

        #expect(abs(weak.launchSpeedShare - 0.2) < 0.0001)
        #expect(full.launchSpeedShare == 1)
        #expect(abs(weak.gravity(recordGravity: 0.3) - 1.2425) < 0.0001)
        #expect(abs(full.gravity(recordGravity: 0.3) - 0.3) < 0.0001)

        let shot = ProjectileShot.arrow(
            profile: ProjectileProfile(
                speed: 1000,
                gravityFactor: 0.3,
                range: 4000,
                collisionRadius: 2
            ),
            damage: weak, weapon: nil, ammunition: nil
        )
        #expect(abs(shot.flightProfile.gravityFactor - 1.2425) < 0.0001)
        #expect(abs(shot.speedScale - 0.2) < 0.0001)
    }
}
