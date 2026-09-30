// The seams other features reach factions through. The runtimes in OpenSkyFactions
// conform, and the composition root hands them over as these protocols.

import OpenSkyFormatsESM
import OpenSkyGameData

/// What one seeding pass did.
nonisolated public struct FactionSeedReport: Equatable, Sendable {
    /// Factions the pass added, in the order the record authored them.
    public let added: [ReferenceKey]
    /// `SNAM` entries the load order carries no FACT record for, which is a
    /// dangling link rather than an error.
    public let unresolved: Int
    /// True when this actor had already been seeded, so the pass did nothing.
    public let wasAlreadySeeded: Bool

    public static let none = FactionSeedReport(added: [], unresolved: 0, wasAlreadySeeded: false)

    public init(added: [ReferenceKey], unresolved: Int, wasAlreadySeeded: Bool) {
        self.added = added
        self.unresolved = unresolved
        self.wasAlreadySeeded = wasAlreadySeeded
    }
}

/// Derives how one actor regards another from faction relations, relationship
/// ranks, and crime. `HostilityDerivation` conforms.
nonisolated public protocol HostilityDeriving: Sendable {
    var relationships: RelationshipStore { get }

    /// The whole answer for one ordered pair.
    func decide(
        _ observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> HostilityDecision

    /// The most hostile reaction any pair of the two actors' memberships declares,
    /// in either direction, or nil when none names the other. Most hostile wins: our
    /// rule, because no source says. Both directions count, because vanilla does not
    /// always author the mirror XNAM.
    func factionReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction?

    /// The scripted rank between the pair, from either actor's component. The
    /// second lookup covers a component written one-sided.
    func scriptedRank(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> Int8?
}

/// Faction membership and rank per actor, over the world-state store.
/// `FactionRuntime` conforms.
@MainActor
public protocol FactionAccess {
    /// Load-order FACT lookup behind every stored membership.
    var factions: FactionStore { get }

    func isMember(_ key: ReferenceKey, of faction: ReferenceKey) -> Bool

    /// The rank `key` holds, or nil when it is not a member.
    func rank(of key: ReferenceKey, in faction: ReferenceKey) -> Int8?

    /// Puts `key` in `faction` at `rank`, or moves an existing membership. A faction
    /// this load order does not carry is refused, since it could never be read back.
    /// - Returns: true when the stored state changed.
    @discardableResult
    func join(
        _ key: ReferenceKey,
        to faction: ReferenceKey,
        rank: Int8,
        in cell: CellSceneLocation?
    ) -> Bool

    /// Takes `key` out of `faction`.
    ///
    /// A key this load order no longer resolves is still removable, because a
    /// stored key is kept precisely so it survives a plugin coming and going.
    ///
    /// - Returns: true when the actor was a member.
    @discardableResult
    func leave(
        _ key: ReferenceKey,
        from faction: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool
}

/// Relationship ranks between actors, over the world-state store.
/// `RelationshipRuntime` conforms.
@MainActor
public protocol RelationshipAccess {
    /// The signed Creation Kit rank between two actors, "4: Lover ... -4:
    /// Archnemesis" (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>), or nil
    /// when neither layer names the pair. Nil is not 0 (Acquaintance). `bases` maps
    /// a reference to its `NPC_` identity, nil for the player.
    func rank(
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        bases: (ReferenceKey) -> ResolvedFormID?
    ) -> Int8?

    /// Sets the rank between two actors in both components, as `SetRelationshipRank`
    /// does (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>). An actor set
    /// against itself is refused.
    /// - Returns: true when stored state changed.
    @discardableResult
    func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        in cell: CellSceneLocation?,
        targetCell: CellSceneLocation?
    ) -> Bool
}
