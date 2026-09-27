// Hit volumes, reach and target filtering (issue #195, roadmap item 15.4,
// scope points 4 and 5).
//
// Two of the issue's acceptance clauses live here: a swing through two
// overlapping targets hits each once, and the reach a swing gets is
// `fCombatDistance * scale * WEAP.reach`. The rest pin the filters — never the
// attacker, at most one hit per swing per target — and the geometry the
// closest-approach solver has to get right for a capsule sweep to mean
// anything.

@testable import opensky
import simd
import Testing

struct MeleeHitDetectionTests {
    // MARK: - Reach

    @Test func reachIsCombatDistanceTimesScaleTimesWeaponReach() {
        let settings = CombatSettings.synthetic
        let weapon = MeleeWeaponProfile(damage: 10, reach: 0.7)

        let reach = MeleeSwing.reach(weapon: weapon, settings: settings, actorScale: 1.2)

        #expect(abs(reach - 141 * 1.2 * 0.7) < 0.001)
    }

    @Test func aBrokenScaleOrReachFallsBackToOneRatherThanToZero() {
        let settings = CombatSettings.synthetic
        let broken = MeleeWeaponProfile(damage: 10, reach: 0)

        #expect(MeleeSwing.reach(weapon: broken, settings: settings) == 141)
        #expect(
            MeleeSwing.reach(
                weapon: .unarmed, settings: settings, actorScale: .nan
            ) == 141
        )
    }

    // MARK: - Hits

    @Test func aSwingThroughTwoOverlappingTargetsHitsEachOnce() {
        let swing = Self.swing(reach: 200)
        let targets = [
            Self.target(1, at: SIMD3(80, 0, 0)),
            // Overlapping the first: the capsules are 24 apart with a radius
            // of 24 each, so they interpenetrate.
            Self.target(2, at: SIMD3(96, 0, 0))
        ]

        let hits = MeleeHitDetector.hits(swing: swing, targets: targets, attacker: Self.attacker)

        #expect(hits.count == 2)
        #expect(Set(hits.map(\.target)).count == 2)
        // Nearest first.
        #expect(hits[0].target == targets[0].key)
    }

    @Test func aSwingNeverHitsItsOwnAttacker() {
        let swing = Self.swing(reach: 200)
        let targets = [
            MeleeTarget(key: Self.attacker, feet: SIMD3<Float>()),
            Self.target(1, at: SIMD3(80, 0, 0))
        ]

        let hits = MeleeHitDetector.hits(swing: swing, targets: targets, attacker: Self.attacker)

        #expect(hits.map(\.target) == [targets[1].key])
    }

    @Test func aTargetAlreadyHitThisSwingIsSkipped() {
        let swing = Self.swing(reach: 200)
        let target = Self.target(1, at: SIMD3(80, 0, 0))

        let first = MeleeHitDetector.hits(
            swing: swing, targets: [target], attacker: Self.attacker
        )
        let second = MeleeHitDetector.hits(
            swing: swing,
            targets: [target],
            attacker: Self.attacker,
            alreadyHit: Set(first.map(\.target))
        )

        #expect(first.count == 1)
        #expect(second.isEmpty)
    }

    @Test func aTargetBeyondReachIsMissed() {
        // 60 units of reach, target 400 units away.
        let hits = MeleeHitDetector.hits(
            swing: Self.swing(reach: 60),
            targets: [Self.target(1, at: SIMD3(400, 0, 0))],
            attacker: Self.attacker
        )
        #expect(hits.isEmpty)
    }

    @Test func aTargetBehindTheAttackerIsMissed() {
        let hits = MeleeHitDetector.hits(
            swing: Self.swing(reach: 200),
            targets: [Self.target(1, at: SIMD3(-100, 0, 0))],
            attacker: Self.attacker
        )
        #expect(hits.isEmpty)
    }

    @Test func aTargetOnAFarHigherLedgeIsMissed() {
        // The blade's vertical half-extent is a quarter of the capsule height,
        // so a target standing 300 units up is out of a horizontal swing.
        let hits = MeleeHitDetector.hits(
            swing: Self.swing(reach: 200),
            targets: [Self.target(1, at: SIMD3(80, 0, 300))],
            attacker: Self.attacker
        )
        #expect(hits.isEmpty)
    }

    @Test func hitOrderIsDeterministicForCoincidentTargets() {
        let swing = Self.swing(reach: 200)
        let coincident = [
            Self.target(9, at: SIMD3(80, 0, 0)),
            Self.target(2, at: SIMD3(80, 0, 0))
        ]

        let hits = MeleeHitDetector.hits(
            swing: swing, targets: coincident, attacker: Self.attacker
        )
        let reversed = MeleeHitDetector.hits(
            swing: swing, targets: coincident.reversed(), attacker: Self.attacker
        )

        #expect(hits.map(\.target) == reversed.map(\.target))
        // Ties break on the lower reference.
        #expect(hits[0].target == coincident[1].key)
    }

    // MARK: - Geometry

    @Test func closestApproachOfCrossingSegmentsIsTheCrossingPoint() {
        let approach = MeleeHitDetector.closestApproach(
            first: (SIMD3(-10, 0, 0), SIMD3(10, 0, 0)),
            second: (SIMD3(0, -10, 5), SIMD3(0, 10, 5))
        )
        #expect(simd_distance(approach.onFirst, SIMD3<Float>()) < 0.001)
        #expect(simd_distance(approach.onSecond, SIMD3<Float>(0, 0, 5)) < 0.001)
    }

    @Test func closestApproachOfParallelSegmentsLandsOnAnEndPoint() {
        let approach = MeleeHitDetector.closestApproach(
            first: (SIMD3(0, 0, 0), SIMD3(10, 0, 0)),
            second: (SIMD3(20, 0, 0), SIMD3(30, 0, 0))
        )
        #expect(simd_distance(approach.onFirst, SIMD3<Float>(10, 0, 0)) < 0.001)
        #expect(simd_distance(approach.onSecond, SIMD3<Float>(20, 0, 0)) < 0.001)
    }

    @Test func closestApproachOfDegenerateSegmentsIsThePointPair() {
        let point = SIMD3<Float>(3, 4, 5)
        let approach = MeleeHitDetector.closestApproach(
            first: (point, point),
            second: (SIMD3<Float>(), SIMD3<Float>())
        )
        #expect(approach.onFirst == point)
        #expect(approach.onSecond == SIMD3<Float>())
    }

    // MARK: - Fixture

    private static let attacker = ReferenceKey.generated(0)

    /// A swing from the origin along +X, which is yaw 0.
    private static func swing(reach: Float) -> ShapeSweepQuery {
        MeleeSwing.volume(
            feet: SIMD3<Float>(),
            capsule: .standard,
            facing: 0,
            reach: reach
        )
    }

    private static func target(_ id: UInt64, at feet: SIMD3<Float>) -> MeleeTarget {
        MeleeTarget(key: .generated(id), feet: feet)
    }
}
