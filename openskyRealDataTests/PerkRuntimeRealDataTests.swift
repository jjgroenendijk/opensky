// Env-gated perk-runtime spot check over the user's read-only active load
// order (issue #497, roadmap item 20.4): grant the player a pinned vanilla
// damage perk and assert the melee number moves in the documented direction and
// magnitude. Counts, editor IDs and derived numbers only — no game bytes leave
// the run.

import Foundation
@testable import opensky
import Testing

struct PerkRuntimeRealDataTests {
    /// `nonisolated` so the `.enabled(if:)` trait can read it from the sendable
    /// closure the macro builds; the test bodies are `@MainActor` because the
    /// runtimes they drive write through `WorldStateStore`.
    nonisolated private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// A ten-damage swing, which is a sword's order of magnitude and keeps the
    /// assertion arithmetic rather than data-dependent.
    private static let baseDamage: Float = 10

    @MainActor
    private static func runtime(root: GameDataRoot) -> (PerkRuntime, PerkStore) {
        let store = PerkStoreLoader.load(root: root)
        return (PerkRuntime(store: WorldStateStore(), perks: store), store)
    }

    /// `Armsman00` is authored as `Mod Attack Damage` × 1.2 with a perk-owner
    /// tab carrying `HasPerk Armsman20 == 0` and a weapon-type tab this engine
    /// binds no reference for. So a player who owns the first rank alone deals
    /// exactly 1.2× the WEAP base, and the skipped weapon tab is counted rather
    /// than silently widening the perk.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
    func grantingArmsmanMovesTheMeleeNumberByTheAuthoredFactor() throws {
        let root = try #require(Self.dataRoot)
        var (perks, store) = Self.runtime(root: root)
        let armsman = try #require(store.perk(editorID: "Armsman00"))
        let weapon = MeleeWeaponProfile(damage: Self.baseDamage, reach: 1, handType: .sword)

        let before = MeleeDamage.resolve(weapon: weapon, block: nil, settings: .synthetic)
        #expect(before.applied == Self.baseDamage)

        perks.add(ReferenceKey(resolved: armsman.id), to: .player)
        let multiplier = perks.multiplier(at: PerkEntryPoint(rawValue: 35), on: .player)
        let after = MeleeDamage.resolve(
            weapon: weapon,
            block: nil,
            settings: .synthetic,
            attackMultiplier: multiplier
        )

        #expect(multiplier > 1)
        #expect(abs(multiplier - 1.2) < 0.0001)
        #expect(after.applied > before.applied)
        #expect(abs(after.applied - Self.baseDamage * 1.2) < 0.001)
        #expect(perks.tally.unboundConditionSubjects[.weapon] == 1)
        print(
            "[INFO] Armsman00: melee \(before.applied) -> \(after.applied) "
                + "(x\(multiplier)), unbound tabs "
                + "\(perks.tally.unboundConditionSubjects.count)"
        )
    }

    /// The rank chain's own switch, against the real records: owning both ranks
    /// applies the later one alone, because `Armsman00` carries
    /// `HasPerk Armsman20 == 0`. Without the `HasPerk` condition function every
    /// rank of every vanilla chain would stack.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
    func aLaterRankSwitchesTheEarlierOneOff() throws {
        let root = try #require(Self.dataRoot)
        var (perks, store) = Self.runtime(root: root)
        let first = try #require(store.perk(editorID: "Armsman00"))
        let second = try #require(store.perk(editorID: "Armsman20"))
        let attackDamage = PerkEntryPoint(rawValue: 35)

        perks.add(ReferenceKey(resolved: first.id), to: .player)
        perks.add(ReferenceKey(resolved: second.id), to: .player)
        let outcome = perks.modify(
            Self.baseDamage, at: attackDamage, on: .player
        )

        // The second rank alone: 1.4 rather than 1.2 x 1.4.
        #expect(outcome.applied == 1)
        #expect(abs(outcome.value - Self.baseDamage * 1.4) < 0.001)
        #expect(perks.tally.conditionsFailed >= 1)
        print(
            "[INFO] Armsman00 + Armsman20: \(Self.baseDamage) -> \(outcome.value), "
                + "effects applied \(outcome.applied)"
        )
    }

    /// The spell-cost seam against a real record.
    ///
    /// `Flames` costs 24 and names `DestructionNovice00` in SPIT, and that
    /// perk's only effect is `Mod Spell Cost` x 0.5 — the same discount authored
    /// twice. A caster who owns it pays half, not a quarter, which is what the
    /// no-double-count rule in `CasterRuntimePerkCost` exists for.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
    func theHalfCostPerkHalvesARealSpellOnlyForItsOwner() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins, recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "PERK"]
        )
        let spells = SpellStore(index: index, effects: MagicEffectStore(index: index))
        let store = WorldStateStore()
        let caster = CasterRuntime(
            spellbook: SpellbookRuntime(
                store: store, spells: spells, equipSlots: EquipSlotStore(index: index)
            ),
            values: ActorValueRuntime(store: store, baselines: ActorValueBaselineResolver())
        )
        var perks = PerkRuntime(store: store, perks: PerkStore(index: index, spells: spells))
        // Flames is the vanilla Novice Destruction spell every character starts
        // with, and its SPIT names the Novice Destruction perk.
        let flames = try #require(spells.spell(editorID: "Flames"))
        let link = try #require(flames.data?.halfCostPerk)
        let perk = try #require(perks.perks.resolve(link, fromPlugin: flames.sourcePlugin))

        caster.perks = perks
        let full = caster.cost(of: flames, caster: .player)
        perks.add(ReferenceKey(resolved: perk.id), to: .player)
        caster.perks = perks
        let halved = caster.cost(of: flames, caster: .player)

        #expect(full > 0)
        #expect(abs(halved - full / 2) < 0.001)
        // Not a quarter: the header link and the entry point are one discount.
        #expect(halved > full / 4)
        #expect(CasterRuntime.reducesSpellCost(perk))
        print(
            "[INFO] \(flames.displayName) cost \(full) -> \(halved) with "
                + "\(perk.editorID ?? perk.id.description)"
        )
    }
}
