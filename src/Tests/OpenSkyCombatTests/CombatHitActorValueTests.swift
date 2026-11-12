// The attacker's and the defender's actor values on a weapon hit: `Attack Damage Mult`
// scales the blow, and `Reflect Damage` sends it back.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

@MainActor
struct CombatHitActorValueTests {
    private static let guardKey = ReferenceKey.generated(1)

    private static func coordinator(
        reflecting chance: Float, on defender: ReferenceKey
    ) -> (CombatCoordinator, FakeCoordinatorWorld) {
        let world = FakeCoordinatorWorld()
        world.values[defender] = [ActorValueIndex.reflectDamage: chance]
        let coordinator = CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
        return (coordinator, world)
    }

    @Test func aCertainReflectSendsTheFullBlowBackAndSparesNoOne() {
        let (coordinator, world) = Self.coordinator(reflecting: 100, on: Self.guardKey)
        coordinator.meleeWorld.applyMeleeDamage(12, to: Self.guardKey)
        #expect(world.damage.map(\.key) == [Self.guardKey, .player])
        #expect(world.damage.map(\.amount) == [12, 12])
    }

    @Test func anNPCBlowOnAReflectingPlayerComesBack() {
        let (coordinator, world) = Self.coordinator(reflecting: 100, on: .player)
        let blow = CombatBlow(
            attacker: Self.guardKey, weapon: nil, handType: .sword, baseDamage: 8
        )
        coordinator.loopWorld.applyCombatBlow(8, to: .player, blow: blow)
        #expect(world.damage.map(\.key) == [.player, Self.guardKey])
        #expect(world.damage.map(\.amount) == [8, 8])
    }

    @Test func rangedAndUnattributedHitsDoNotReflect() {
        let (coordinator, world) = Self.coordinator(reflecting: 100, on: Self.guardKey)
        coordinator.shared.damage.applyHealthDamage(
            5,
            to: Self.guardKey,
            attacker: .player,
            kind: .ranged
        )
        coordinator.shared.damage.applyHealthDamage(
            5,
            to: Self.guardKey,
            attacker: nil,
            kind: .melee
        )
        #expect(world.damage.map(\.key) == [Self.guardKey, Self.guardKey])
    }

    @Test func twoReflectingActorsDoNotTradeTheBlowForever() {
        let (coordinator, world) = Self.coordinator(reflecting: 100, on: Self.guardKey)
        world.values[.player] = [ActorValueIndex.reflectDamage: 100]
        coordinator.meleeWorld.applyMeleeDamage(3, to: Self.guardKey)
        #expect(world.damage.count == 2)
    }

    @Test func theChanceIsAPercent() {
        let (coordinator, world) = Self.coordinator(reflecting: 50, on: Self.guardKey)
        for _ in 0 ..< 400 {
            coordinator.meleeWorld.applyMeleeDamage(1, to: Self.guardKey)
        }
        let reflected = world.damage.filter { $0.key == .player }.count
        #expect((140 ... 260).contains(reflected))
    }

    @Test func attackDamageMultScalesTheBlowAndDefaultsToOne() {
        let world = FakeCoordinatorWorld()
        world.values[Self.guardKey] = [ActorValueIndex.attackDamageMult: 0.5]
        let coordinator = CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
        let blow = CombatBlow(attacker: Self.guardKey, handType: .sword, baseDamage: 10)
        #expect(coordinator.shared.strikes.strike(blow, on: .player).damage(base: 10) == 5)
        let unset = CombatBlow(
            attacker: .generated(2), handType: .sword, baseDamage: 10
        )
        #expect(coordinator.shared.strikes.strike(unset, on: .player).damage(base: 10) == 10)
        #expect(ActorValueIdentity.index(named: "Attack Damage Mult") == ActorValueIndex
            .attackDamageMult)
        #expect(ActorValueIdentity.index(named: "Reflect Damage") == ActorValueIndex.reflectDamage)
        #expect(ActorValueIdentity.defaultValue(at: ActorValueIndex.attackDamageMult) == 1)
    }

    @Test func noReflectNeverDrawsOrReflects() {
        let (coordinator, world) = Self.coordinator(reflecting: 0, on: Self.guardKey)
        coordinator.meleeWorld.applyMeleeDamage(4, to: Self.guardKey)
        #expect(world.damage.map(\.key) == [Self.guardKey])
    }
}
