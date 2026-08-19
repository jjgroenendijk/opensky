// The seams perks were wired into (issue #497, roadmap item 20.4): the melee
// and archery attack multipliers, the block term, and the spell cost.
//
// Each test drives the number a formula produces rather than the evaluator that
// feeds it, so a seam that stops folding perks in fails here even when the
// evaluator is still right.
//
// Records are synthetic and built in code (`PerkRuntimeFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PerkSeamTests {
    private func armedRuntime(
        _ perk: UInt32
    ) throws -> (PerkRuntime, WorldStateStore) {
        var (perks, store) = try PerkRuntimeFixture.runtime()
        perks.add(PerkRuntimeFixture.key(perk), to: .player)
        return (perks, store)
    }

    /// `Mod Attack Damage` is what a swing folds in beside its fortify term:
    /// 10 base damage with a 1.2 perk lands 12.
    @Test func aDamagePerkMovesTheMeleeNumber() throws {
        var (perks, _) = try armedRuntime(PerkRuntimeFixture.Perk.damageRank1)
        let weapon = MeleeWeaponProfile(damage: 10, reach: 1, speed: 1, handType: .sword)

        let unarmedByPerks = MeleeDamage.resolve(
            weapon: weapon, block: nil, settings: .synthetic
        )
        let multiplier = perks.multiplier(
            at: PerkRuntimeFixture.attackDamage, on: .player
        )
        let withPerk = MeleeDamage.resolve(
            weapon: weapon,
            block: nil,
            settings: .synthetic,
            attackMultiplier: multiplier
        )

        #expect(unarmedByPerks.applied == 10)
        #expect(multiplier == 1.2)
        #expect(withPerk.applied == 12)
        #expect(withPerk.wasFortified)
    }

    /// A bow shot reads the same entry point, which is what makes Overdraw and
    /// Armsman one implementation.
    @Test func aDamagePerkMovesTheArcheryNumber() throws {
        var (perks, _) = try armedRuntime(PerkRuntimeFixture.Perk.damageRank1)

        let base = ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 0, skill: 0)
        let withPerk = ArcheryDamage.resolve(
            bowDamage: 10,
            arrowDamage: 0,
            skill: 0,
            bonusMultiplier: perks.multiplier(
                at: PerkRuntimeFixture.attackDamage, on: .player
            )
        )

        #expect(abs(withPerk.applied - base.applied * 1.2) < 0.0001)
    }

    /// `Mod Percent Blocked` multiplies the blocked fraction, which is where
    /// the quoted block formula puts the perk term.
    @Test func aBlockingPerkMovesTheBlockedFraction() throws {
        var (perks, _) = try armedRuntime(PerkRuntimeFixture.Perk.blocking)

        let base = MeleeDamage.blockedFraction(
            attackerDamage: 10, block: .weapon, settings: .synthetic
        )
        let withPerk = MeleeDamage.blockedFraction(
            attackerDamage: 10,
            block: .weapon,
            settings: .synthetic,
            bonusMultiplier: perks.multiplier(
                at: PerkRuntimeFixture.percentBlocked, on: .player
            )
        )

        #expect(withPerk > base)
        #expect(abs(withPerk - base * 1.25) < 0.0001)
    }

    // MARK: - Spell cost

    private func caster(
        store: WorldStateStore
    ) throws -> CasterRuntime {
        let index = try PerkRuntimeFixture.index()
        return CasterRuntime(
            spellbook: SpellbookRuntime(
                store: store,
                spells: PerkRuntimeFixture.spellStore(index: index),
                equipSlots: EquipSlotStore(index: index)
            ),
            values: PerkRuntimeFixture.values(store: store)
        )
    }

    private func flames(_ caster: CasterRuntime) throws -> ResolvedSpell {
        try #require(
            caster.spellbook.record(PerkRuntimeFixture.key(PerkRuntimeFixture.Spell.flames))
        )
    }

    /// Without the perk the caster pays the record's own cost, which is what
    /// the half-cost link meant before ownership was checked.
    @Test func theHalfCostPerkOnlyHalvesTheCostForACasterWhoOwnsIt() throws {
        let store = WorldStateStore()
        let caster = try caster(store: store)
        let spell = try flames(caster)
        var (perks, _) = try PerkRuntimeFixture.runtime(store: store)
        caster.perks = perks

        #expect(caster.cost(of: spell, caster: .player) == 20)

        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.halfCost), to: .player)
        caster.perks = perks
        #expect(caster.cost(of: spell, caster: .player) == 10)
    }

    /// `Mod Spell Cost` applies over whatever the half-cost perk left, so
    /// owning both is 20 halved and then scaled by 0.8.
    @Test func theSpellCostEntryPointAppliesOverTheHalvedCost() throws {
        let store = WorldStateStore()
        let caster = try caster(store: store)
        let spell = try flames(caster)
        var (perks, _) = try PerkRuntimeFixture.runtime(store: store)
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.spellCost), to: .player)
        caster.perks = perks

        #expect(caster.cost(of: spell, caster: .player) == 16)

        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.halfCost), to: .player)
        caster.perks = perks
        #expect(caster.cost(of: spell, caster: .player) == 8)
    }

    /// A perk that names itself in SPIT *and* hooks `Mod Spell Cost` reduces the
    /// cost once, not twice. Vanilla authors exactly that shape — `Flames` names
    /// `DestructionNovice00`, whose only effect is `Mod Spell Cost` x 0.5 — and
    /// halving on top of it would charge a quarter where the game charges a
    /// half.
    @Test func aHalfCostPerkThatHooksSpellCostReducesTheCostOnce() throws {
        let store = WorldStateStore()
        let caster = try caster(store: store)
        let index = try PerkRuntimeFixture.index()
        let spells = PerkRuntimeFixture.spellStore(index: index)
        let spell = try #require(
            spells.spell(key: PerkRuntimeFixture.key(PerkRuntimeFixture.Spell.selfHalving))
        )
        var (perks, _) = try PerkRuntimeFixture.runtime(store: store)
        perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.spellCost), to: .player)
        caster.perks = perks

        // 20 x 0.8 from the entry point, and no second reduction for the same
        // perk being named in the header.
        #expect(caster.cost(of: spell, caster: .player) == 16)
    }

    /// A session with no perk runtime pays the record's cost, which is what
    /// every synthetic scene and every pre-20.4 session did.
    @Test func aSessionWithNoPerkRuntimePaysTheRecordCost() throws {
        let store = WorldStateStore()
        let caster = try caster(store: store)

        #expect(try caster.cost(of: flames(caster), caster: .player) == 20)
    }
}
