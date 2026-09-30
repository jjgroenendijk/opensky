// Social profiles per actor for the faction and relationship condition
// functions. See docs/engine/hostility.md and docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// Every actor's social profile plus the FACT store a faction parameter resolves
/// against and the derivation that answers about a pair.
nonisolated public struct FactionConditionResolution: Sendable {
    public let facts: ActorConditionFacts<FactionStore, ActorSocialProfile>
    /// The same derivation the combat loop uses, so a condition and combat
    /// never disagree about hostility.
    public let derivation: (any HostilityDeriving)?

    public static let empty = FactionConditionResolution()

    public init(
        factions: FactionStore? = nil,
        sourcePlugin: String? = nil,
        derivation: (any HostilityDeriving)? = nil,
        profiles: [ReferenceKey: ActorSocialProfile] = [:]
    ) {
        facts = ActorConditionFacts(store: factions, sourcePlugin: sourcePlugin, facts: profiles)
        self.derivation = derivation
    }

    public var isAvailable: Bool {
        facts.isAvailable && derivation != nil
    }

    public func key(of formID: FormID) -> ReferenceKey? {
        facts.key(of: formID)
    }

    /// Nil for an actor no cell has streamed, or a key that names no actor.
    public func profile(of key: ReferenceKey) -> ActorSocialProfile? {
        guard isAvailable else { return nil }
        return facts.fact(of: key)
    }

    public func isMember(_ actor: ReferenceKey, of faction: ReferenceKey) -> Bool? {
        profile(of: actor)?.memberships.isMember(of: faction)
    }

    /// Nil when `actor` is not a member. The condition function and the Papyrus
    /// native spell that case as different numbers.
    public func rank(of actor: ReferenceKey, in faction: ReferenceKey) -> Int8? {
        profile(of: actor)?.memberships.rank(in: faction)
    }

    /// Nil when either actor has no profile. No declared relation reads as
    /// `.neutral`, the Creation Kit default, because `GetFactionRelation` has
    /// no value for "unrelated".
    public func factionReaction(
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> ActorReaction? {
        guard
            let derivation,
            let mine = profile(of: observer),
            let theirs = profile(of: target)
        else { return nil }
        return derivation.factionReaction(of: mine, toward: theirs) ?? .neutral
    }

    /// The signed relationship rank, from a script first and a `RELA` record
    /// second. Nil when neither names the pair.
    public func relationshipRank(of observer: ReferenceKey, toward target: ReferenceKey) -> Int8? {
        guard
            let derivation,
            let mine = profile(of: observer),
            let theirs = profile(of: target)
        else { return nil }
        if let scripted = derivation.scriptedRank(of: mine, toward: theirs) {
            return scripted
        }
        guard
            let base = mine.base,
            let otherBase = theirs.base,
            let signed = derivation.relationships.rank(between: base, and: otherBase)?
                .signedRank
        else { return nil }
        return Int8(clamping: signed)
    }

    public func isHostile(_ observer: ReferenceKey, toward target: ReferenceKey) -> Bool? {
        guard
            let derivation,
            let mine = profile(of: observer),
            let theirs = profile(of: target)
        else { return nil }
        return derivation.decide(mine, toward: theirs).isHostile
    }
}

nonisolated extension FactionConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// Empty when no faction runtime is wired, so every faction and
    /// relationship function is a reason-tagged false rather than an actor who
    /// belongs to nothing.
    public var factions: FactionConditionResolution {
        get { self[resolution: FactionConditionResolution.self] }
        set { self[resolution: FactionConditionResolution.self] = newValue }
    }
}
