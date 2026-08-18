// The spells an actor is authored with (issue #473, roadmap item 19.10): the
// NPC_ `SPLO` run resolved through the template chain, plus the `SPLO` run on
// the RACE it is a member of.
//
// Record-side and immutable, sitting beside `SpellbookRuntime` exactly as
// `InventoryBaselineResolver` sits beside `InventoryRuntime`: this half reads
// records and knows nothing about the store, the runtime half writes the store
// and knows nothing about records. Nothing here mutates after `init`, so it is
// freely readable from the cell-build queue.
//
// ## Where the two lists come from
//
// Both are `SPLO` runs and both were already decoded: `ActorBase.spells` for the
// NPC_ and `Race.spells` for the RACE, each documented against UESP's
// "Skyrim Mod:Mod File Format/NPC_" and "/RACE". What 19.10 adds is only the
// resolution around them — which record in a template chain actually supplies
// the actor's list, and which race's list rides along with it.
//
// The NPC_ list inherits through the ACBS `Use Spell List` flag, which is its
// own template-data bit (UESP NPC_ ACBS template flags name it beside Use Stats
// and Use Inventory), so it resolves exactly as the stats and the outfit do:
// a record delegates its list upward only while that one flag stays set.
//
// The race list rides `useTraits`, because the race an actor *is* is the traits
// race — the same field the renderer skins it with — and a race's spells are
// the abilities every member of it carries.
//
// ## An entry may name a leveled spell list
//
// Observed against `Skyrim.esm` rather than assumed: `LvlBanditWizard` carries
// seven `SPLO` entries and every one that resolves to a SPEL is a self buff or
// a heal. Its attack spells are behind two `LVSP` records
// (`LSpellBandit03FireFrostShock` and `LSpellBandit05FireFrostShock`), each
// holding three alternatives at level 1 — a bolt, an ice spike and a lightning
// bolt in the first, their master-level counterparts in the second. Without
// expanding those, a vanilla caster knows nothing it could ever throw at
// anybody, which is why 19.10 expands them.
//
// The entry chosen is `LeveledList.deterministicEntry` — highest level, first
// among ties — the same policy the TPLT chain applies to an LVLN hop and the
// outfit chain applies to an LVLI hop. Rolling against player level and chance
// none is the same open question there and is answered in one place when it is
// answered at all.
//
// Documented in docs/engine/magic.md.

import Foundation

/// One actor's authored spell list, kept split so an inspector can say which
/// half a spell came from.
nonisolated struct ActorSpellBaseline: Equatable, Sendable {
    /// The NPC_'s own `SPLO` run, from whichever chain record supplies it.
    let actorSpells: [FormID]
    /// The `SPLO` run on the RACE the actor is a member of.
    let raceSpells: [FormID]

    /// Both lists, actor first, with a FormID named by both kept once. Order is
    /// the record's own, so two runs of the same session grant the same list in
    /// the same sequence.
    var all: [FormID] {
        var seen: Set<UInt32> = []
        return (actorSpells + raceSpells).filter { seen.insert($0.rawValue).inserted }
    }

    /// An actor with no records behind it — a summon, a synthetic fixture.
    static let none = ActorSpellBaseline(actorSpells: [], raceSpells: [])
}

/// Re-derives actor spell lists from plugin data.
nonisolated struct ActorSpellBaselineResolver {
    /// Deepest leveled-spell nesting followed before expansion gives up. The
    /// visited set catches a list that points at itself; this cap catches the
    /// long chain that is technically acyclic and still nonsense. The same
    /// number and the same reason as `InventoryBaselineResolver`.
    static let maximumLeveledDepth = 8

    /// Template-chain resolution, which supplies the NPC_ list, the race and
    /// the LVSP index an entry may route through.
    let templates: ActorTemplateResolver
    /// RACE decodes by raw FormID, which supply the race list.
    let races: [UInt32: Race]

    /// Built from the indexes the actor-value side already loaded, rather than
    /// walking the plugin a second time for records that are already in memory.
    init(actorValues: ActorValueResolver) {
        templates = actorValues.templates
        races = actorValues.races
    }

    init(templates: ActorTemplateResolver, races: [UInt32: Race]) {
        self.templates = templates
        self.races = races
    }

    /// The spell list plugin data authors for `base`.
    ///
    /// A broken template chain — a dangling TPLT, a cycle, an empty LVLN —
    /// resolves to an empty baseline rather than propagating, which is the rule
    /// `InventoryBaselineResolver.actorBaseline` states: an actor whose chain
    /// does not resolve has no appearance either, and that path already reports
    /// the failure.
    func baseline(for base: FormID) -> ActorSpellBaseline {
        guard let resolved = try? templates.resolveSpells(base: base) else { return .none }
        let race = resolved.race.value.flatMap { races[$0.rawValue] }
        return ActorSpellBaseline(
            actorSpells: expand(resolved.spells.value),
            raceSpells: expand(race?.spells ?? [])
        )
    }

    /// `list` with every entry that names an LVSP replaced by the one spell
    /// that list's deterministic policy chooses.
    ///
    /// An entry naming nothing this index knows is kept as it is: it may be a
    /// SPEL, which this type does not resolve — `SpellbookRuntime.resolve` is
    /// what decides whether a link is a spell the load order still carries.
    private func expand(_ list: [FormID]) -> [FormID] {
        list.flatMap { expand($0, depth: 0, visiting: []) }
    }

    private func expand(
        _ id: FormID,
        depth: Int,
        visiting: Set<UInt32>
    ) -> [FormID] {
        guard
            depth < Self.maximumLeveledDepth,
            let list = templates.leveledSpells[id.rawValue],
            !visiting.contains(id.rawValue)
        else { return [id] }
        guard let entry = list.deterministicEntry else { return [] }
        return expand(
            entry.reference,
            depth: depth + 1,
            visiting: visiting.union([id.rawValue])
        )
    }

    /// The spell list for one actor-value subject, which is what a runtime
    /// holding an `ActorValueHolder` actually has in hand.
    func baseline(for subject: ActorValueSubject) -> ActorSpellBaseline {
        switch subject {
        case let .actor(base): baseline(for: base)
        case .player, .generated: .none
        }
    }
}
