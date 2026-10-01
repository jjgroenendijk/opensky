// The perks an actor is authored with: the NPC_ `PRKR` run through the template
// chain. Record-side; `PerkRuntime` is the store side. A RACE has no perk run, and
// the ACBS "Use spelllist (both spells and perks)" flag (UESP) drives inheritance,
// so one `resolveSpells` walk serves both. See docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// Re-derives actor perk lists from plugin data.
nonisolated public struct ActorPerkBaselineResolver: Sendable {
    /// Template-chain resolution, which supplies the NPC_ list.
    public let templates: ActorTemplateResolver

    public init(templates: ActorTemplateResolver) {
        self.templates = templates
    }

    /// Built from the indexes the actor-value side already loaded, rather than
    /// walking the plugin a second time for records that are already in memory.
    public init(actorValues: ActorValueResolver) {
        templates = actorValues.templates
    }

    /// The perk list plugin data authors for `base`.
    ///
    /// A broken template chain — a dangling TPLT, a cycle, an empty LVLN —
    /// resolves to an empty list rather than propagating, the rule every
    /// baseline resolver here states.
    public func baseline(for base: FormID) -> [FormID] {
        guard let resolved = try? templates.resolveSpells(base: base) else { return [] }
        return resolved.perks.value
    }

    /// The perk list for one actor-value subject, which is what a runtime
    /// holding an `ActorValueHolder` actually has in hand.
    ///
    /// The player has no NPC_ record in this engine and therefore no authored
    /// perks: the player starts with none and takes them, which is what
    /// "seed the player empty" means.
    public func baseline(for subject: ActorValueSubject) -> [FormID] {
        switch subject {
        case let .actor(base): baseline(for: base)
        case .player, .generated: []
        }
    }
}
