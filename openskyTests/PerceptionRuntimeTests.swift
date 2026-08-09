// The perception pass end to end (issue #202, roadmap item 16.6): the wall, the
// cone, the accumulation rates, the decay schedule, the investigate position,
// the caps and the overlay.
//
// The acceptance gate for 16.6 is exactly these behaviours over synthetic
// geometry, so each `@Test` below names one of its clauses.

@testable import opensky
import simd
import Testing

@MainActor
struct PerceptionRuntimeTests {
    /// Internal rather than private: `private` is per file, and the surface
    /// half of these tests lives in `PerceptionRuntimeSurfaceTests`.
    let settings = DetectionSettings.synthetic

    /// Advances `runtime` by whole fixed steps.
    func advance(_ runtime: PerceptionRuntime, steps: Int) {
        for _ in 0 ..< steps {
            runtime.advance(by: PerceptionRuntime.fixedStepSeconds)
        }
    }

    // MARK: - Sight

    @Test func aTargetBehindAWallIsNotSeen() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(400, 0, 0))],
            blocked: PerceptionFixture.wall(atX: 200)
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 300)

        let pair = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(!pair.hasLineOfSight)
        #expect(pair.isInViewCone)
        #expect(pair.breakdown.visualFactor == 0)
        #expect(pair.state == .unaware)
        #expect(pair.level == 0)
        // The same pose without the wall is detected outright, so the wall is
        // what made the difference rather than the distance.
        world.blocked = { _, _ in false }
        advance(runtime, steps: 300)
        #expect(runtime.state(observer: PerceptionFixture.guardKey, target: .player)
            .state == .detected)
    }

    @Test func aTargetOutsideTheConeIsNotSeenButCanStillBeHeard() {
        // The observer faces +X; the target stands behind it on -X.
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0), facing: 0)],
            targets: [PerceptionFixture.target(feet: SIMD3(-300, 0, 0), gait: .sprint)]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 60)

        let pair = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(!pair.isInViewCone)
        #expect(pair.hasLineOfSight)
        #expect(pair.breakdown.visualFactor == 0)
        // Sprinting behind a guard's back is loud enough to notice, which is
        // the hearing half of the pass doing the work on its own.
        #expect(pair.breakdown.soundFactor > 0)
        #expect(pair.state != .unaware)
    }

    @Test func theConeIsAYawWedgeAboutTheObserverFacing() {
        let observer = PerceptionFixture.observer(feet: SIMD3(0, 0, 0), facing: 0)
        let cosine = settings.viewConeCosine
        func inCone(_ position: SIMD3<Float>) -> Bool {
            PerceptionSight.isInViewCone(
                observer: observer,
                target: PerceptionFixture.target(feet: position),
                cosine: cosine
            )
        }
        #expect(inCone(SIMD3(100, 0, 0)))
        #expect(inCone(SIMD3(100, 100, 0)))
        #expect(!inCone(SIMD3(-100, 0, 0)))
        #expect(!inCone(SIMD3(-100, 100, 0)))
        // Directly above counts as inside: it has no horizontal direction to be
        // outside in.
        #expect(inCone(SIMD3(0, 0, 200)))
    }

    // MARK: - Accumulation and decay

    @Test func sneakingChangesTheAccumulationRateAgainstStandingUp() {
        func level(after steps: Int, sneaking: Bool) -> Float {
            let world = FakePerceptionWorld(
                observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
                targets: [PerceptionFixture.target(
                    feet: SIMD3(600, 0, 0),
                    gait: sneaking ? .sneak : .walk,
                    isSneaking: sneaking
                )]
            )
            let runtime = PerceptionRuntime(settings: settings, world: world)
            advance(runtime, steps: steps)
            return runtime.state(observer: PerceptionFixture.guardKey, target: .player).level
        }
        let standing = level(after: 12, sneaking: false)
        let sneaking = level(after: 12, sneaking: true)
        #expect(standing > 0)
        #expect(sneaking > 0)
        #expect(sneaking < standing)
    }

    @Test func decayLosesAVanishedTargetOnSchedule() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(200, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 120)
        #expect(runtime.state(observer: PerceptionFixture.guardKey, target: .player)
            .state == .detected)

        // The target steps out of the world entirely, so nothing is perceived
        // and only decay runs. At 20 a second from a full 100 the level crosses
        // back under the suspicious threshold at 3.75 s and empties at 5 s.
        world.targets = [PerceptionFixture.target(feet: SIMD3(99999, 0, 0), gait: nil)]
        advance(runtime, steps: 180) // 3 s
        let partway = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(partway.level > settings.suspiciousLevel.value)
        #expect(partway.state == .suspicious)

        advance(runtime, steps: 60) // 4 s total
        #expect(runtime.state(observer: PerceptionFixture.guardKey, target: .player)
            .state == .unaware)

        advance(runtime, steps: 120) // 6 s total, past the 5 s empty point
        let emptied = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(emptied.level == 0)
        #expect(emptied.lastKnownPosition == nil)
    }

    @Test func theInvestigatePositionLandsWhereTheTargetWasLastSeen() {
        let seenAt = SIMD3<Float>(600, 120, 0)
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: seenAt)]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 60)
        #expect(runtime.state(observer: PerceptionFixture.guardKey, target: .player)
            .lastKnownPosition == seenAt)

        // The target ducks behind a wall and keeps moving. The remembered
        // position stays where it was last actually perceived, not where the
        // target now is — which is the whole point of an investigate position.
        world.blocked = PerceptionFixture.wall(atX: 300)
        world.targets = [PerceptionFixture.target(feet: SIMD3(1400, -900, 0), gait: nil)]
        advance(runtime, steps: 60)
        let pair = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(pair.lastKnownPosition == seenAt)
        #expect(pair.state != .unaware)
    }

    @Test func theSameInputsProduceTheSameLevelsTwice() {
        func run() -> [Float] {
            let world = FakePerceptionWorld(
                observers: [
                    PerceptionFixture.observer(feet: SIMD3(0, 0, 0)),
                    PerceptionFixture.observer(
                        key: PerceptionFixture.secondGuardKey,
                        feet: SIMD3(300, 300, 0),
                        facing: .pi,
                        name: "Second"
                    )
                ],
                targets: [PerceptionFixture.target(feet: SIMD3(700, 40, 0))]
            )
            let runtime = PerceptionRuntime(settings: settings, world: world)
            advance(runtime, steps: 37)
            return runtime.readout().pairs.map(\.level)
        }
        #expect(run() == run())
    }
}
