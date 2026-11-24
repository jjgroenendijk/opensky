// An arrow damages the destructible object it strikes, and a shot that passes the kill
// cam's release check turns toward its target.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct ProjectileObjectAndKillCamTests {
    private static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))

    private static func flatProfile() -> ProjectileProfile {
        ProjectileProfile(speed: 1000, gravityFactor: 0, range: 4000, collisionRadius: 2)
    }

    private static func runtime(world: FakeProjectileWorld) -> ProjectileRuntime {
        ProjectileRuntime(settings: .synthetic, world: world)
    }

    private static func shot(profile: ProjectileProfile) -> ProjectileShot {
        ProjectileShot.arrow(
            profile: profile,
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E),
            ammunition: FormID(0x0001_397D)
        )
    }

    private static func advance(_ runtime: ProjectileRuntime, seconds: Float) {
        var elapsed: Float = 0
        while elapsed < seconds {
            _ = runtime.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
    }

    /// A wall that is a destructible object takes the arrow's damage as destruction damage.
    @Test func anArrowDamagesTheObjectItStrikes() {
        let world = FakeProjectileWorld()
        let barrel = FormID(0x0002_0000)
        world.wall = FakeProjectileWorld.Wall(x: 800, reference: barrel)
        let runtime = Self.runtime(world: world)
        runtime.fire(Self.shot(profile: Self.flatProfile()))
        Self.advance(runtime, seconds: 2)
        #expect(world.objectDamage[barrel] == 15)
    }

    /// A shot that passes the kill cam's release check turns toward the target, by at
    /// most 15 degrees.
    @Test func aKillCamShotTurnsTowardItsTarget() throws {
        let world = FakeProjectileWorld()
        world.shooter = ProjectileShooter(
            key: .player, origin: .zero, aim: SIMD3(1, 0, 0), isFirstPerson: false,
            location: Self.cell
        )
        world.killCamAim = SIMD3(1000, 1000, 0)
        let runtime = Self.runtime(world: world)
        let shot = try #require(runtime.fire(Self.shot(profile: Self.flatProfile())))
        let flight = simd_normalize(shot.state.velocity)
        let turn = acos(min(1, simd_dot(flight, simd_normalize(shot.launchDirection))))
        #expect(flight.y > 0)
        #expect(turn <= 15 * .pi / 180 + 0.001)
    }
}
