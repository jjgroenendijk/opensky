// The factions an actor is authored into (NPC_ `SNAM`) and its AI attributes
// (`AIDT`), through the template chain. Record-side; `FactionRuntime` is the store
// side. One `resolveFactions(base:)` walk answers both, as hostility needs both.
// See docs/engine/hostility.md.

import Foundation
import OpenSkyFormatsESM

/// What plugin data authors about one actor's social standing.
nonisolated public struct ActorFactionBaseline: Equatable, Sendable {
    public let memberships: [ActorBase.FactionMembership]
    public let aiData: ActorAIData
    /// The authored `CRIF`, as a raw link in the resolver's plugin. Nil for an actor
    /// that reports crimes to nobody.
    public var crimeFaction: FormID?

    /// An actor no record describes: the player, and any generated actor.
    public static let none = ActorFactionBaseline(memberships: [], aiData: .absent)
}

/// Re-derives actor faction lists and AI attributes from plugin data.
nonisolated public struct ActorFactionBaselineResolver: Sendable {
    /// Template-chain resolution, which supplies both field groups.
    public let templates: ActorTemplateResolver

    public init(templates: ActorTemplateResolver) {
        self.templates = templates
    }

    /// Built from the indexes the actor-value side already loaded, rather than
    /// walking the plugin a second time for records that are already in memory.
    public init(actorValues: ActorValueResolver) {
        templates = actorValues.templates
    }

    /// What plugin data authors for `base`. A broken template chain resolves to
    /// `ActorFactionBaseline.none`: no factions and no fights, the safe failure.
    public func baseline(for base: FormID) -> ActorFactionBaseline {
        guard let resolved = try? templates.resolveFactions(base: base) else { return .none }
        return ActorFactionBaseline(
            memberships: resolved.factions.value,
            aiData: resolved.aiData.value ?? .absent,
            crimeFaction: resolved.crimeFaction
        )
    }

    /// The baseline for one actor-value subject, which is what a runtime
    /// holding an `ActorValueHolder` actually has in hand.
    ///
    /// The player has no NPC_ record in this engine and therefore no authored
    /// memberships: every faction the player is in was joined at runtime, which
    /// is exactly what the component records.
    public func baseline(for subject: ActorValueSubject) -> ActorFactionBaseline {
        switch subject {
        case let .actor(base): baseline(for: base)
        case .player, .generated: .none
        }
    }
}
