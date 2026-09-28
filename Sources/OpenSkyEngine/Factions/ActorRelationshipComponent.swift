// One actor's runtime relationship ranks, as a world-state component
// (issue #508, roadmap item 21.4).
//
// A `RELA` record says what two `NPC_` bases were *authored* as. This component
// is what two actors are to each other *now*, after a quest or a script called
// `Actor.SetRelationshipRank`. It is a slot of its own beside `factions` for the
// same lifetime reason that one is separate from `actorValues`: a rank moves on
// a quest stage or a script call, never per frame.
//
// ## Why it is keyed by reference and the records are keyed by base
//
// `RelationshipStore` indexes `RELA` by the pair of `NPC_` bases the record
// names, because that is what the record carries. The Papyrus function takes two
// *actors* — "akOther: The other actor to determine our relationship with"
// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>) — and the player is
// one of the two in nearly every vanilla call while having no `NPC_` base in this
// engine. Keying the override by `ReferenceKey` is therefore the only shape that
// can express the common case at all, and it is what makes a scripted rank with
// the player readable by `GetRelationshipRank`.
//
// The consequence is stated rather than hidden: an override is about the two
// references, so two placements of the same base do not share one. Vanilla
// scripts name unique actors, so this is a difference nothing observed exercises,
// and the alternative could not name the player.
//
// ## Both directions are written
//
// A relationship is one fact about a pair, not two opinions: `RELA` stores a
// single record per pair and `RelationshipStore` looks it up in either argument
// order. `RelationshipRuntime` therefore writes the rank into both actors'
// components, so a reader that only has one of them still finds it.
//
// The component is dropped entirely once it empties, exactly as
// `ActorFactionState` is, so an actor with no overrides stops being dirty for
// this slot.
//
// Documented in docs/engine/hostility.md and docs/formats/relationships.md.

import Foundation
import OpenSkyFormatsESM

/// One override: the other actor, and the rank the pair holds.
///
/// The rank is the signed Creation Kit number — "4: Lover ... -4: Archnemesis"
/// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>) — rather than the
/// record's unsigned `RELA` word, because that is what both the native and the
/// condition function speak. `RelationshipRank.signedRank` is the conversion in
/// the other direction.
///
/// Signed and stored raw: the wiki calls -4...4 "acceptable" without saying what
/// happens outside it, so a value a script invents is kept rather than clamped
/// into a rank it did not mean.
nonisolated public struct ActorRelationshipOverride: Equatable, Sendable, Comparable {
    public let other: ReferenceKey
    public let rank: Int8

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.other == rhs.other ? lhs.rank < rhs.rank : lhs.other < rhs.other
    }
}

/// Every relationship rank one actor has been given by a script, in ascending
/// key order.
///
/// Ordered rather than a dictionary so the save writes the same bytes twice for
/// the same state, which is the rule `ActorFactionState.memberships` already
/// follows. One entry per other actor: setting a rank twice replaces it, because
/// "what are these two to each other" must have exactly one answer.
nonisolated public struct ActorRelationshipState: WorldStateComponent, Sendable {
    public private(set) var overrides: [ActorRelationshipOverride]

    public static var componentKind: WorldStateComponentKind {
        .relationships
    }

    public var erased: WorldStateComponentValue {
        .relationships(self)
    }

    public var isEmpty: Bool {
        overrides.isEmpty
    }

    public var count: Int {
        overrides.count
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: a repeated actor collapses to its last rank and the order
    /// becomes key order, so a file written under a different load order still
    /// restores a valid component.
    ///
    /// An actor this session no longer resolves is *kept*, the rule a stored
    /// faction membership follows: the entry is invisible to every query that
    /// goes through a live key anyway, and dropping it would make a plugin
    /// coming and going destroy a scripted relationship.
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

    public init?(erased: WorldStateComponentValue) {
        guard case let .relationships(value) = erased else { return nil }
        self = value
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
