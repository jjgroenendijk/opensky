// A calm helper beside a guard that attacks a bandit: it asks only about an ally it
// detects, and a helper with a Morality stays out of a fight its ally started.
// See docs/engine/combat.md#who-an-assisting-actor-fights.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import simd
import Testing

@MainActor
struct CombatAssistMoralityTests {
    private typealias Fixture = CombatLoopFixture
    private static let guardKey = Fixture.opponent
    private static let bandit = Fixture.second
    private static let helper = ReferenceKey.generated(3)
    private static let guardSeesBandit = CombatFoePair(observer: guardKey, target: bandit)

    /// The guard attacks the bandit on sight, so the guard started the fight.
    private static func session() -> (runtime: CombatLoopRuntime, world: FakeCombatWorld) {
        let (runtime, world) = Fixture.session(feet: SIMD3(500, 0, 0))
        world.actors.append(CombatActorObservation(
            key: bandit, feet: SIMD3(560, 0, 0), name: "Bandit"
        ))
        world.actors.append(CombatActorObservation(
            key: helper, feet: SIMD3(440, 0, 0), name: "Helper"
        ))
        world.weapons[bandit] = MeleeWeaponProfile(damage: 5, reach: 1)
        world.weapons[helper] = MeleeWeaponProfile(damage: 5, reach: 1)
        world.hostilePairs = [guardSeesBandit]
        world.pairAwareness[guardSeesBandit] = .detected(at: SIMD3(560, 0, 0))
        world.assistPairs = [CombatFoePair(observer: helper, target: guardKey)]
        return (runtime, world)
    }

    @Test func theGuardThatAttacksOnSightStartedTheFightAndTheBanditDidNot() {
        let (runtime, world) = Self.session()
        withExtendedLifetime(world) { Fixture.run(runtime, seconds: Fixture.cycleSeconds) }
        #expect(runtime.aggressors.contains(Self.guardKey))
        #expect(!runtime.aggressors.contains(Self.bandit))
    }

    @Test func aHelperThatDoesNotDetectItsAllyStaysOutAndPerceptionWatchesThePair() {
        let (runtime, world) = Self.session()
        withExtendedLifetime(world) { Fixture.run(runtime, seconds: 0.5) }
        #expect(runtime.npcAssists.isEmpty)
        #expect(runtime.watchedPairs.contains(
            CombatFoePair(observer: Self.helper, target: Self.guardKey)
        ))
    }

    @Test func aHelperWithAMoralityStaysOutOfTheFightItsAllyStarted() {
        let (runtime, world) = Self.session()
        world.awareness[Self.helper] = .detected(at: SIMD3(500, 0, 0))
        world.moralities[Self.helper] = 3
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 2)
        #expect(runtime.npcAssists.isEmpty)
        #expect(runtime.combatTarget(of: Self.helper) == nil)
    }

    @Test func aHelperWithNoMoralityHelpsAndTakesTheGuardsMark() {
        let (runtime, world) = Self.session()
        world.awareness[Self.helper] = .detected(at: SIMD3(500, 0, 0))
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 3)
        #expect(runtime.npcAssists[Self.helper] == Self.bandit)
        #expect(runtime.aggressors.contains(Self.helper))
    }

    @Test func theHelpViewAsksTheWorldAboutCrimes() {
        let (runtime, world) = Self.session()
        let view = CombatHelpView(runtime: runtime, world: world)
        #expect(!view.attacksPlayerOnSightForCrimes(Self.helper))
        world.crimeAttackers = [Self.helper]
        #expect(view.attacksPlayerOnSightForCrimes(Self.helper))
        world.crimeStandings[CombatFoePair(observer: Self.helper, target: .player)] =
            .criminalWhileAGuardFights
        #expect(!view.committedCrime(.player, judgedBy: Self.helper))
    }

    @Test func aScriptStartMarksTheAttackerUnlessItIsAGuard() {
        let (runtime, world) = Self.session()
        world.hostilePairs = []
        world.guards = [Self.bandit]
        runtime.startCombat(Self.guardKey, with: .player)
        runtime.startCombat(Self.bandit, with: .player)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(runtime.aggressors.contains(Self.guardKey))
        #expect(!runtime.aggressors.contains(Self.bandit))
        runtime.stopCombat(Self.guardKey)
        #expect(!runtime.aggressors.contains(Self.guardKey))
    }
}
