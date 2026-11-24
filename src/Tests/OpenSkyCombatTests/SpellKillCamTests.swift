// A spell's kill cam is decided when it leaves the hand: it plays when the spell's
// health damage kills the target, and not when it falls short.

import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct SpellKillCamTests {
    private static let wolf = ReferenceKey.generated(3)

    private static func firebolt() -> SpellPayload {
        SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x0230), sourcePlugin: "Base.esm",
            caster: .player,
            entries: [MagicItemEffect(effect: FormID(0x0012), magnitude: 40, area: 0, duration: 0)],
            isHostile: true, ignoresResistance: false, projectile: FormID(0x0020), name: "Firebolt"
        )
    }

    private static func projectile() -> LiveProjectile {
        let profile = ProjectileProfile(
            speed: 1000,
            gravityFactor: 0,
            range: 4000,
            collisionRadius: 2
        )
        return LiveProjectile(
            id: 7, shooter: .player, profile: profile, payload: .spell(firebolt()),
            launchPosition: .zero, launchDirection: SIMD3(1, 0, 0), location: nil,
            state: ProjectileFlight.launch(from: .zero, along: SIMD3(1, 0, 0), profile: profile)
        )
    }

    /// The player is nearly dead, so the chance check passes at once.
    private static func coordinator(spellDamage: Float) -> CombatCoordinator {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: wolf, feet: SIMD3(600, 0, 0))]
        world.hostilities[wolf] = .hostile
        world.healths[wolf] = (30, 30)
        world.healths[.player] = (1, 100)
        world.spellDamage = spellDamage
        return CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func aKillingSpellStartsTheKillCamAtTheRelease() {
        let coordinator = Self.coordinator(spellDamage: 40)
        let aim = coordinator.projectileWorld.projectileKillCamAim(
            for: Self.projectile(), aimTarget: Self.wolf
        )
        #expect(aim != nil)
        #expect(coordinator.takeCommands().contains(.rangedKillCam(
            projectile: 7,
            target: Self.wolf
        )))
    }

    @Test func aSpellThatLeavesTheTargetAliveStartsNone() {
        let coordinator = Self.coordinator(spellDamage: 10)
        let aim = coordinator.projectileWorld.projectileKillCamAim(
            for: Self.projectile(), aimTarget: Self.wolf
        )
        #expect(aim == nil)
        #expect(coordinator.takeCommands().isEmpty)
    }
}
