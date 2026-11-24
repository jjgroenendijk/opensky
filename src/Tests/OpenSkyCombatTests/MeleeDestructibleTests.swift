// A player's swing that reaches a destructible object deals it destruction damage.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct MeleeDestructibleTests {
    /// A barrel in reach takes the swing's damage as destruction damage, once a swing.
    @Test func aSwingDamagesADestructibleObjectInReach() {
        let world = FakeMeleeWorld()
        world.destructibles = [MeleeTarget(key: .generated(9), feet: SIMD3(80, 0, 0))]
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 24)
        MeleeCombatRuntimeTests.drawAndSwing(runtime)
        #expect(world.objectDamage == [.generated(9): 24])
        #expect(world.damage.isEmpty)
    }
}
