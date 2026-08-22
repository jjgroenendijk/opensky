// One actor's runtime faction memberships, as a world-state component
// (issue #503, roadmap item 21.3).
//
// The NPC_ `SNAM` run says which factions an actor was *authored* into. This
// component is what the actor belongs to *now*: seeded from that run the first
// time anything asks, then moved by a quest joining the player to the
// Companions, a script promoting somebody a rank, or a faction removal.
//
// A slot of its own beside `perks` and `spellbook` for the lifetime reason
// those two are separate from `actorValues`: a membership changes on a quest
// stage or a script call, never per frame, while the values beside it are
// rewritten sixty times a second.
//
// The component is dropped entirely once it empties, exactly as `PerkState` is,
// so an actor in no faction stops being dirty for this slot. That is also why
// seeding an actor whose record authors no membership writes nothing.
//
// Documented in docs/engine/combat.md and docs/formats/factions.md.

import Foundation

/// One membership: the faction and the rank the actor holds in it.
///
/// The rank is signed because `ActorBase.FactionMembership.rank` is — xEdit
/// reads `itS8` and vanilla authors negative ranks to mean "a member the rank
/// titles do not name".
nonisolated struct ActorFactionMembership: Equatable, Sendable, Comparable {
    let faction: ReferenceKey
    let rank: Int8

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.faction == rhs.faction ? lhs.rank < rhs.rank : lhs.faction < rhs.faction
    }
}

/// Every faction one actor currently belongs to, in ascending faction-key
/// order.
///
/// Ordered rather than a dictionary so the save writes the same bytes twice for
/// the same state, which is the rule `PerkState.owned` already follows. One
/// entry per faction: joining a faction an actor is already in changes the rank
/// rather than adding a second row, because "what rank is this actor" must have
/// exactly one answer.
nonisolated struct ActorFactionState: WorldStateComponent {
    private(set) var memberships: [ActorFactionMembership]

    static var componentKind: WorldStateComponentKind {
        .factions
    }

    var erased: WorldStateComponentValue {
        .factions(self)
    }

    var isEmpty: Bool {
        memberships.isEmpty
    }

    var count: Int {
        memberships.count
    }

    /// Just the factions, in the same order, for a caller that does not care
    /// about ranks.
    var factions: [ReferenceKey] {
        memberships.map(\.faction)
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: a repeated faction collapses to its last rank and the order
    /// becomes key order, so a file written under a different load order still
    /// restores a valid component.
    ///
    /// A faction this load order no longer resolves is *kept*, the rule a known
    /// spell and an owned perk follow: losing it would make removing a plugin
    /// destroy progress, and it is invisible to every query that goes through
    /// `FactionStore` anyway.
    init(memberships: [ActorFactionMembership] = []) {
        var ranks: [ReferenceKey: Int8] = [:]
        for membership in memberships {
            ranks[membership.faction] = membership.rank
        }
        self.memberships = ranks.keys.sorted().compactMap { faction in
            guard let rank = ranks[faction] else { return nil }
            return ActorFactionMembership(faction: faction, rank: rank)
        }
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .factions(value) = erased else { return nil }
        self = value
    }

    func isMember(of faction: ReferenceKey) -> Bool {
        memberships.contains { $0.faction == faction }
    }

    /// The rank the actor holds, or nil when it is not a member — which is not
    /// the same as rank 0, a rank vanilla authors freely.
    func rank(in faction: ReferenceKey) -> Int8? {
        memberships.first { $0.faction == faction }?.rank
    }

    /// The state after joining `faction` at `rank`, or changing the rank when
    /// the actor is already a member.
    func joining(_ faction: ReferenceKey, rank: Int8) -> ActorFactionState {
        ActorFactionState(
            memberships: memberships + [ActorFactionMembership(faction: faction, rank: rank)]
        )
    }

    /// The state after leaving `faction`, unchanged when the actor was never in
    /// it.
    func leaving(_ faction: ReferenceKey) -> ActorFactionState {
        guard isMember(of: faction) else { return self }
        return ActorFactionState(memberships: memberships.filter { $0.faction != faction })
    }
}
