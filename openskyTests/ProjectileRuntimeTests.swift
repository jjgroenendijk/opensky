// The projectile runtime end to end (issue #196, roadmap item 15.5, scope
// points 3 to 5).
//
// The issue's acceptance in one file: "deterministic tests pin a full
// trajectory (spawn, apex, impact point) and verify range despawn, inventory
// consumption, damage combination, and one-impact-per-projectile", plus the
// stuck-arrow cap and the streaming lifecycle.
//
// The graph is stood in for by `ArcheryRuntime.loose` and by the list of names
// the graph would have fired, which is exactly what
// `LocomotionGraphEventQueue` hands the runtime. `ArcheryStateTests` covers the
// state machine those names drive and the env-gated `ProjectileRealDataTests`
// closes the loop on vanilla PROJ values.

@testable import opensky
import simd
import Testing

@MainActor
struct ProjectileRuntimeTests {
    private static let arrow = FormID(0x0001_397D)
    private static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))

    /// A flat, fast shot: no gravity, so the impact point is exactly on the
    /// aim ray and a test can name it.
    private static func flatProfile(range: Float = 4000) -> ProjectileProfile {
        ProjectileProfile(speed: 1000, gravityFactor: 0, range: range, collisionRadius: 2)
    }

    private static func runtime(
        world: FakeProjectileWorld,
        settings: ArcherySettings = .synthetic
    ) -> ProjectileRuntime {
        let runtime = ProjectileRuntime(settings: settings)
        runtime.attach(world: world)
        return runtime
    }

    private static func shot(
        profile: ProjectileProfile,
        damage: Float = 15,
        ammunition: FormID? = arrow
    ) -> ArcheryShot {
        ArcheryShot(
            profile: profile,
            damage: ArcheryDamage.resolve(
                bowDamage: damage, arrowDamage: 0, skill: 0
            ),
            weapon: FormID(0x0001_397E),
            ammunition: ammunition
        )
    }

    /// Runs `seconds` of simulation in one-frame chunks a 60 Hz display would
    /// deliver, which is what makes the accumulator do its job.
    @discardableResult
    private static func advance(
        _ runtime: ProjectileRuntime,
        seconds: Float
    ) -> [ProjectileTrace] {
        var traces: [ProjectileTrace] = []
        var elapsed: Float = 0
        while elapsed < seconds {
            traces += runtime.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        return traces
    }

    // MARK: - Firing

    @Test func firingConsumesOneArrowFromTheQuiver() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        let projectile = runtime.fire(Self.shot(profile: Self.flatProfile()))

        #expect(projectile != nil)
        #expect(world.consumed == [Self.arrow])
        #expect(world.arrowCount == 9)
        #expect(runtime.firedCount == 1)
        #expect(runtime.live.count == 1)
    }

    @Test func anEmptyQuiverPutsNothingInTheAir() {
        let world = FakeProjectileWorld()
        world.arrowCount = 0
        let runtime = Self.runtime(world: world)

        let projectile = runtime.fire(Self.shot(profile: Self.flatProfile()))

        #expect(projectile == nil)
        #expect(runtime.live.isEmpty)
        #expect(runtime.firedCount == 0)
    }

    /// The dev spawn control fires with no ammunition named, which must not
    /// touch the quiver.
    @Test func aShotWithNoAmmunitionLeavesTheQuiverAlone() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.fire(Self.shot(profile: Self.flatProfile(), ammunition: nil))

        #expect(world.consumed.isEmpty)
        #expect(world.arrowCount == 10)
        #expect(runtime.live.count == 1)
    }

    @Test func aProfileWithNoLaunchSpeedIsRefused() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        let projectile = runtime.fire(
            Self.shot(profile: ProjectileProfile(speed: 0, gravityFactor: 0.35))
        )

        #expect(projectile == nil)
        #expect(world.consumed.isEmpty)
    }

    /// The launch is tilted up by the perspective's own GMST, which is the
    /// whole of what `f3PArrowTiltUpAngle` does.
    @Test func theShotIsTiltedUpByThePerspectivesAngle() {
        let world = FakeProjectileWorld()
        world.shooter = ProjectileShooter(
            key: .player, origin: SIMD3(), aim: SIMD3(1, 0, 0),
            isFirstPerson: false, location: Self.cell
        )
        let runtime = Self.runtime(world: world)

        let projectile = runtime.fire(Self.shot(profile: Self.flatProfile()))

        // 2.5 degrees in third person.
        let expected = sinf(2.5 * Float.pi / 180)
        #expect(abs((projectile?.launchDirection.z ?? 0) - expected) < 0.0001)
    }

    // MARK: - Impact

    @Test func aShotThatStrikesAnActorDamagesItOnceAndStops() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: .generated(7), feet: SIMD3(500, 0, -64))]
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile(), damage: 15))

        let traces = Self.advance(runtime, seconds: 2)

        #expect(runtime.live.isEmpty)
        #expect(runtime.impactCount == 1)
        #expect(traces.count == 1)
        #expect(traces.first?.outcome == .hitActor)
        #expect(traces.first?.target == .generated(7))
        #expect(world.damage == [.generated(7): 15])
        // One impact per projectile, enforced by the projectile ceasing to
        // exist rather than by a filter: a second step never happens.
        #expect(Self.advance(runtime, seconds: 2).isEmpty)
        #expect(world.damage[.generated(7)] == 15)
    }

    @Test func aShotThatStrikesGeometryStopsThereAndDamagesNothing() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 800, reference: FormID(0x0002_0000))
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))

        let traces = Self.advance(runtime, seconds: 2)

        #expect(traces.first?.outcome == .hitStatic)
        #expect(traces.first?.target == nil)
        #expect(world.damage.isEmpty)
        // The impact point is on the wall, within one substep of travel.
        let end = traces.first?.endPosition ?? SIMD3()
        #expect(abs(end.x - 800) < 1000 * WalkController.fixedTimeStep + 0.01)
    }

    /// An actor standing behind a wall is not hit: the nearer touch wins.
    @Test func theNearerOfAWallAndAnActorWins() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 400, reference: FormID(0x0002_0000))
        world.targets = [MeleeTarget(key: .generated(7), feet: SIMD3(900, 0, -64))]
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))

        let traces = Self.advance(runtime, seconds: 2)

        #expect(traces.first?.outcome == .hitStatic)
        #expect(world.damage.isEmpty)
    }

    @Test func aShotNeverHitsTheShooter() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: .player, feet: SIMD3(0, 0, -64))]
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))

        let traces = Self.advance(runtime, seconds: 8)

        #expect(world.damage.isEmpty)
        #expect(traces.first?.outcome == .outOfRange)
    }

    // MARK: - Expiry

    @Test func aMissDespawnsAtTheShorterOfRangeAndTheVisibleMoveDistance() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        // PROJ range 60000, `fVisibleNavmeshMoveDist` 4096: the setting wins.
        runtime.fire(Self.shot(profile: Self.flatProfile(range: 60000)))

        let traces = Self.advance(runtime, seconds: 8)

        #expect(runtime.live.isEmpty)
        #expect(traces.first?.outcome == .outOfRange)
        #expect((traces.first?.travelled ?? 0) >= 4096)
        #expect((traces.first?.travelled ?? 0) < 4096 + 1000 * WalkController.fixedTimeStep + 1)
    }

    @Test func aShorterRecordRangeWinsOverTheSetting() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile(range: 1000)))

        let traces = Self.advance(runtime, seconds: 8)

        #expect(traces.first?.outcome == .outOfRange)
        #expect((traces.first?.travelled ?? 0) < 1010)
    }

    @Test func aLifetimeCapRetiresAShotThatIsStillInRange() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        runtime.fire(
            Self.shot(
                profile: ProjectileProfile(
                    speed: 100, gravityFactor: 0, range: 60000, lifetime: 0.5
                )
            )
        )

        let traces = Self.advance(runtime, seconds: 2)

        #expect(traces.first?.outcome == .expired)
        #expect(abs((traces.first?.flightTime ?? 0) - 0.5) < 0.02)
    }

    // MARK: - Determinism

    /// The requirement the issue words as "deterministic trajectories": the
    /// same shot advanced in 60 Hz frames and in 240 Hz frames lands in the
    /// same place, because both run the same fixed steps.
    @Test func theImpactPointDoesNotDependOnTheFrameRate() {
        func impact(frameTime: Float) -> SIMD3<Float> {
            let world = FakeProjectileWorld()
            world.wall = FakeProjectileWorld.Wall(x: 900, reference: FormID(0x0002_0000))
            let runtime = Self.runtime(world: world)
            runtime.fire(
                Self.shot(
                    profile: ProjectileProfile(
                        speed: 1000, gravityFactor: 0.35, range: 60000, collisionRadius: 2
                    )
                )
            )
            var traces: [ProjectileTrace] = []
            for _ in 0 ..< Int(4 / frameTime) where traces.isEmpty {
                traces += runtime.advance(by: frameTime)
            }
            return traces.first?.endPosition ?? SIMD3()
        }

        #expect(simd_distance(impact(frameTime: 1.0 / 60), impact(frameTime: 1.0 / 240)) < 0.001)
    }
}
