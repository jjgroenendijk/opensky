// NPC against NPC: a guard fights the bandit it detects, the bandit fights back, and the
// player stays out of combat. Whole fixed steps against `FakeCombatWorld`.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import simd
import Testing

@MainActor
struct CombatNPCFoeTests {
    private typealias Fixture = CombatLoopFixture
    private static let guardKey = Fixture.opponent
    private static let bandit = Fixture.second
    private static let guardSeesBandit = CombatFoePair(observer: guardKey, target: bandit)

    /// A guard at 500 units from the player and a bandit in its reach.
    private static func session() -> (runtime: CombatLoopRuntime, world: FakeCombatWorld) {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.actors.append(CombatActorObservation(
            key: bandit, feet: SIMD3(560, 0, 0), name: "Bandit"
        ))
        world.weapons[bandit] = MeleeWeaponProfile(damage: 5, reach: 1)
        world.hostilePairs = [guardSeesBandit]
        return (runtime, world)
    }

    @Test func aGuardFightsTheBanditItDetectsAndTheBanditFightsBack() {
        let (runtime, world) = Self.session()
        world.pairAwareness[Self.guardSeesBandit] = .detected(at: SIMD3(560, 0, 0))
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 3)

        #expect(runtime.foePairs == [Self.guardSeesBandit])
        #expect(runtime.combatTarget(of: Self.guardKey) == Self.bandit)
        #expect(runtime.combatTarget(of: Self.bandit) == Self.guardKey)
        #expect((world.damage[Self.bandit] ?? 0) > 0)
        #expect((world.damage[Self.guardKey] ?? 0) > 0)
        #expect(world.damage[.player] == nil)
        #expect(!runtime.isPlayerInCombat)
        #expect(runtime.activity(of: .player) == .notFighting)
        #expect(!runtime.state.isPlayerInCombat)
    }

    /// A calm helper beside the guard takes on the bandit, and stays calm toward the player.
    @Test func aHelperJoinsItsAllysFightAgainstTheNPC() {
        let (runtime, world) = Self.session()
        let helper = ReferenceKey.generated(3)
        world.actors.append(CombatActorObservation(
            key: helper, feet: SIMD3(440, 0, 0), name: "Helper"
        ))
        world.weapons[helper] = MeleeWeaponProfile(damage: 5, reach: 1)
        world.assistPairs = [CombatFoePair(observer: helper, target: Self.guardKey)]
        world.pairAwareness[Self.guardSeesBandit] = .detected(at: SIMD3(560, 0, 0))
        world.awareness[helper] = .detected(at: SIMD3(500, 0, 0))
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 3)

        #expect(runtime.combatTarget(of: helper) == Self.bandit)
        #expect(!runtime.isPlayerInCombat)
        world.actors.removeAll { $0.key == Self.bandit }
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(runtime.npcAssists.isEmpty)
    }

    /// A helper that would help both sides stays out.
    @Test func aHelperOfBothSidesStaysOut() {
        let (runtime, world) = Self.session()
        let helper = ReferenceKey.generated(3)
        world.actors.append(CombatActorObservation(
            key: helper, feet: SIMD3(440, 0, 0), name: "Helper"
        ))
        world.assistPairs = [
            CombatFoePair(observer: helper, target: Self.guardKey),
            CombatFoePair(observer: helper, target: Self.bandit)
        ]
        world.pairAwareness[Self.guardSeesBandit] = .detected(at: SIMD3(560, 0, 0))
        world.awareness[helper] = .detected(at: SIMD3(500, 0, 0))
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 3)
        #expect(runtime.combatTarget(of: helper) == nil)
        #expect(runtime.npcAssists.isEmpty)
    }

    /// Pairs sort by observer, then target, so perception tracks them in a fixed order.
    @Test func foePairsSortByObserverThenTarget() {
        let first = CombatFoePair(observer: .generated(1), target: .generated(5))
        let second = CombatFoePair(observer: .generated(1), target: .generated(6))
        let third = CombatFoePair(observer: .generated(2), target: .generated(3))
        #expect([third, second, first].sorted() == [first, second, third])
    }

    @Test func aFoeNotYetDetectedIsNotFought() {
        let (runtime, world) = Self.session()
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(runtime.combatTarget(of: Self.guardKey) == nil)
        #expect(world.damage[Self.bandit] == nil)
    }

    @Test func aFriendDoesNotFightBack() {
        let (runtime, world) = Self.session()
        world.pairAwareness[Self.guardSeesBandit] = .detected(at: SIMD3(560, 0, 0))
        world.pairReactions[CombatFoePair(observer: Self.bandit, target: Self.guardKey)] = .friend
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 2)
        #expect(runtime.combatTarget(of: Self.guardKey) == Self.bandit)
        #expect(runtime.combatTarget(of: Self.bandit) == nil)
    }

    /// The bandit fights the player too, but has not seen the player: it stays on the guard.
    @Test func aFoeOfThePlayerKeepsTheNPCItFightsWhileThePlayerIsUnseen() {
        let (runtime, world) = Self.session()
        let banditSeesGuard = CombatFoePair(observer: Self.bandit, target: Self.guardKey)
        world.hostilePairs = [banditSeesGuard]
        world.pairAwareness[banditSeesGuard] = .detected(at: SIMD3(500, 0, 0))
        runtime.setHostility(.hostile, on: Self.bandit)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(runtime.combatTarget(of: Self.bandit) == Self.guardKey)
    }

    @Test func thePlayersAllyIsNoNPCFoe() {
        let (runtime, world) = Self.session()
        world.pairAwareness[Self.guardSeesBandit] = .detected(at: SIMD3(560, 0, 0))
        runtime.command(Self.bandit, by: .player)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(runtime.foePairs.isEmpty)
        #expect(runtime.combatTarget(of: Self.guardKey) == nil)
    }

    @Test func friendlyReactionsAreAllyAndFriend() {
        #expect(ActorReaction.ally.isFriendly)
        #expect(ActorReaction.friend.isFriendly)
        #expect(!ActorReaction.neutral.isFriendly)
        #expect(!ActorReaction.enemy.isFriendly)
    }
}
