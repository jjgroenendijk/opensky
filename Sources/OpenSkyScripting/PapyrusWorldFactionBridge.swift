// The faction and relationship half of the Papyrus world seam: memberships,
// ranks, relationship ranks, and what two actors make of each other. Every
// write is one `FactionRuntime` or `RelationshipRuntime` call.
// See docs/engine/papyrus-actor-natives.md and docs/engine/hostility.md.

import Foundation
import OpenSkyFormatsESM

/// Faction and relationship operations a Papyrus native may perform.
///
/// Every read answers nil for a session with no faction runtime — a synthetic
/// scene with no FACT index — because answering "not a member" there would read
/// as a fact about the actor rather than about the session.
@MainActor
public protocol PapyrusWorldFactionBridge {
    /// Puts `actor` in `faction` at rank 0, and does nothing if already a member
    /// (<https://ck.uesp.net/wiki/AddToFaction_-_Actor>). So it cannot reuse
    /// `setFactionRank(_:of:in:)`, which would demote.
    /// - Returns: true when memberships changed, or nil without a faction runtime.
    @discardableResult
    func addToFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool?

    /// Takes `actor` out of `faction`
    /// (<https://ck.uesp.net/wiki/RemoveFromFaction_-_Actor>). The crime faction
    /// comes from the location here, so there is none to clear.
    /// - Returns: true when the actor was a member, or nil without a faction runtime.
    @discardableResult
    func removeFromFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool?

    /// Whether `actor` is in `faction`.
    ///
    /// "Returns whether this actor is a member of the specified faction or not."
    /// (<https://ck.uesp.net/wiki/IsInFaction_-_Actor>)
    func isInFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool?

    /// `actor`'s rank in `faction`, or nil when it is not a member.
    ///
    /// "Gets this actor's rank in the specified faction."
    /// (<https://ck.uesp.net/wiki/GetFactionRank_-_Actor>) The -2 the page
    /// documents for a non-member is applied by the native rather than here, so
    /// this seam can keep "not a member" and "member at rank -2" apart.
    func factionRank(of actor: ReferenceKey, in faction: ReferenceKey) -> Int8??

    /// Sets `actor`'s rank in `faction`, adding it when needed
    /// (<https://ck.uesp.net/wiki/SetFactionRank_-_Actor>).
    /// - Returns: true when memberships changed, or nil without a faction runtime.
    @discardableResult
    func setFactionRank(_ rank: Int8, of actor: ReferenceKey, in faction: ReferenceKey) -> Bool?

    /// The signed relationship rank between two actors, or nil when nothing names
    /// the pair.
    ///
    /// "Gets the relationship rank between this actor and another."
    /// (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>) Scripted ranks
    /// win over the `RELA` record; see `RelationshipRuntime`.
    func relationshipRank(of actor: ReferenceKey, toward other: ReferenceKey) -> Int8??

    /// Sets the relationship rank between two actors, in both directions
    /// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>).
    /// - Returns: true when state changed, or nil without a relationship runtime.
    @discardableResult
    func setRelationshipRank(
        _ rank: Int8,
        of actor: ReferenceKey,
        toward other: ReferenceKey
    ) -> Bool?

    /// The faction-based reaction between two actors, as the Creation Kit numbers
    /// it: "0: Neutral, 1: Enemy, 2: Ally, 3: Friend"
    /// (<https://ck.uesp.net/wiki/GetFactionReaction_-_Actor>).
    func factionReaction(of actor: ReferenceKey, toward other: ReferenceKey) -> Int?

    /// Whether `actor` is hostile to `other` right now, through the whole
    /// hostility precedence list rather than a second derivation.
    func isHostile(_ actor: ReferenceKey, toward other: ReferenceKey) -> Bool?

    /// What a member of one faction makes of a member of another, in the numbering
    /// `factionReaction(of:toward:)` uses (<https://ck.uesp.net/wiki/Faction_Script>).
    /// Nil means no faction data or no `XNAM` either way; the native refuses rather
    /// than answering Neutral.
    func factionRelation(of faction: ReferenceKey, toward other: ReferenceKey) -> Int?
}

/// Nonisolated hops for the faction operations, mirroring the rest of
/// `PapyrusWorldAccess`: one `MainActor.assumeIsolated` per method, which is an
/// assertion that natives run on the main actor rather than a suppression of the
/// check.
nonisolated extension PapyrusWorldAccess {
    @discardableResult
    public func addToFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.addToFaction(actor, faction: faction) }
    }

    @discardableResult
    public func removeFromFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.removeFromFaction(actor, faction: faction) }
    }

    public func isInFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.isInFaction(actor, faction: faction) }
    }

    public func factionRank(of actor: ReferenceKey, in faction: ReferenceKey) -> Int8?? {
        MainActor.assumeIsolated { bridge.factionRank(of: actor, in: faction) }
    }

    @discardableResult
    public func setFactionRank(
        _ rank: Int8,
        of actor: ReferenceKey,
        in faction: ReferenceKey
    ) -> Bool? {
        MainActor.assumeIsolated { bridge.setFactionRank(rank, of: actor, in: faction) }
    }

    public func relationshipRank(of actor: ReferenceKey, toward other: ReferenceKey) -> Int8?? {
        MainActor.assumeIsolated { bridge.relationshipRank(of: actor, toward: other) }
    }

    @discardableResult
    public func setRelationshipRank(
        _ rank: Int8,
        of actor: ReferenceKey,
        toward other: ReferenceKey
    ) -> Bool? {
        MainActor.assumeIsolated {
            bridge.setRelationshipRank(rank, of: actor, toward: other)
        }
    }

    public func factionReaction(of actor: ReferenceKey, toward other: ReferenceKey) -> Int? {
        MainActor.assumeIsolated { bridge.factionReaction(of: actor, toward: other) }
    }

    public func isHostile(_ actor: ReferenceKey, toward other: ReferenceKey) -> Bool? {
        MainActor.assumeIsolated { bridge.isHostile(actor, toward: other) }
    }

    public func factionRelation(of faction: ReferenceKey, toward other: ReferenceKey) -> Int? {
        MainActor.assumeIsolated { bridge.factionRelation(of: faction, toward: other) }
    }
}
