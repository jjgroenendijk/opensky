// What a mine and an explosive shot read through the projectile world: who sets a mine
// off, the player's roll, the place, the shooter's skill, and an arrow on an object.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyProgressionInterface
import simd
import Testing

@MainActor
struct CombatProjectileMineTests {
    private static let wolf = ReferenceKey.generated(7)
    private static let deer = ReferenceKey.generated(8)
    private static let corpse = ReferenceKey.generated(9)

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func thePlayersMineReachesOnlyLivingHostileActors() {
        let world = FakeCoordinatorWorld()
        world.actors = [
            CombatActorObservation(key: Self.wolf, feet: SIMD3(1, 0, 0)),
            CombatActorObservation(key: Self.deer, feet: SIMD3(2, 0, 0)),
            CombatActorObservation(key: Self.corpse, feet: SIMD3(3, 0, 0), isDead: true)
        ]
        world.hostilities = [Self.wolf: .hostile, Self.corpse: .hostile]
        let part = Self.coordinator(world).projectileWorld
        #expect(part.mineTriggers(for: .player).map(\.key) == [Self.wolf])
    }

    @Test func anNPCsMineReachesThePlayerOnlyWhenHostile() {
        let world = FakeCoordinatorWorld()
        let part = Self.coordinator(world).projectileWorld
        #expect(part.mineTriggers(for: Self.wolf).isEmpty)
        world.hostilities[Self.wolf] = .hostile
        #expect(part.mineTriggers(for: Self.wolf).map(\.key) == [.player])
    }

    @Test func aZeroChanceNeverSetsTheMineOff() {
        let world = FakeCoordinatorWorld()
        world.perkFactors[.calculateMineExplodeChance] = 0
        #expect(!Self.coordinator(world).projectileWorld.playerSetsOffMine())
        world.perkFactors[.calculateMineExplodeChance] = 2
        #expect(Self.coordinator(world).projectileWorld.playerSetsOffMine())
    }

    @Test func theProjectileWorldReadsThePlaceAndTheSkill() throws {
        let world = FakeCoordinatorWorld()
        let archery = try #require(ActorValueIdentity.index(named: "Archery"))
        world.values[.player] = [archery: 40]
        let part = Self.coordinator(world).projectileWorld
        #expect(part.projectileIsOutdoors == !world.isInInterior)
        #expect(part.explosiveShotSkill(of: .player) == 40)
        #expect(part.explosiveShotSkill(of: Self.wolf) == nil)
        #expect(!part.applyProjectileDestruction(5, to: FormID(0x50)))
    }
}
