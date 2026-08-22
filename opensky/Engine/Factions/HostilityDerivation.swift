// Deriving one actor's hostility toward another from what the records say
// (issue #503, roadmap item 21.3).
//
// Through M16 hostility was a switch: an actor was angry because the player hit
// it, because a script said so, or because somebody ticked a box in the dev
// panel. This is what replaced the box as the *first* answer. A bandit is
// hostile to the player because a bandit is Very Aggressive and the player is a
// stranger; a Whiterun guard standing beside them is not, because a guard is
// only Aggressive and a stranger is not an enemy.
//
// ## The precedence order
//
// Asked what `observer` makes of `target`, the derivation takes the first of
// these that answers and stops:
//
// 1. **The explicit runtime override** — `ActorCombatState`, written by the dev
//    panel, by `StartCombat`, and by the player's own blow. Last resort in the
//    sense that matters: it is consulted first and beats everything, because it
//    is the record of something that already happened in this session. An actor
//    the player stabbed does not calm down because the records say the two are
//    friends.
// 2. **The crime term** — `CrimeHostilitySource`, the seam issues #504 and #505
//    join through. Empty here, and deliberately named rather than left implicit
//    so crime work does not have to reopen this precedence list. It sits above
//    the record terms because a bounty is a thing the player did, like a blow,
//    and below the override for the same reason a blow is.
// 3. **The RELA relationship between the two base records** — the Creation Kit
//    wiki states flatly that "relationships override factions"
//    (<https://ck.uesp.net/wiki/Relationship>), which is the one precedence rule
//    in this list that comes from a source rather than from us.
// 4. **The FACT interfaction relations** between the two actors' memberships.
// 5. **Neutral**, which the Creation Kit calls the default two factions relate
//    by "even if you don't specify it".
//
// Only step 3's position is documented upstream. Steps 1, 2 and 4-over-5 are
// this engine's ordering, stated here so a later reader can disagree with a
// decision rather than reverse-engineer one.
//
// ## Turning a reaction into a hostility
//
// The reaction alone does not say whether a weapon comes out; the actor's own
// Aggression does, "in conjunction with Faction Relationships"
// (<https://ck.uesp.net/wiki/AI_Data_Tab>). `ActorReaction.provokesAttack(at:)`
// carries that table, so this file only has to pick the reaction.
//
// Documented in docs/engine/combat.md.

import Foundation

/// Everything the derivation needs to know about one actor.
///
/// A flat value rather than a lookup closure so the whole derivation is
/// testable without a world-state store, and so a caller that already has the
/// memberships in hand does not pay for them twice.
nonisolated struct ActorSocialProfile: Equatable, Sendable {
    let key: ReferenceKey
    /// The actor's NPC_ base identity, which is what a RELA record names. Nil
    /// for the player, who has no base record in this engine, and for a
    /// generated actor no plugin describes.
    let base: ResolvedFormID?
    let memberships: ActorFactionState
    /// The AI attributes behind the aggression check. `ActorAIData.absent` for
    /// an actor whose record authors no AIDT, which never attacks unprovoked.
    let aiData: ActorAIData
    /// The session's explicit answer for this actor, when something already
    /// wrote one.
    let hostilityOverride: ActorHostility?

    init(
        key: ReferenceKey,
        base: ResolvedFormID? = nil,
        memberships: ActorFactionState = ActorFactionState(),
        aiData: ActorAIData = .absent,
        hostilityOverride: ActorHostility? = nil
    ) {
        self.key = key
        self.base = base
        self.memberships = memberships
        self.aiData = aiData
        self.hostilityOverride = hostilityOverride
    }
}

/// Which term of the precedence list produced the answer.
nonisolated enum HostilitySource: String, Equatable, Sendable, CaseIterable {
    case runtimeOverride
    case crime
    case relationship
    case faction
    case defaultNeutral

    var displayName: String {
        switch self {
        case .runtimeOverride: "runtime override"
        case .crime: "crime"
        case .relationship: "relationship"
        case .faction: "faction relation"
        case .defaultNeutral: "default"
        }
    }
}

/// One derivation's whole answer: what came out, what the records said, and
/// which term said it.
///
/// The reaction travels beside the hostility because they are different facts.
/// An unaggressive actor regards a bandit as an enemy and still does not attack
/// it, and a panel that showed only the hostility would make that look like the
/// records were being ignored.
nonisolated struct HostilityDecision: Equatable, Sendable {
    let hostility: ActorHostility
    let reaction: ActorReaction
    let source: HostilitySource

    var isHostile: Bool {
        hostility == .hostile
    }
}

/// Where crime joins the derivation (issues #504 and #505).
///
/// A protocol with one question rather than a closure so the bounty runtime can
/// carry its own state, and so this file names the seam in a way a reader can
/// find. `NoCrimeHostility` is what the engine runs with until #504 lands.
nonisolated protocol CrimeHostilitySource {
    /// What `observer`'s crime bookkeeping makes of `target`, or nil when crime
    /// has no opinion — which is the answer for every pair until a bounty, a
    /// witnessed theft or an assault gives it one.
    func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction?
}

/// The crime term before crime exists.
nonisolated struct NoCrimeHostility: CrimeHostilitySource {
    func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        nil
    }
}

/// Resolves what one actor makes of another from factions, relationships,
/// crime and explicit overrides.
nonisolated struct HostilityDerivation {
    let relations: FactionRelationIndex
    let relationships: RelationshipStore
    /// The crime seam. Assignable rather than injected at init so the session
    /// can hand the derivation a real bounty source once #504 exists, without
    /// rebuilding the relation index behind it.
    var crime: any CrimeHostilitySource = NoCrimeHostility()

    /// The whole answer for one ordered pair.
    func decide(
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
    func reaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction {
        resolveReaction(observer, toward: target).reaction
    }

    /// The most hostile reaction any pair of the two actors' memberships
    /// declares, in either direction, or nil when no membership pair names the
    /// other.
    ///
    /// Most hostile wins, and that is our rule rather than a documented one:
    /// neither UESP nor the Creation Kit wiki says what an actor in both an
    /// allied and an enemy faction makes of a target. Erring toward the enemy
    /// reading keeps a quest faction that marks somebody an enemy from being
    /// silently cancelled by an unrelated friendly membership, which is the
    /// failure that would be invisible in play.
    ///
    /// Both directions are consulted because an XNAM is authored on one side
    /// and vanilla does not always author the mirror; a relation naming the
    /// pair at all is an opinion about the pair.
    func factionReaction(
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

    /// The reaction the RELA record between the two bases declares, or nil when
    /// no record names the pair or its rank is one the spec does not name.
    func relationshipReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        guard
            let mine = observer.base,
            let theirs = target.base,
            let rank = relationships.rank(between: mine, and: theirs)
        else { return nil }
        return ActorReaction(rank)
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
}
