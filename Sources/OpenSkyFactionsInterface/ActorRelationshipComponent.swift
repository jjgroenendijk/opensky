// One actor's runtime relationship ranks, as a world-state component, set by
// `Actor.SetRelationshipRank`. Keyed by `ReferenceKey`, not `NPC_` base, because
// the player has no base; so two placements of one base do not share a rank.
// `RelationshipRuntime` writes both actors' components. Dropped once empty.
// See docs/engine/hostility.md and docs/formats/relationships.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// One override: the other actor, and the rank the pair holds. The rank is the
/// signed Creation Kit number, "4: Lover ... -4: Archnemesis"
/// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>), stored raw without
/// clamping. `RelationshipRank.signedRank` converts the record word.
nonisolated public struct ActorRelationshipOverride: Equatable, Sendable, Comparable {
    public let other: ReferenceKey
    public let rank: Int8
    /// The rank the pair held when it first reached Friend (1) or higher, nil before
    /// that. UESP "Skyrim:Disposition": the item allowance "is only evaluated once".
    public let firstFriendRank: Int8?

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.other == rhs.other ? lhs.rank < rhs.rank : lhs.other < rhs.other
    }

    public init(other: ReferenceKey, rank: Int8, firstFriendRank: Int8? = nil) {
        self.other = other
        self.rank = rank
        self.firstFriendRank = firstFriendRank
    }
}

/// Every relationship rank one actor has been given by a script, in ascending key
/// order, so a save writes the same bytes for the same state. One entry per other
/// actor.
nonisolated public struct ActorRelationshipState: WorldStateComponent, Sendable {
    public private(set) var overrides: [ActorRelationshipOverride]

    public static var componentKind: WorldStateComponentKind {
        .relationships
    }

    public var isEmpty: Bool {
        overrides.isEmpty
    }

    public var count: Int {
        overrides.count
    }

    /// Normalizes on the way in, so a save from another load order restores a valid
    /// component. An actor this session no longer resolves is kept, so a plugin
    /// coming and going does not destroy a scripted relationship.
    public init(overrides: [ActorRelationshipOverride] = []) {
        var latest: [ReferenceKey: ActorRelationshipOverride] = [:]
        for override in overrides {
            latest[override.other] = override
        }
        self.overrides = latest.keys.sorted().compactMap { latest[$0] }
    }

    /// The rank toward `other`, or nil when no script has set one — which is not
    /// the same as 0, the Acquaintance rank a script may set deliberately.
    public func rank(toward other: ReferenceKey) -> Int8? {
        overrides.first { $0.other == other }?.rank
    }

    /// The rank the pair held when it first reached Friend, nil before that.
    public func firstFriendRank(toward other: ReferenceKey) -> Int8? {
        overrides.first { $0.other == other }?.firstFriendRank
    }

    /// The state after setting the rank toward `other`, replacing any earlier
    /// one. The first rank of Friend or higher is kept for good.
    public func setting(_ rank: Int8, toward other: ReferenceKey) -> ActorRelationshipState {
        let first = firstFriendRank(toward: other) ?? (rank >= 1 ? rank : nil)
        let override = ActorRelationshipOverride(other: other, rank: rank, firstFriendRank: first)
        return ActorRelationshipState(overrides: overrides + [override])
    }
}

nonisolated extension WorldStateComponentKind {
    /// Relationship ranks a script has set between one actor and others. A slot of
    /// its own beside `factions` because the two are different facts with the same
    /// lifetime: what an actor *belongs to*, and what it *is to somebody else*. The
    /// Creation Kit says outright that "relationships override factions"
    /// (<https://ck.uesp.net/wiki/Relationship>), so they cannot share a slot and
    /// still be resolved in that order.
    public static let relationships = Self(
        rawValue: "relationships", order: 17, affectsCellBuild: false
    )
}
