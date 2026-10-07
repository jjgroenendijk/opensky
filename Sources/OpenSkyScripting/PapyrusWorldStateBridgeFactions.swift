// The faction and relationship half of `PapyrusWorldStateBridge`, through
// `FactionRuntime` and `RelationshipRuntime`, reached by closures; without them
// every native refuses. The accessor seeds an actor's authored `SNAM` run before
// answering, as `derivedHostilityDecision(of:)` does.

import Foundation
import OpenSkyConditions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

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
        let old = runtime.rank(of: actor, toward: other, bases: actorBaseIdentity)
        let changed = runtime.setRank(
            rank,
            of: actor,
            toward: other,
            in: cellLocation(of: actor),
            targetCell: cellLocation(of: other)
        )
        // A pair no layer named counts as acquaintances (rank 0).
        if changed, old != rank {
            _ = story?.sendStoryEvent(.relationshipRank(actor, other, old: old ?? 0, new: rank))
        }
        return changed
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

/// One pair's social answer for the natives: whether the observer is hostile, and
/// what the two factions alone make of each other. `GetFactionReaction` is the
/// faction term only (<https://ck.uesp.net/wiki/GetFactionReaction_-_Actor>).
nonisolated public struct PapyrusSocialDecision: Equatable, Sendable {
    public let isHostile: Bool
    public let factionReaction: ActorReaction

    public init(isHostile: Bool, factionReaction: ActorReaction) {
        self.isHostile = isHostile
        self.factionReaction = factionReaction
    }
}
