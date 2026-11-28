// What using a stuck projectile does: the `PROJ` flags Can Be Disabled and Can Be
// Picked Up. See docs/engine/projectiles.md, "Pick-up, bounce, and stick in the game".

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct ProjectileStuckActivationTests {
    private static let disableSound = FormID(0x0005_5555)

    /// Fires one arrow with `activation` into a wall and returns the runtime and the
    /// key of the arrow left standing.
    private static func stuckArrow(
        _ activation: ProjectileActivation
    ) throws -> (ProjectileRuntime, ReferenceKey) {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        var profile = ProjectileProfile(
            speed: 1000,
            gravityFactor: 0,
            range: 4000,
            collisionRadius: 2
        )
        profile.activation = activation
        runtime.fire(ProjectileShot.arrow(
            profile: profile,
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E),
            ammunition: FormID(0x0001_397D)
        ))
        for _ in 0 ..< 120 {
            runtime.advance(by: 1.0 / 60)
        }
        let key = try #require(runtime.stuck.first?.key)
        return (runtime, key)
    }

    @Test func theFlagsComeFromTheRecord() {
        func activation(_ flags: Projectile.Flags) -> ProjectileActivation {
            ProjectileProfile(record: Projectile(
                formID: FormID(0x0010_B0A5), flags: flags, gravityFactor: 0, speed: 3000,
                range: 10000
            )).activation
        }
        #expect(activation([.canBePickedUp]) == ProjectileActivation(canBePickedUp: true))
        #expect(
            activation([.canBeDisabled])
                == ProjectileActivation(canBePickedUp: false, canBeDisabled: true)
        )
    }

    @Test func anArrowThatCanBePickedUpLetsTheTakeThrough() throws {
        let (runtime, key) = try Self.stuckArrow(ProjectileActivation())
        let use = runtime.activateStuck(key)
        #expect(use?.allowsPickUp == true)
        #expect(use?.disableSound == nil)
    }

    /// `BoundArrowPROJ` sets only Can Be Disabled: the first use plays the disable
    /// sound, and no use takes the arrow.
    @Test func aBoundArrowIsDisabledOnceAndNeverTaken() throws {
        let rule = ProjectileActivation(
            canBePickedUp: false, canBeDisabled: true, disableSound: Self.disableSound
        )
        let (runtime, key) = try Self.stuckArrow(rule)

        let first = runtime.activateStuck(key)
        let second = runtime.activateStuck(key)

        #expect(first?.allowsPickUp == false)
        #expect(first?.disableSound == Self.disableSound)
        #expect(second?.allowsPickUp == false)
        #expect(second?.disableSound == nil)
        #expect(runtime.stuck.first?.arrow.isDisabled == true)
    }

    @Test func aKeyThatIsNoStuckProjectileIsLeftAlone() throws {
        let (runtime, _) = try Self.stuckArrow(ProjectileActivation())
        #expect(runtime.activateStuck(.generated(9999)) == nil)
    }
}
