import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
public import OpenSkyGameData

/// Resolves what one actor makes of another from factions, relationships,
/// crime and explicit overrides.
nonisolated public struct HostilityDerivation: Sendable {
    public var relations: FactionRelationIndex
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
            // A crime makes even an unaggressive witness attack: the alarm's Fight is an
            // attack, not a hostility test (docs/engine/crime-reports.md#the-alarm-package).
            let attacks = resolved.source == .crime
                ? resolved.reaction == .enemy
                : resolved.reaction.provokesAttack(at: observer.aiData.aggression)
            return HostilityDecision(
                hostility: attacks ? .hostile : .neutral,
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
    /// `GetFactionReaction`, or a readout explaining a decision.
    public func reaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction {
        resolveReaction(observer, toward: target).reaction
    }

    /// The observer's factions' relations toward the target's factions, merged the
    /// game's way: a Friend pair beats any Enemy pair. The target's relations back are
    /// not read, and a membership at rank -1 takes no part.
    public func factionReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        var merged: ActorReaction?
        for mine in Self.counted(observer) {
            for theirs in Self.counted(target) {
                merged = ActorReaction.merged(merged, relations.reaction(of: mine, toward: theirs))
                if merged == .ally {
                    return merged
                }
            }
        }
        return merged
    }

    private static func counted(_ profile: ActorSocialProfile) -> [ReferenceKey] {
        profile.memberships.memberships.filter { $0.rank != -1 }.map(\.faction)
    }

    /// The reaction for the pair's relationship rank, or nil when nothing names it.
    /// A scripted rank beats the record, and it is the only layer that can name
    /// the player, who has no `NPC_` base for a `RELA` record.
    public func relationshipReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        let rank: RelationshipRank? = if let scripted = scriptedRank(of: observer, toward: target) {
            RelationshipRank(signedRank: Int(scripted))
        } else if let mine = observer.base, let theirs = target.base {
            relationships.rank(between: mine, and: theirs)
        } else {
            nil
        }
        // The game starts a Confidant at Ally, where the wiki groups it with Friend.
        if rank == .confidant {
            return .ally
        }
        return rank.flatMap(ActorReaction.init)
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

    private func resolveReaction(
        _ observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> (reaction: ActorReaction, source: HostilitySource) {
        if let crimeReaction = crime.crimeReaction(of: observer, toward: target) {
            return (crimeReaction, .crime)
        }
        // The rank is the start value, and the factions merge into it; an Ally rank
        // ends the merge before any faction is read.
        let related = relationshipReaction(of: observer, toward: target)
        if related == .ally {
            return (.ally, .relationship)
        }
        let declared = factionReaction(of: observer, toward: target)
        if
            let declared,
            ActorReaction.merged(related ?? .neutral, declared) != related ?? .neutral
        {
            return (declared, .faction)
        }
        if let related {
            return (related, .relationship)
        }
        return declared.map { ($0, .faction) } ?? (.neutral, .defaultNeutral)
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
