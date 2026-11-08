// Kill moves: a swing weighs its hit on the actor in front, and the coordinator decides
// whether that hit kills before the idle tree picks the paired idle.

@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct KillMoveTests {
    private static let npc = ReferenceKey.generated(1)

    private static func coordinator(health: Float) -> (CombatCoordinator, FakeCoordinatorWorld) {
        let world = FakeCoordinatorWorld()
        world.healths[npc] = (health, 100)
        let coordinator = CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
        return (coordinator, world)
    }

    @Test func aPlayedKillMoveReplacesTheSwing() {
        for plays in [false, true] {
            let world = FakeMeleeWorld()
            world.playsKillMoves = plays
            world.targets = [MeleeTarget(key: Self.npc, feet: SIMD3(80, 0, 0))]
            let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 24)
            runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)
            runtime.acceptFrame(MeleeIntent(attack: true))
            #expect(world.killMoveDamage == [Self.npc: 24])
            #expect(world.raised.contains(CombatGraphNames.attackStart) == !plays)
        }
    }

    @Test func aSwingWithNoOneInReachWeighsNoKillMove() {
        let world = FakeMeleeWorld()
        world.playsKillMoves = true
        world.targets = [MeleeTarget(key: Self.npc, feet: SIMD3(2000, 0, 0))]
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 24)
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)
        runtime.acceptFrame(MeleeIntent(attack: true))
        #expect(world.killMoveDamage.isEmpty)
        #expect(world.raised.contains(CombatGraphNames.attackStart))
    }

    @Test func theAttackKillsWhenItsHitTakesHealthToZero() {
        let (coordinator, world) = Self.coordinator(health: 20)
        #expect(coordinator.startMeleeKillMove(on: Self.npc, damage: 30, power: true))
        #expect(coordinator.startMeleeKillMove(on: Self.npc, damage: 5, power: false))
        #expect(world.killMoves.map(\.kills) == [true, false])
        #expect(world.killMoves.map(\.action) == [
            KillMoveAttempt.powerAttackAction, KillMoveAttempt.attackAction
        ])
    }

    @Test func anUnkillableOrDeadTargetIsNotKilled() {
        let (coordinator, world) = Self.coordinator(health: 20)
        world.unkillable = [Self.npc]
        coordinator.startMeleeKillMove(on: Self.npc, damage: 30, power: false)
        world.unkillable = []
        world.healths[Self.npc] = (0, 100)
        coordinator.startMeleeKillMove(on: Self.npc, damage: 30, power: false)
        #expect(world.killMoves.map(\.kills) == [false, false])
    }

    @Test func anNPCKillMoveNeverTakesThePlayer() {
        let (coordinator, world) = Self.coordinator(health: 20)
        world.healths[.player] = (1, 100)
        #expect(!coordinator.startCombatKillMove(by: Self.npc, on: .player, damage: 30))
        #expect(world.killMoves.isEmpty)
    }

    @Test func anActorInAKillMoveTakesTenfoldDamageAndLeavesTheFight() {
        let (coordinator, world) = Self.coordinator(health: 100)
        world.inKillMove = [Self.npc]
        coordinator.applyHealthDamage(2, to: Self.npc, attacker: nil)
        #expect(world.damage.map(\.amount) == [20])
        #expect(coordinator.combatIgnoredByPackage(Self.npc))
    }
}
