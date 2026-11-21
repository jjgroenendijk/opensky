// A press with the bow away only draws it: the bow aims nothing until the button
// is let go and pressed again. See docs/engine/attack-input.md.

@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import Testing

@MainActor
struct ArcherySheathedPressTests {
    @Test func aPressWithTheBowAwayDrawsNothingUntilPressedAgain() {
        let world = FakeProjectileWorld()
        let runtime = ArcheryRuntime(
            settings: .synthetic,
            projectiles: ProjectileRuntime(settings: .synthetic, world: world),
            world: world
        )
        runtime.bow = MeleeWeaponProfile(damage: 7, reach: 1, weapon: FormID(0x0001_397E))
        runtime.arrow = ArcheryAmmunition(
            item: FormID(0x0001_397D),
            damage: 8,
            profile: ProjectileProfile(speed: 3600, gravityFactor: 0.35, range: 60000)
        )
        func frame(held: Bool, drawn: Bool) {
            runtime.acceptFrame(ArcheryIntent(
                drawing: held, hasBowEquipped: true, deltaTime: 1.0 / 60, weaponDrawn: drawn
            ))
        }
        frame(held: true, drawn: false)
        frame(held: true, drawn: true)
        frame(held: true, drawn: true)
        #expect(runtime.drawRequestCount == 0)
        frame(held: false, drawn: true)
        frame(held: true, drawn: true)
        #expect(runtime.drawRequestCount == 1)
    }
}
