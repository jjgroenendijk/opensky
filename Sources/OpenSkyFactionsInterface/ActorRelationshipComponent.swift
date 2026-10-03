// One actor's runtime relationship ranks, as a world-state component, set by
// `Actor.SetRelationshipRank`. Keyed by `ReferenceKey`, not `NPC_` base, because
// the player has no base; so two placements of one base do not share a rank.
// `RelationshipRuntime` writes both actors' components. Dropped once empty.
// See docs/engine/hostility.md and docs/formats/relationships.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One override: the other actor, and the rank the pair holds. The rank is the
/// signed Creation Kit number, "4: Lover ... -4: Archnemesis"
/// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>), stored raw without
/// clamping. `RelationshipRank.signedRank` converts the record word.
nonisolated public struct ActorRelationshipOverride: Equatable, Sendable, Comparable {
    public let other: ReferenceKey
    public let rank: Int8

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.other == rhs.other ? lhs.rank < rhs.rank : lhs.other < rhs.other
    }

    public init(other: ReferenceKey, rank: Int8) {
        self.other = other
        self.rank = rank
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
        var ranks: [ReferenceKey: Int8] = [:]
        for override in overrides {
            ranks[override.other] = override.rank
        }
        self.overrides = ranks.keys.sorted().compactMap { other in
            guard let rank = ranks[other] else { return nil }
            return ActorRelationshipOverride(other: other, rank: rank)
        }
    }

    /// The rank toward `other`, or nil when no script has set one — which is not
    /// the same as 0, the Acquaintance rank a script may set deliberately.
    public func rank(toward other: ReferenceKey) -> Int8? {
        overrides.first { $0.other == other }?.rank
    }

    /// The state after setting the rank toward `other`, replacing any earlier
    /// one.
    public func setting(_ rank: Int8, toward other: ReferenceKey) -> ActorRelationshipState {
        ActorRelationshipState(
            overrides: overrides + [ActorRelationshipOverride(other: other, rank: rank)]
        )
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
