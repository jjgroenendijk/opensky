// `PapyrusWorldStateBridge`'s faction and relationship half (issue #508, roadmap
// item 21.4), beside the actor, quest, magic and crime halves.
//
// Every operation goes through the session's `FactionRuntime` or
// `RelationshipRuntime`, which are the same doors an actor's seeded `SNAM` run
// and the hostility derivation come through: a scripted membership and an
// authored one therefore reach the store, the journal and the save by one path,
// and a script cannot produce a membership the engine could not have produced
// itself.
//
// Both runtimes are reached through closures for the reason `mutatePerks` is:
// the controller owns them and hands over accessors, so a session that never
// built one leaves every native here refusing rather than answering "not a
// member".
//
// Seeding, and why it happens here. `FactionRuntime` copies an actor's authored
// `SNAM` run into the component the first time anything asks. A script that
// calls `IsInFaction` on an actor the player has never met must see that run, so
// the accessor the controller supplies seeds before it answers — the same thing
// `derivedHostilityDecision(of:)` does for the combat loop.

import Foundation
import OpenSkyFormatsESM

extension PapyrusWorldStateBridge {
    @discardableResult
    public func addToFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        guard let runtime = factionRuntime?(actor) else { return nil }
        // "If the Actor is already in the faction, this function does nothing."
        guard !runtime.isMember(actor, of: faction) else { return false }
        return runtime.join(actor, to: faction, rank: 0, in: cellLocation(of: actor))
    }

    @discardableResult
    public func removeFromFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        guard let runtime = factionRuntime?(actor) else { return nil }
        return runtime.leave(actor, from: faction, in: cellLocation(of: actor))
    }

    public func isInFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        guard let runtime = factionRuntime?(actor) else { return nil }
        return runtime.isMember(actor, of: faction)
    }

    public func factionRank(of actor: ReferenceKey, in faction: ReferenceKey) -> Int8?? {
        guard let runtime = factionRuntime?(actor) else { return nil }
        return runtime.rank(of: actor, in: faction)
    }

    @discardableResult
    public func setFactionRank(
        _ rank: Int8,
        of actor: ReferenceKey,
        in faction: ReferenceKey
    ) -> Bool? {
        guard let runtime = factionRuntime?(actor) else { return nil }
        return runtime.join(actor, to: faction, rank: rank, in: cellLocation(of: actor))
    }

    public func relationshipRank(of actor: ReferenceKey, toward other: ReferenceKey) -> Int8?? {
        guard let runtime = relationshipRuntime?() else { return nil }
        return runtime.rank(of: actor, toward: other, bases: actorBaseIdentity)
    }

    @discardableResult
    public func setRelationshipRank(
        _ rank: Int8,
        of actor: ReferenceKey,
        toward other: ReferenceKey
    ) -> Bool? {
        guard let runtime = relationshipRuntime?() else { return nil }
        return runtime.setRank(
            rank,
            of: actor,
            toward: other,
            in: cellLocation(of: actor),
            targetCell: cellLocation(of: other)
        )
    }

    public func factionReaction(of actor: ReferenceKey, toward other: ReferenceKey) -> Int? {
        guard let reaction = socialDecision?(actor, other)?.factionReaction else { return nil }
        return ConditionFunctions.factionRelationValue(of: reaction)
    }

    public func isHostile(_ actor: ReferenceKey, toward other: ReferenceKey) -> Bool? {
        socialDecision?(actor, other)?.isHostile
    }

    public func factionRelation(of faction: ReferenceKey, toward other: ReferenceKey) -> Int? {
        guard
            let relations = factionRelationIndex?(),
            let reaction = relations.reaction(of: faction, toward: other)
        else { return nil }
        return ConditionFunctions.factionRelationValue(of: reaction)
    }

    /// The `NPC_` identity a `RELA` record would name for one reference, which is
    /// what the record layer of a relationship lookup is keyed by. Nil for the
    /// player and for any actor no plugin describes.
    private var actorBaseIdentity: (ReferenceKey) -> ResolvedFormID? {
        { [weak self] key in self?.actorSocialBase?(key) }
    }
}

/// One pair's social answer as the natives need it: whether the observer is
/// hostile, and what the two actors' *factions* alone make of each other.
///
/// A value rather than the whole `HostilityDecision` because the two natives ask
/// different questions and only one of them is about hostility:
/// `GetFactionReaction` is explicitly "the faction-based reaction"
/// (<https://ck.uesp.net/wiki/GetFactionReaction_-_Actor>), which is the faction
/// term of the precedence list and not the answer that came out of it.
nonisolated public struct PapyrusSocialDecision: Equatable, Sendable {
    public let isHostile: Bool
    public let factionReaction: ActorReaction

    public init(isHostile: Bool, factionReaction: ActorReaction) {
        self.isHostile = isHostile
        self.factionReaction = factionReaction
    }
}
