// An NPC's swing damages a destructible object inside it, and misses one outside it.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd
import Testing

@MainActor
struct CombatLoopDestructibleTests {
    private typealias Fixture = CombatLoopFixture
    private static let barrel = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x730)

    /// The opponent stands at +x and swings toward the player at the origin.
    private static func fight(barrelAt feet: SIMD3<Float>) -> FakeCombatWorld {
        let (runtime, world) = Fixture.session()
        world.destructibles = [MeleeTarget(key: barrel, feet: feet)]
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 2)
        return world
    }

    @Test func aSwingDamagesAnObjectBetweenTheFighters() {
        let world = Self.fight(barrelAt: SIMD3(30, 0, 0))
        #expect((world.objectDamage[Self.barrel] ?? 0) > 0)
    }

    @Test func aSwingMissesAnObjectBehindTheAttacker() {
        let world = Self.fight(barrelAt: SIMD3(400, 0, 0))
        #expect(world.objectDamage[Self.barrel] == nil)
    }
}
