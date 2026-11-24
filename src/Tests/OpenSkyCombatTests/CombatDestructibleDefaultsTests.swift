// The combat world parts pass destructible objects through to the world, and a world
// or a fake that knows none damages nothing.

@testable import OpenSkyCombat
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct CombatDestructibleDefaultsTests {
    private static let barrel = ReferenceKey.generated(40)

    private static func coordinator() -> CombatCoordinator {
        CombatCoordinator(
            world: FakeCoordinatorWorld(),
            data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func theWorldPartsFindNoObjectsInAWorldWithoutThem() {
        let coordinator = Self.coordinator()
        #expect(coordinator.loopWorld.combatDestructibles(within: 100, of: .zero).isEmpty)
        coordinator.loopWorld.damageCombatDestructible(Self.barrel, amount: 5)
        #expect(coordinator.meleeWorld.meleeDestructibles(within: 100, of: .zero).isEmpty)
        coordinator.meleeWorld.damageMeleeDestructible(Self.barrel, amount: 5)
        #expect(FakeCoordinatorWorld().destructibleKey(reference: FormID(0x50)) == nil)
    }

    @Test func aBlastWorldWithoutObjectsDamagesAndPlacesNothing() {
        let world = FakeImpulseWorld()
        #expect(!world.applyDestructionDamage(5, to: Self.barrel))
        #expect(!world.placeExplosionObject(ExplosionObjectPlacement(
            base: Self.barrel,
            position: .zero
        )))
    }
}
