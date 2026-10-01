// One actor's hostility toward another, derived from the records. The first
// answer wins: the runtime override (`ActorCombatState`), the crime term, the
// RELA relationship, the FACT relations, then neutral. Only "relationships
// override factions" is documented (<https://ck.uesp.net/wiki/Relationship>);
// the rest of the order is ours. `ActorReaction.provokesAttack(at:)` turns the
// reaction into hostility. See docs/engine/hostility.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Resolves what one actor makes of another from factions, relationships,
/// crime and explicit overrides.
nonisolated public struct HostilityDerivation: HostilityDeriving {
    public let relations: FactionRelationIndex
    public let relationships: RelationshipStore
    /// The crime seam. Assignable rather than injected at init, so the session can
    /// swap the bounty source without rebuilding the relation index.
    public var crime: any CrimeHostilitySource = NoCrimeHostility()

    /// The whole answer for one ordered pair.
    public func decide(
        _ observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> HostilityDecision {
        let resolved = resolveReaction(observer, toward: target)
        guard let stored = observer.hostilityOverride else {
            return HostilityDecision(
                hostility: resolved.reaction.provokesAttack(at: observer.aiData.aggression)
                    ? .hostile
                    : .neutral,
                reaction: resolved.reaction,
                source: resolved.source
            )
        }
        return HostilityDecision(
            hostility: stored,
            reaction: resolved.reaction,
            source: .runtimeOverride
        )
    }

    /// The reaction alone, for a caller that wants what the records say without
    /// the aggression table over it — a condition function asking
    /// `GetFactionReaction`, or a panel explaining a decision.
    public func reaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction {
        resolveReaction(observer, toward: target).reaction
    }

    /// The most hostile reaction any membership pair declares, in either direction.
    /// Most hostile wins (our rule; no source states one), so a friendly membership
    /// cannot silently cancel an enemy one. Vanilla does not always mirror an XNAM.
    public func factionReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        var worst: ActorReaction?
        for mine in observer.memberships.factions {
            for theirs in target.memberships.factions {
                worst = Self.moreHostile(worst, relations.reaction(of: mine, toward: theirs))
                worst = Self.moreHostile(worst, relations.reaction(of: theirs, toward: mine))
            }
        }
        return worst
    }

    /// The reaction for the pair's relationship rank, or nil when nothing names it.
    /// A scripted rank beats the record, and it is the only layer that can name
    /// the player, who has no `NPC_` base for a `RELA` record.
    public func relationshipReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        if let scripted = scriptedRank(of: observer, toward: target) {
            return RelationshipRank(signedRank: Int(scripted)).flatMap(ActorReaction.init)
        }
        guard
            let mine = observer.base,
            let theirs = target.base,
            let rank = relationships.rank(between: mine, and: theirs)
        else { return nil }
        return ActorReaction(rank)
    }

    /// The scripted rank between the pair, from either actor's component. Both
    /// sides are written by `RelationshipRuntime`, so the second lookup covers a
    /// component an older build wrote one-sided rather than a disagreement this
    /// one can produce.
    public func scriptedRank(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> Int8? {
        observer.relationshipOverrides.rank(toward: target.key)
            ?? target.relationshipOverrides.rank(toward: observer.key)
    }

    // MARK: - Private

    /// The more hostile of two reactions, either of which may be absent.
    private static func moreHostile(
        _ left: ActorReaction?,
        _ right: ActorReaction?
    ) -> ActorReaction? {
        guard let left else { return right }
        guard let right else { return left }
        return max(left, right)
    }

    private func resolveReaction(
        _ observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> (reaction: ActorReaction, source: HostilitySource) {
        if let crimeReaction = crime.crimeReaction(of: observer, toward: target) {
            return (crimeReaction, .crime)
        }
        if let related = relationshipReaction(of: observer, toward: target) {
            return (related, .relationship)
        }
        if let declared = factionReaction(of: observer, toward: target) {
            return (declared, .faction)
        }
        return (.neutral, .defaultNeutral)
    }

    public init(
        relations: FactionRelationIndex,
        relationships: RelationshipStore,
        crime: any CrimeHostilitySource = NoCrimeHostility()
    ) {
        self.relations = relations
        self.relationships = relationships
        self.crime = crime
    }
}
