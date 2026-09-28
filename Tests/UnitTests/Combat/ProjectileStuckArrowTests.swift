// Stuck arrows and the streaming lifecycle (issue #196, roadmap item 15.5,
// scope points 4 and 5), split out of `ProjectileRuntimeTests.swift` for the
// strict-lint type-body cap. Same runtime, same fake world, same shot helpers;
// what differs is that these tests ask what is left behind after an impact
// rather than what the impact did.

@testable import opensky
import simd
import Testing

@MainActor
struct ProjectileStuckArrowTests {
    private static let arrow = FormID(0x0001_397D)
    private static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))

    private static func flatProfile(range: Float = 4000) -> ProjectileProfile {
        ProjectileProfile(speed: 1000, gravityFactor: 0, range: range, collisionRadius: 2)
    }

    private static func runtime(world: FakeProjectileWorld) -> ProjectileRuntime {
        let runtime = ProjectileRuntime(settings: .synthetic)
        runtime.attach(world: world)
        return runtime
    }

    private static func shot(profile: ProjectileProfile) -> ProjectileShot {
        ProjectileShot.arrow(
            profile: profile,
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E),
            ammunition: arrow
        )
    }

    /// Runs `seconds` of simulation in the one-frame chunks a 60 Hz display
    /// would deliver.
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

    @Test func anArrowThatLandsIsLeftStandingInTheWorld() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))

        let traces = Self.advance(runtime, seconds: 2)

        #expect(traces.first?.stuck == true)
        #expect(runtime.stuck.count == 1)
        #expect(world.spawned.first?.base == Self.arrow)
        #expect(world.spawned.first?.host?.rawValue == 0x0002_0000)
        #expect(world.spawned.first?.location == Self.cell)
    }

    /// UESP: "Only 15 missed arrows or bolts can be present at once, once a
    /// 16th has been fired the first one fired will despawn."
    @Test func theSixteenthStuckArrowEvictsTheFirst() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        world.arrowCount = 100
        let runtime = Self.runtime(world: world)

        for _ in 0 ..< 16 {
            runtime.fire(Self.shot(profile: Self.flatProfile()))
            Self.advance(runtime, seconds: 2)
        }

        #expect(world.spawned.count == 16)
        #expect(runtime.stuck.count == ProjectileRuntime.stuckLimit)
        #expect(world.removed.count == 1)
        #expect(world.liveStuckKeys.count == ProjectileRuntime.stuckLimit)
    }

    /// The streaming lifecycle: a cell that unloads takes its stuck arrows.
    @Test func anUnloadedCellTakesItsStuckArrowsWithIt() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))
        Self.advance(runtime, seconds: 2)
        #expect(runtime.stuck.count == 1)

        world.residentCells = [.exterior(CellCoordinate(x: 9, y: 9))]
        runtime.advance(by: 1.0 / 60)

        #expect(runtime.stuck.isEmpty)
        #expect(world.removed.count == 1)
    }

    /// An empty resident set means "nothing is streamed", which must leave
    /// stuck arrows alone rather than evicting every one of them.
    @Test func anEmptyResidentSetEvictsNothing() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))
        Self.advance(runtime, seconds: 2)

        world.residentCells = []
        runtime.advance(by: 1.0 / 60)

        #expect(runtime.stuck.count == 1)
        #expect(world.removed.isEmpty)
    }

    /// In-flight projectiles do not survive a reset — which is what makes them
    /// something a save/load does not persist.
    @Test func despawningResolvesNothingAndEmptiesTheAir() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: .generated(7), feet: SIMD3(3000, 0, -64))]
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))
        runtime.advance(by: 1.0 / 60)

        runtime.despawnAll()

        #expect(runtime.live.isEmpty)
        #expect(world.damage.isEmpty)
        #expect(runtime.trace.last?.outcome == .cancelled)
    }

    @Test func clearingStuckArrowsPullsThemAllBackOut() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        world.arrowCount = 5
        let runtime = Self.runtime(world: world)
        for _ in 0 ..< 3 {
            runtime.fire(Self.shot(profile: Self.flatProfile()))
            Self.advance(runtime, seconds: 2)
        }

        runtime.clearStuckArrows()

        #expect(runtime.stuck.isEmpty)
        #expect(world.removed.count == 3)
    }

    @Test func aSessionThatCannotSpawnStillResolvesTheImpact() {
        let world = FakeProjectileWorld()
        world.canSpawn = false
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))

        let traces = Self.advance(runtime, seconds: 2)

        #expect(traces.first?.outcome == .hitStatic)
        #expect(traces.first?.stuck == false)
        #expect(runtime.stuck.isEmpty)
    }

    @Test func theTraceIsBounded() {
        let world = FakeProjectileWorld()
        world.arrowCount = 100
        world.canSpawn = false
        let runtime = Self.runtime(world: world)
        for _ in 0 ..< (ProjectileRuntime.traceLimit + 5) {
            runtime.fire(Self.shot(profile: Self.flatProfile(range: 100)))
            Self.advance(runtime, seconds: 1)
        }

        #expect(runtime.trace.count == ProjectileRuntime.traceLimit)
    }
}
