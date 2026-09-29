// The faction and relationship half of the Papyrus world seam (issue #508,
// roadmap item 21.4), declared beside the quest, actor, magic and crime halves
// and refined into `PapyrusWorldBridge` the same way.
//
// Seven operations, which is the whole surface this item can back with something
// real: read and write a membership, read and write a rank, read a relationship
// rank and write one, and answer what two actors make of each other.
//
// Nothing here writes around `WorldStateStore`. Every mutation is one
// `FactionRuntime` or `RelationshipRuntime` call, so the journal, the dirty
// counts and the save see a scripted membership exactly as they see one an actor
// was seeded with.
//
// Documented in docs/engine/papyrus-actor-natives.md and docs/engine/hostility.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// Faction and relationship operations a Papyrus native may perform.
///
/// Every read answers nil for a session with no faction runtime — a synthetic
/// scene with no FACT index — because answering "not a member" there would read
/// as a fact about the actor rather than about the session.
@MainActor
public protocol PapyrusWorldFactionBridge {
    /// Puts `actor` in `faction` at rank 0.
    ///
    /// "Adds the Actor to a specified faction at rank 0. If the Actor is already
    /// in the faction, this function does nothing."
    /// (<https://ck.uesp.net/wiki/AddToFaction_-_Actor>) The no-op half is why
    /// this cannot go through `setFactionRank(_:of:in:)`: a script adding
    /// somebody who is already a Companion must not demote them.
    ///
    /// - Returns: true when the stored memberships changed, or nil for a session
    ///   with no faction runtime.
    @discardableResult
    func addToFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool?

    /// Takes `actor` out of `faction`.
    ///
    /// "Removes this actor from the specified faction."
    /// (<https://ck.uesp.net/wiki/RemoveFromFaction_-_Actor>) The page adds that
    /// "if the faction was the actor's crime faction, the actor's crime faction
    /// will be cleared" — this engine derives the crime faction from the *place*
    /// (`CrimeFactionResolver`) rather than from a membership, so there is
    /// nothing to clear and the sentence has no effect here.
    ///
    /// - Returns: true when the actor was a member, or nil for a session with no
    ///   faction runtime.
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

    /// Sets `actor`'s rank in `faction`, adding it as a member when necessary.
    ///
    /// "Sets this actor's rank in the specified faction. Adds the actor to the
    /// faction if necessary." (<https://ck.uesp.net/wiki/SetFactionRank_-_Actor>)
    ///
    /// - Returns: true when stored memberships changed, or nil for a session with
    ///   no faction runtime.
    @discardableResult
    func setFactionRank(_ rank: Int8, of actor: ReferenceKey, in faction: ReferenceKey) -> Bool?

    /// The signed relationship rank between two actors, or nil when nothing names
    /// the pair.
    ///
    /// "Gets the relationship rank between this actor and another."
    /// (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>) Scripted ranks
    /// win over the `RELA` record; see `RelationshipRuntime`.
    func relationshipRank(of actor: ReferenceKey, toward other: ReferenceKey) -> Int8??

    /// Sets the relationship rank between two actors, in both directions.
    ///
    /// "Sets the relationship rank between this actor and another."
    /// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>)
    ///
    /// - Returns: true when stored state changed, or nil for a session with no
    ///   relationship runtime.
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

    /// What a member of one faction makes of a member of another, as the same
    /// Creation Kit numbering `factionReaction(of:toward:)` uses.
    ///
    /// "Gets this faction's reaction towards the other faction."
    /// (<https://ck.uesp.net/wiki/Faction_Script>) Nil covers both "no faction
    /// data in this session" and "neither `XNAM` names the other", which the
    /// native turns into a refusal rather than into Neutral: the `Faction`
    /// script's own numbering has no value for "unrelated", and answering
    /// Neutral would make an authored Neutral indistinguishable from silence.
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
