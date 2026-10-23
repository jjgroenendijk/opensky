// Allies in the combat loop: a summon walks after the player, fights the player's
// foe, and draws a foe that stands nearer to it. Whole fixed steps against
// `FakeCombatWorld`, so a fight repeats exactly.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
import simd
import Testing

@MainActor
struct CombatAllyTests {
    private typealias Fixture = CombatLoopFixture
    private static let ally = ReferenceKey.generated(9)

    private static func session(
        ally feet: SIMD3<Float>
    ) -> (runtime: CombatLoopRuntime, world: FakeCombatWorld) {
        let (runtime, world) = Fixture.session()
        world.actors.append(CombatActorObservation(key: ally, feet: feet, name: "Familiar"))
        world.weapons[ally] = MeleeWeaponProfile(damage: 5, reach: 1)
        runtime.command(ally, by: .player)
        return (runtime, world)
    }

    @Test func aFarAllyWalksBackToThePlayer() throws {
        let (runtime, world) = Self.session(ally: SIMD3(1000, 0, 0))
        world.actors.removeAll { $0.key == Fixture.opponent }
        Fixture.run(runtime, seconds: 0.1)
        let walk = try #require(world.moveRequests.last { $0.key == Self.ally })
        #expect(abs(simd_length(walk.point) - CombatAllyRule.keepDistance) < 0.01)
        #expect(world.moveRequests.count { $0.key == Self.ally } == 1)
        #expect(runtime.following[Self.ally] != nil)
    }

    @Test func aNearAllyStaysWhereItIs() {
        let (runtime, world) = Self.session(ally: SIMD3(100, 0, 0))
        world.actors.removeAll { $0.key == Fixture.opponent }
        Fixture.run(runtime, seconds: 0.1)
        #expect(world.moveRequests.isEmpty)
    }

    @Test func anAllyFightsTheFoeThatFightsThePlayer() {
        let (runtime, world) = Self.session(ally: SIMD3(60, 80, 0))
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 3)
        #expect(runtime.combatTarget(of: Self.ally) == Fixture.opponent)
        #expect((world.damage[Fixture.opponent] ?? 0) > 0)
        #expect(runtime.combatTarget(of: Fixture.opponent) == .player)
        #expect(world.hostility[Self.ally] == nil)
    }

    @Test func aFoeTurnsOnANearerAlly() {
        let (runtime, world) = Self.session(ally: SIMD3(100, 0, 0))
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 3)
        #expect(runtime.combatTarget(of: Fixture.opponent) == Self.ally)
        #expect((world.damage[Self.ally] ?? 0) > 0)
        #expect(world.damage[.player] == nil)
        #expect(runtime.incomingHitCount == 0)
    }

    @Test func thePlayersBlowDoesNotTurnAnAlly() {
        let (runtime, world) = Self.session(ally: SIMD3(100, 0, 0))
        runtime.notePlayerHits([Self.ally])
        #expect(world.hostility[Self.ally] == nil)
    }

    @Test func aDismissedAllyIsNoLongerCommanded() {
        let (runtime, world) = Self.session(ally: SIMD3(1000, 0, 0))
        Fixture.run(runtime, seconds: 0.1)
        runtime.dismiss(Self.ally)
        #expect(runtime.allies(of: .player).isEmpty)
        #expect(world.stopRequests.contains(Self.ally))
        #expect(!runtime.engagesWithoutPerceiving(Self.ally))
    }

    @Test func theFoeNearestTheAllyIsChosenWithinTheDefendRadius() {
        let near = MeleeTarget(key: .generated(1), feet: SIMD3(200, 0, 0))
        let far = MeleeTarget(key: .generated(2), feet: SIMD3(5000, 0, 0))
        let chosen = CombatAllyRule.foe(
            for: SIMD3(4900, 0, 0), defending: SIMD3(), among: [near, far]
        )
        #expect(chosen == near)
    }
}
