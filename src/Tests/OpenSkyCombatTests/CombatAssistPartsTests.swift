// The combat helper rules over a fake `CombatWorld`: hit facts, the hit reaction
// list, danger threats, and the aggro radius reach the readout.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import simd
import Testing

@MainActor
struct CombatAssistPartsTests {
    private static let foe = ReferenceKey.generated(7)

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    /// An attack with no attack data keeps the weapon's own stagger.
    @Test func aHitReadsItsFactsAndIsListed() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.foe, feet: SIMD3(5, 0, 0))]
        let coordinator = Self.coordinator(world)
        let loop = coordinator.loopWorld
        let fromFoe = loop.combatHitFacts(from: Self.foe, on: .player, weaponStagger: 0.5)
        #expect(fromFoe.attackStagger == 0.5)
        #expect(!fromFoe.targetRuns)
        let onFoe = coordinator.meleeWorld.meleeHitFacts(
            on: Self.foe, event: "attackStart", weaponStagger: 0.25
        )
        #expect(onFoe.attackStagger == 0.25)
        var hit = HitReactionHit()
        hit.facts = onFoe
        let report = HitReactionReport(
            attacker: .player, target: Self.foe, hit: hit, reaction: HitReaction()
        )
        loop.noteCombatHitReaction(report)
        coordinator.meleeWorld.noteHitReaction(report)
        #expect(coordinator.assistReadout.reactions == [report, report])
        #expect(coordinator.assistReadout.autoAim == nil)
    }

    @Test func withoutShotsOrRecordsThereIsNoDangerAndNoRadius() {
        let world = FakeCoordinatorWorld()
        let loop = Self.coordinator(world).loopWorld
        #expect(loop.combatDangerThreats().isEmpty)
        #expect(loop.combatHealth(of: Self.foe) == 100)
        #expect(loop.combatAggroRadius(of: Self.foe) == nil)
    }

    /// A threat from the actor itself does not count, so its score stays 0.
    @Test func anActorIgnoresItsOwnThreat() {
        let (runtime, world) = CombatLoopFixture.session()
        CombatLoopFixture.engage(runtime, world)
        let key = CombatLoopFixture.opponent
        world.dangerThreats = [
            DangerThreat(
                id: 1,
                source: key,
                position: CombatLoopFixture.closeFeet,
                damage: 100,
                radius: 500
            )
        ]
        CombatLoopFixture.run(runtime, seconds: 0.5)
        #expect(runtime.dangerWatches[key]?.score == 0)
        #expect(!runtime.isRecoiling(key))
        #expect(!runtime.fightsRanged(key))
    }

    @Test func anAimPickKeepsItsTargetAndHand() {
        let target = ProjectileAimCandidate(key: Self.foe, centre: .zero, top: SIMD3(0, 0, 1))
        let pick = ProjectileAimPick(target: target, rightHandIsFree: true)
        #expect(pick.target.key == Self.foe)
        #expect(pick.rightHandIsFree)
    }
}
