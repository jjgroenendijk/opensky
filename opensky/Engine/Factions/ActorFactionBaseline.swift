// The factions an actor is authored into and the AI attributes it fights by
// (issue #503, roadmap item 21.3): the NPC_ `SNAM` run and the `AIDT` struct,
// both resolved through the template chain.
//
// Record-side and immutable, sitting beside `FactionRuntime` exactly as
// `ActorPerkBaselineResolver` sits beside `PerkRuntime`: this half reads
// records and knows nothing about the store, the runtime half writes the store
// and knows nothing about records.
//
// One walk answers both questions because `ActorTemplateResolver`
// `resolveFactions(base:)` resolves them together — the memberships on
// `useFactions`, the AI data on `useAIData` — and the hostility derivation
// needs both at once.
//
// Documented in docs/engine/combat.md.

import Foundation

/// What plugin data authors about one actor's social standing.
nonisolated struct ActorFactionBaseline: Equatable {
    let memberships: [ActorBase.FactionMembership]
    let aiData: ActorAIData

    /// An actor no record describes: the player, and any generated actor.
    static let none = ActorFactionBaseline(memberships: [], aiData: .absent)
}

/// Re-derives actor faction lists and AI attributes from plugin data.
nonisolated struct ActorFactionBaselineResolver {
    /// Template-chain resolution, which supplies both field groups.
    let templates: ActorTemplateResolver

    init(templates: ActorTemplateResolver) {
        self.templates = templates
    }

    /// Built from the indexes the actor-value side already loaded, rather than
    /// walking the plugin a second time for records that are already in memory.
    init(actorValues: ActorValueResolver) {
        templates = actorValues.templates
    }

    /// What plugin data authors for `base`.
    ///
    /// A broken template chain — a dangling TPLT, a cycle, an empty LVLN —
    /// resolves to `ActorFactionBaseline.none` rather than propagating, the
    /// rule every baseline resolver here states. An actor whose chain cannot be
    /// walked then belongs to nothing and starts no fights, which is the safe
    /// direction for a failure to fall.
    func baseline(for base: FormID) -> ActorFactionBaseline {
        guard let resolved = try? templates.resolveFactions(base: base) else { return .none }
        return ActorFactionBaseline(
            memberships: resolved.factions.value,
            aiData: resolved.aiData.value ?? .absent
        )
    }

    /// The baseline for one actor-value subject, which is what a runtime
    /// holding an `ActorValueHolder` actually has in hand.
    ///
    /// The player has no NPC_ record in this engine and therefore no authored
    /// memberships: every faction the player is in was joined at runtime, which
    /// is exactly what the component records.
    func baseline(for subject: ActorValueSubject) -> ActorFactionBaseline {
        switch subject {
        case let .actor(base): baseline(for: base)
        case .player, .generated: .none
        }
    }
}
