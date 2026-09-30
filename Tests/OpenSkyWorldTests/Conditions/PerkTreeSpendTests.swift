// Spending a perk point: the tree, the rank order, the perk's own conditions,
// and the typed refusal for each. The synthetic tree has the shape of vanilla
// `AVOneHanded`: an empty entry node, one box off it, two boxes off that, and a
// rank chain whose higher ranks are in no box.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionTesting
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PerkTreeSpendTests {
    private struct Harness {
        let validator: PerkTreeSpendValidator
        var runtime: PerkRuntime
        let trees: PerkTreeIndex
        let store: WorldStateStore
    }

    private func harness(oneHanded: Float = 15) throws -> Harness {
        let index = try PerkRuntimeFixture.index()
        let store = WorldStateStore()
        var runtime = PerkRuntime(
            store: store, perks: PerkRuntimeFixture.perkStore(index: index),
            conditionRegistry: .standard
        )
        runtime.conditions = ConditionContext()
        let trees = PerkRuntimeFixture.trees(index: index)
        return Harness(
            validator: PerkTreeSpendValidator(
                runtime: runtime,
                trees: trees,
                conditionRegistry: .standard
            ),
            runtime: runtime,
            trees: trees,
            store: store
        )
    }

    /// The condition context the record's own `CTDA` run is judged in: one
    /// player whose One-Handed base is whatever the case needs.
    private func conditions(oneHanded: Float) -> ConditionContext {
        ConditionContext(
            actors: ActorStateResolution(states: [
                .player: ActorConditionState(
                    current: ActorValues(repeating: 100),
                    maximums: ActorValues(repeating: 100),
                    generalBaseline: [PerkRuntimeFixture.oneHandedIndex: oneHanded]
                )
            ]),
            subject: .player
        )
    }

    private func refusal(
        _ harness: Harness,
        _ perk: UInt32,
        oneHanded: Float = 15
    ) -> PerkSpendRefusal? {
        harness.validator.refusal(
            for: PerkRuntimeFixture.key(perk),
            on: .player,
            conditions: conditions(oneHanded: oneHanded)
        )
    }

    /// The tree index finds every box and nothing that is not one: the four
    /// records with a `PNAM` minus the entry node, which grants no perk.
    @Test func theTreeIndexesOnlyItsBoxes() throws {
        let harness = try harness()

        #expect(harness.trees.count == 3)
        let head = try #require(
            harness.trees.placement(of: PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1))
        )
        #expect(head.reachableFromRoot)
        #expect(head.parents.isEmpty)
        #expect(head.actorValueIndex == PerkRuntimeFixture.oneHandedIndex)

        let child = try #require(
            harness.trees.placement(of: PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking))
        )
        #expect(!child.reachableFromRoot)
        #expect(child.parents == [PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)])
    }

    /// The first box of a tree hangs off the entry node, so it is buyable with
    /// nothing owned and no conditions to meet.
    @Test func theFirstBoxIsBuyableWithNothingOwned() throws {
        let harness = try harness()

        #expect(refusal(harness, PerkRuntimeFixture.Perk.damageRank1) == nil)
    }

    /// A box whose only line comes from another box is refused until that box
    /// is owned, and accepted afterwards.
    @Test func aChildBoxNeedsItsParentOwned() throws {
        var harness = try harness()

        #expect(refusal(harness, PerkRuntimeFixture.Perk.blocking) == .parentMissing)

        harness.runtime.add(
            PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1), to: .player
        )

        #expect(refusal(harness, PerkRuntimeFixture.Perk.blocking) == nil)
    }

    /// A higher rank is in no box of its own, so it is found through the chain
    /// head — and refused until the rank below it is owned.
    @Test func aHigherRankNeedsTheRankBelowIt() throws {
        var harness = try harness()
        let rank1 = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)

        #expect(
            refusal(harness, PerkRuntimeFixture.Perk.damageRank2)
                == .previousRankMissing(rank1)
        )

        harness.runtime.add(rank1, to: .player)

        #expect(refusal(harness, PerkRuntimeFixture.Perk.damageRank2) == nil)
    }

    /// The record's own condition run is the skill requirement, and it is what
    /// refuses a box whose tree parent is already owned.
    @Test func aSkillRequirementRefusesUntilTheSkillIsHighEnough() throws {
        var harness = try harness()
        harness.runtime.add(
            PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1), to: .player
        )

        #expect(
            refusal(harness, PerkRuntimeFixture.Perk.skillGated, oneHanded: 49)
                == .unmetCondition
        )
        #expect(refusal(harness, PerkRuntimeFixture.Perk.skillGated, oneHanded: 50) == nil)
    }

    /// A perk already owned buys nothing, and is refused before any tree rule
    /// is consulted.
    @Test func anOwnedPerkIsRefused() throws {
        var harness = try harness()
        harness.runtime.add(
            PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1), to: .player
        )

        #expect(refusal(harness, PerkRuntimeFixture.Perk.damageRank1) == .alreadyOwned)
    }

    /// A perk no tree grants — a quest perk, an ability handed out directly —
    /// cannot be bought with a point.
    @Test func aPerkOutsideEveryTreeIsRefused() throws {
        let harness = try harness()

        #expect(refusal(harness, PerkRuntimeFixture.Perk.ability) == .notInPerkTree)
        #expect(refusal(harness, PerkRuntimeFixture.Perk.halfCost) == .notInPerkTree)
    }

    /// A key this load order carries no record for is an answer, not a trap.
    @Test func anUnresolvedPerkIsRefused() throws {
        let harness = try harness()

        #expect(refusal(harness, 0xDEAD) == .unresolvedPerk)
    }

    /// A session with no AVIF records refuses every spend rather than accepting
    /// one against a tree that does not exist.
    @Test func aSessionWithNoTreesRefusesEverySpend() throws {
        let index = try PerkRuntimeFixture.index()
        let runtime = PerkRuntime(
            store: WorldStateStore(), perks: PerkRuntimeFixture.perkStore(index: index),
            conditionRegistry: .standard
        )
        let validator = PerkTreeSpendValidator(
            runtime: runtime,
            trees: .empty,
            conditionRegistry: .standard
        )

        #expect(
            validator.refusal(
                for: PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1),
                on: .player,
                conditions: conditions(oneHanded: 100)
            ) == .notInPerkTree
        )
    }
}
