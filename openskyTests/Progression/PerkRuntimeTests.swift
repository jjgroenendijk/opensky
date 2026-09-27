// Owning perks and evaluating what they do (issue #497, roadmap item 20.4):
// the component, the rank chain, condition gating through the live `HasPerk`
// function, seeding from an authored list, and the ability grant.
//
// Records are synthetic and built in code (`PerkRuntimeFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PerkRuntimeTests {
    // MARK: - Owning

    @Test func anActorStartsOwningNothingAndIsCleanForTheSlot() throws {
        let (perks, store) = try PerkRuntimeFixture.runtime()

        #expect(perks.state(of: .player).owned.isEmpty)
        #expect(store.component(PerkState.self, for: .player) == nil)
    }

    @Test func addingAndRemovingAPerkAreBothWrittenOnce() throws {
        var (perks, store) = try PerkRuntimeFixture.runtime()
        let blocking = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking)

        let added = perks.add(blocking, to: .player)
        #expect(added)
        #expect(perks.owns(blocking, on: .player))
        let addedTwice = perks.add(blocking, to: .player)
        #expect(!addedTwice)

        let removed = perks.remove(blocking, from: .player)
        #expect(removed)
        #expect(!perks.owns(blocking, on: .player))
        let removedTwice = perks.remove(blocking, from: .player)
        #expect(!removedTwice)
        // The component is dropped entirely once it empties.
        #expect(store.component(PerkState.self, for: .player) == nil)
    }

    /// A key nothing resolves is refused rather than stored: it could never be
    /// evaluated, and storing it would put a permanent unreadable entry in the
    /// save.
    @Test func aPerkThisLoadOrderDoesNotCarryIsRefusedAndCounted() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()

        let added = perks.add(PerkRuntimeFixture.key(0x0BAD), to: .player)
        #expect(!added)
        #expect(perks.state(of: .player).isEmpty)
        #expect(perks.tally.unresolvedPerks == 1)
    }

    // MARK: - Ranks

    /// A rank is the deepest owned record of an `NNAM` chain, not a count.
    @Test func rankIsThePositionOfTheDeepestOwnedRecordInTheChain() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()
        let first = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)
        let second = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank2)

        #expect(perks.rank(inChainFrom: first, on: .player) == 0)
        perks.add(first, to: .player)
        #expect(perks.rank(inChainFrom: first, on: .player) == 1)
        perks.add(second, to: .player)
        #expect(perks.rank(inChainFrom: first, on: .player) == 2)
        // Holding only the later record still reads as rank 2, which is what a
        // script that granted a rank directly leaves behind.
        perks.remove(first, from: .player)
        #expect(perks.rank(inChainFrom: first, on: .player) == 2)
    }

    // MARK: - Evaluating

    @Test func anEntryPointNoOwnedPerkHooksLeavesTheValueAlone() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()

        let untouched = perks.modify(10, at: PerkRuntimeFixture.attackDamage, on: .player)
        #expect(untouched.value == 10)
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking), to: .player)
        // Owned, but it hooks a different entry point.
        let stillUntouched = perks.modify(10, at: PerkRuntimeFixture.attackDamage, on: .player)
        #expect(stillUntouched.value == 10)
    }

    @Test func anOwnedPerkMultipliesTheValueItHooks() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1), to: .player)

        let outcome = perks.modify(10, at: PerkRuntimeFixture.attackDamage, on: .player)

        #expect(outcome.value == 12)
        #expect(outcome.applied == 1)
        #expect(outcome.didChange)
    }

    /// The rank chain's own switch: `DamageRank1` carries
    /// `HasPerk DamageRank2 == 0` on its perk-owner tab, so owning both ranks
    /// applies the second alone rather than stacking 1.2 and 1.5.
    @Test func owningTheNextRankSwitchesThePreviousOneOffThroughHasPerk() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1), to: .player)
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank2), to: .player)

        let outcome = perks.modify(10, at: PerkRuntimeFixture.attackDamage, on: .player)

        #expect(outcome.value == 15)
        #expect(outcome.applied == 1)
        #expect(perks.tally.conditionsFailed == 1)
    }

    /// The weapon tab names an object nothing in this engine can bind, so it is
    /// skipped and counted rather than failing the whole effect. This is the
    /// subsystem's one documented over-application.
    @Test func aConditionTabWithNoBoundSubjectIsSkippedAndCounted() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1), to: .player)

        _ = perks.modify(10, at: PerkRuntimeFixture.attackDamage, on: .player)

        #expect(perks.tally.unboundConditionSubjects == [.weapon: 1])
    }

    /// An actor-value function reads through the caller's closure, so the same
    /// perk answers differently for two actors.
    @Test func anActorValueFunctionReadsThroughTheCallersValueClosure() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.actorValueDamage), to: .player)

        // 10 * (1 + 50 * 0.01)
        let outcome = perks.modify(
            10,
            at: PerkRuntimeFixture.attackDamage,
            on: .player,
            actorValue: { $0 == ActorValueIndex.resistFire ? 50 : nil }
        )

        #expect(outcome.value == 15)
    }

    // MARK: - Seeding

    @Test func seedingGrantsTheAuthoredListOnceAndCountsDanglingLinks() throws {
        var (perks, _) = try PerkRuntimeFixture.runtime()
        let links = [
            FormID(PerkRuntimeFixture.Perk.blocking),
            FormID(PerkRuntimeFixture.Perk.halfCost),
            FormID(0x0BAD)
        ]

        let report = perks.seed(links, fromPlugin: PerkRuntimeFixture.pluginName, to: .player)

        #expect(report.added.count == 2)
        #expect(report.unresolved == 1)
        #expect(perks.state(of: .player).count == 2)
        // Idempotent: the same list adds nothing the second time.
        let again = perks.seed(links, fromPlugin: PerkRuntimeFixture.pluginName, to: .player)
        #expect(again.added.isEmpty)
    }

    // MARK: - Abilities

    @Test func anAbilityPerkGrantsItsSpellAndLosesItWithThePerk() throws {
        let store = WorldStateStore()
        var (perks, _) = try PerkRuntimeFixture.runtime(store: store)
        let index = try PerkRuntimeFixture.index()
        let spells = PerkRuntimeFixture.spellStore(index: index)
        var effects = ActiveEffectRuntime(
            values: PerkRuntimeFixture.values(store: store),
            effects: MagicEffectStore(index: index)
        )
        let ability = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.ability)
        let spell = PerkRuntimeFixture.key(PerkRuntimeFixture.Spell.stoneskin)

        perks.add(ability, to: .player)
        let granted = PerkAbilityApplication.reconcile(
            on: .player, perks: perks, spells: spells, using: &effects
        )
        #expect(granted.granted == [spell])
        #expect(granted.storedCount == 1)
        #expect(effects.active(on: .player).allSatisfy { $0.source.kind == .perk })

        // Reconciling again changes nothing: the reconcile is idempotent.
        let again = PerkAbilityApplication.reconcile(
            on: .player, perks: perks, spells: spells, using: &effects
        )
        #expect(!again.didChange)
        #expect(effects.active(on: .player).count == 1)

        perks.remove(ability, from: .player)
        let revoked = PerkAbilityApplication.reconcile(
            on: .player, perks: perks, spells: spells, using: &effects
        )
        #expect(revoked.revoked == [spell])
        #expect(revoked.dispelledCount == 1)
        #expect(effects.active(on: .player).isEmpty)
    }
}
