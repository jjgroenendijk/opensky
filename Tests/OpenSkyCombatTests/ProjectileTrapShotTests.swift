// A shot a script fires with `Weapon.Fire` from a trap: it spends no arrow, the trap
// is credited with the hit, and the arrow still sticks.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyPhysics
import simd
import Testing

@MainActor
struct ProjectileTrapShotTests {
    @Test func aTrapShotSpendsNoArrowAndCreditsTheTrap() {
        let dart = FormID(0x0001_397D)
        let trap = ReferenceKey.generated(90)
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: .player, feet: SIMD3(500, 0, -64))]
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        var payload = ArrowPayload(
            damage: ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 5, skill: 0),
            ammunition: dart
        )
        payload.spendsAmmunition = false
        let shooter = ProjectileShooter(
            key: trap, origin: .zero, aim: SIMD3(1, 0, 0), isFirstPerson: false,
            location: .exterior(CellCoordinate(x: 0, y: 0))
        )
        let shot = ProjectileShot(
            profile: ProjectileProfile(speed: 1000, gravityFactor: 0, range: 4000),
            payload: .arrow(payload)
        )

        #expect(shot.consumedAmmunition == nil)
        #expect(runtime.fire(shot, from: shooter) != nil)
        for _ in 0 ..< 120 {
            runtime.advance(by: 1.0 / 60)
        }

        #expect(world.consumed.isEmpty)
        #expect(world.arrowCount == 10)
        #expect(world.damage[.player] == 15)
        #expect(world.damagedBy[.player] == trap)
        #expect(world.spawned.map(\.base) == [dart])
    }
}
