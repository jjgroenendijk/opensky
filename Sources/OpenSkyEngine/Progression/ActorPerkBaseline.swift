// The perks an actor is authored with (issue #497, roadmap item 20.4): the NPC_
// `PRKR` run resolved through the template chain.
//
// Record-side and immutable, sitting beside `PerkRuntime` exactly as
// `ActorSpellBaselineResolver` sits beside `SpellbookRuntime`: this half reads
// records and knows nothing about the store, the runtime half writes the store
// and knows nothing about records.
//
// ## One list, one flag
//
// There is no race half. A RACE record carries an `SPLO` run and no perk run,
// so an actor's authored perks are the NPC_ list alone. That list inherits
// through the ACBS `Use Spell List` flag, which UESP names "Use spelllist (both
// spells and perks)" — the same flag and the same chain the spell baseline
// walks, which is why both are read out of one `resolveSpells` call rather than
// two walks of the same templates.
//
// Nothing is expanded. A `PRKR` entry names a PERK directly; there is no
// leveled-perk record for it to route through, which is the one way this
// differs from the spell baseline.
//
// Documented in docs/engine/perks.md.

import Foundation

/// Re-derives actor perk lists from plugin data.
nonisolated struct ActorPerkBaselineResolver {
    /// Template-chain resolution, which supplies the NPC_ list.
    let templates: ActorTemplateResolver

    init(templates: ActorTemplateResolver) {
        self.templates = templates
    }

    /// Built from the indexes the actor-value side already loaded, rather than
    /// walking the plugin a second time for records that are already in memory.
    init(actorValues: ActorValueResolver) {
        templates = actorValues.templates
    }

    /// The perk list plugin data authors for `base`.
    ///
    /// A broken template chain — a dangling TPLT, a cycle, an empty LVLN —
    /// resolves to an empty list rather than propagating, the rule every
    /// baseline resolver here states.
    func baseline(for base: FormID) -> [FormID] {
        guard let resolved = try? templates.resolveSpells(base: base) else { return [] }
        return resolved.perks.value
    }

    /// The perk list for one actor-value subject, which is what a runtime
    /// holding an `ActorValueHolder` actually has in hand.
    ///
    /// The player has no NPC_ record in this engine and therefore no authored
    /// perks: the player starts with none and takes them, which is what
    /// "seed the player empty" means.
    func baseline(for subject: ActorValueSubject) -> [FormID] {
        switch subject {
        case let .actor(base): baseline(for: base)
        case .player, .generated: []
        }
    }
}
