// One actor's runtime faction memberships, as a world-state component. Seeded
// from the NPC_ `SNAM` run the first time anything asks, then moved by quests
// and scripts. Dropped once empty, so seeding an actor with no memberships
// writes nothing. See docs/engine/hostility.md and docs/formats/factions.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One membership: the faction and the rank the actor holds in it.
///
/// The rank is signed because `ActorBase.FactionMembership.rank` is — xEdit
/// reads `itS8` and vanilla authors negative ranks to mean "a member the rank
/// titles do not name".
nonisolated public struct ActorFactionMembership: Equatable, Sendable, Comparable {
    public let faction: ReferenceKey
    public let rank: Int8

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.faction == rhs.faction ? lhs.rank < rhs.rank : lhs.faction < rhs.faction
    }

    public init(faction: ReferenceKey, rank: Int8) {
        self.faction = faction
        self.rank = rank
    }
}

/// Every faction one actor belongs to, in ascending faction-key order, so a save
/// writes the same bytes for the same state. One entry per faction: joining again
/// changes the rank.
nonisolated public struct ActorFactionState: WorldStateComponent, Sendable {
    public private(set) var memberships: [ActorFactionMembership]

    public static var componentKind: WorldStateComponentKind {
        .factions
    }

    public var isEmpty: Bool {
        memberships.isEmpty
    }

    public var count: Int {
        memberships.count
    }

    /// Just the factions, in the same order, for a caller that does not care
    /// about ranks.
    public var factions: [ReferenceKey] {
        memberships.map(\.faction)
    }

    /// Normalizes on the way in, so a save from another load order restores a valid
    /// component. A faction the load order no longer resolves is kept, so removing a
    /// plugin does not destroy progress.
    public init(memberships: [ActorFactionMembership] = []) {
        var ranks: [ReferenceKey: Int8] = [:]
        for membership in memberships {
            ranks[membership.faction] = membership.rank
        }
        self.memberships = ranks.keys.sorted().compactMap { faction in
            guard let rank = ranks[faction] else { return nil }
            return ActorFactionMembership(faction: faction, rank: rank)
        }
    }

    public func isMember(of faction: ReferenceKey) -> Bool {
        memberships.contains { $0.faction == faction }
    }

    /// The rank the actor holds, or nil when it is not a member — which is not
    /// the same as rank 0, a rank vanilla authors freely.
    public func rank(in faction: ReferenceKey) -> Int8? {
        memberships.first { $0.faction == faction }?.rank
    }

    /// The state after joining `faction` at `rank`, or changing the rank when
    /// the actor is already a member.
    public func joining(_ faction: ReferenceKey, rank: Int8) -> ActorFactionState {
        ActorFactionState(
            memberships: memberships + [ActorFactionMembership(faction: faction, rank: rank)]
        )
    }

    /// The state after leaving `faction`, unchanged when the actor was never in
    /// it.
    public func leaving(_ faction: ReferenceKey) -> ActorFactionState {
        guard isMember(of: faction) else { return self }
        return ActorFactionState(memberships: memberships.filter { $0.faction != faction })
    }
}

nonisolated extension WorldStateComponentKind {
    /// Every faction one actor currently belongs to, and the rank it holds in each.
    /// A slot of its own for the reason `perks` is one: a membership moves on a
    /// quest stage or a script call, while the actor values beside it are rewritten
    /// sixty times a second. It is also the input to the hostility derivation,
    /// which is why it must be a component and not a re-read of the NPC_ record: an
    /// actor the player has joined to a faction has to stay joined across a reload.
    public static let factions = Self(rawValue: "factions", order: 16, affectsCellBuild: false)
}
