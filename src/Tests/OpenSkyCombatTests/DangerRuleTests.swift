// Danger avoidance: what counts as a threat, the score, and the sidestep
// (docs/engine/danger-avoidance.md).

import OpenSkyCombatInterface
import simd
import Testing

struct DangerRuleTests {
    private let settings = DangerSettings.vanilla
    private let actor = DangerActor(feet: SIMD3(500, 0, 0), radius: 20, health: 100, speed: 370)

    private func fireball(at position: SIMD3<Float> = .zero) -> DangerThreat {
        DangerThreat(
            id: 1, position: position, velocity: SIMD3(1000, 0, 0), damage: 40, radius: 150
        )
    }

    /// The page's example: damage 20 and radius 100 give about 87 units at 5 damage.
    @Test func theEffectiveRadiusFollowsTheDocumentedExample() {
        let radius = DangerRule.effectiveRadius(damage: 20, radius: 100, threshold: 5)
        #expect(abs(radius - 86.6) < 0.1)
        #expect(DangerRule.effectiveRadius(damage: 4, radius: 100, threshold: 5) == 0)
    }

    @Test func aSmallExplosionIsNoThreat() {
        func threat(damage: Float, radius: Float) -> DangerThreat? {
            DangerRule.threat(
                id: 1, source: nil, motion: (.zero, .zero), explosion: (damage, radius)
            )
        }
        #expect(threat(damage: 4, radius: 500) == nil)
        #expect(threat(damage: 20, radius: 30) == nil)
        #expect(threat(damage: 20, radius: 100)?.radius ?? 0 > 86)
    }

    @Test func aThreatCountsOnlyForAnActorAheadOfItInItsSweep() {
        let threat = fireball()
        #expect(DangerRule.counts(threat, at: actor.feet, radius: 20, seconds: 2))
        #expect(!DangerRule.counts(threat, at: SIMD3(-100, 0, 0), radius: 20, seconds: 2))
        #expect(!DangerRule.counts(threat, at: SIMD3(500, 400, 0), radius: 20, seconds: 2))
        #expect(!DangerRule.counts(threat, at: actor.feet, radius: 20, seconds: 0.1))
    }

    @Test func theScoreIsDamageOverHealth() {
        #expect(DangerRule.score([fireball()], for: actor, seconds: 2) == 0.4)
        #expect(DangerRule.score([], for: actor, seconds: 2) == 0)
    }

    @Test func theEscapePointsAreAtARightAngleOnTheActorsOwnSideFirst() {
        var beside = actor
        beside.feet = SIMD3(500, 50, 0)
        let points = DangerRule.escapePoints(
            from: fireball(), for: beside, settings: settings, coin: false
        )
        // Radius 150, less the offset 50, plus the actor's 20, plus the buffer 64.
        #expect(Self.isNear(points.first, SIMD3(500, 234, 0)))
        #expect(Self.isNear(points.last, SIMD3(500, -234, 0)))
        let onLine = DangerRule.escapePoints(
            from: fireball(), for: actor, settings: settings, coin: true
        )
        #expect(Self.isNear(onLine.first, SIMD3(500, 234, 0)))
    }

    @Test func aFighterSidestepsAThreatItHasTimeFor() throws {
        let dodge = try #require(DangerRule.dodge(
            from: [fireball()], for: actor, settings: (settings, true)
        ) { _ in true })
        #expect(Self.isNear(dodge.point, SIMD3(500, 234, 0)))
        #expect(dodge.threat == 1)
        #expect(abs(dodge.seconds - 234.0 / 370) < 0.001)
    }

    @Test func noSidestepWithoutAThreatOrWithoutTime() {
        let none = DangerRule.dodge(
            from: [], for: actor, settings: (settings, true)
        ) { _ in true }
        #expect(none == nil)
        // The blast reaches the actor inside its reaction time.
        var moving = actor
        moving.isMoving = true
        let late = DangerRule.dodge(
            from: [fireball(at: SIMD3(400, 0, 0))], for: moving, settings: (settings, true)
        ) { _ in true }
        #expect(late == nil)
    }

    @Test func aPointTheNavmeshDoesNotReachIsSkipped() throws {
        let dodge = try #require(DangerRule.dodge(
            from: [fireball()], for: actor, settings: (settings, true)
        ) { $0.y < 0 })
        #expect(Self.isNear(dodge.point, SIMD3(500, -234, 0)))
        let walled = DangerRule.dodge(
            from: [fireball()], for: actor, settings: (settings, true)
        ) { _ in false }
        #expect(walled == nil)
    }

    @Test func theChanceIsTheStylesOwnValueAtTheGameSettings() {
        #expect(settings.chance(style: 0.2) == 0.2)
    }

    /// A rune waits beside the middle of the path, away from both of its ends.
    @Test func aMovingFighterIsScoredAlongItsPath() throws {
        let rune = DangerThreat(id: 7, position: SIMD3(800, 0, 0), damage: 50, radius: 60)
        #expect(DangerRule.aheadScore([rune], for: actor, seconds: 2) == 0)
        var walker = actor
        walker.isMoving = true
        walker.goal = SIMD3(1100, 0, 0)
        #expect(DangerRule.aheadScore([rune], for: walker, seconds: 2) == 0.5)
        let dodge = try #require(DangerRule.dodge(
            from: [rune], for: walker, settings: (settings, true)
        ) { _ in true })
        #expect(dodge.threat == 7)
        #expect(abs(dodge.point.y) > 100)
        // A path that ends before the rune is kept.
        walker.goal = SIMD3(600, 0, 0)
        #expect(DangerRule.aheadScore([rune], for: walker, seconds: 2) == 0)
        #expect(DangerRule.dodge(from: [rune], for: walker, settings: (settings, true)) { _ in
            true
        } == nil)
        // An actor at its goal counts as standing.
        walker.goal = walker.feet
        #expect(DangerRule.aheadScore([rune], for: walker, seconds: 2) == 0)
    }

    private static func isNear(_ point: SIMD3<Float>?, _ expected: SIMD3<Float>) -> Bool {
        guard let point else { return false }
        return simd_distance(point, expected) < 0.01
    }
}
