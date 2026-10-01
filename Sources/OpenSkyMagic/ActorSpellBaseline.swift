// The spells an actor is authored with: the NPC_ `SPLO` run through the template chain
// (ACBS `Use Spell List`) plus its traits race's `SPLO`. Record-side and immutable.
// LVSP entries are expanded with `LeveledList.deterministicEntry`, because vanilla
// casters keep their attack spells there (`LvlBanditWizard`). See
// docs/engine/ai-spell-use.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One actor's authored spell list, kept split so an inspector can say which
/// half a spell came from.
nonisolated public struct ActorSpellBaseline: Equatable, Sendable {
    /// The NPC_'s own `SPLO` run, from whichever chain record supplies it.
    public let actorSpells: [FormID]
    /// The `SPLO` run on the RACE the actor is a member of.
    public let raceSpells: [FormID]

    /// Both lists, actor first, with a FormID named by both kept once. Order is
    /// the record's own, so two runs of the same session grant the same list in
    /// the same sequence.
    public var all: [FormID] {
        var seen: Set<UInt32> = []
        return (actorSpells + raceSpells).filter { seen.insert($0.rawValue).inserted }
    }

    /// An actor with no records behind it — a summon, a synthetic fixture.
    public static let none = ActorSpellBaseline(actorSpells: [], raceSpells: [])
}

/// Re-derives actor spell lists from plugin data.
nonisolated public struct ActorSpellBaselineResolver: Sendable {
    /// Deepest leveled-spell nesting followed before expansion gives up. The
    /// visited set catches a list that points at itself; this cap catches the
    /// long chain that is technically acyclic and still nonsense. The same
    /// number and the same reason as `InventoryBaselineResolver`.
    public static let maximumLeveledDepth = 8

    /// Template-chain resolution, which supplies the NPC_ list, the race and
    /// the LVSP index an entry may route through.
    public let templates: ActorTemplateResolver
    /// RACE decodes by raw FormID, which supply the race list.
    public let races: [UInt32: Race]

    /// Built from the indexes the actor-value side already loaded, rather than
    /// walking the plugin a second time for records that are already in memory.
    public init(actorValues: ActorValueResolver) {
        templates = actorValues.templates
        races = actorValues.races
    }

    public init(templates: ActorTemplateResolver, races: [UInt32: Race]) {
        self.templates = templates
        self.races = races
    }

    /// The spell list plugin data authors for `base`. A broken template chain gives an
    /// empty baseline, as in `InventoryBaselineResolver.actorBaseline`.
    public func baseline(for base: FormID) -> ActorSpellBaseline {
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
    public func baseline(for subject: ActorValueSubject) -> ActorSpellBaseline {
        switch subject {
        case let .actor(base): baseline(for: base)
        case .player, .generated: .none
        }
    }
}
