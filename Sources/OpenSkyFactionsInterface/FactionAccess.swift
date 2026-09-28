// The seams other features reach factions through. The runtimes in OpenSkyFactions
// conform, and the composition root hands them over as these protocols.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

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
nonisolated public protocol HostilityDeriving {
    var relations: FactionRelationIndex { get }

    var relationships: RelationshipStore { get }

    /// The crime seam. Assignable rather than injected at init so the session
    /// can hand the derivation a real bounty source once #504 exists, without
    /// rebuilding the relation index behind it.
    var crime: any CrimeHostilitySource { get }

    /// The whole answer for one ordered pair.
    func decide(
        _ observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> HostilityDecision

    /// The reaction alone, for a caller that wants what the records say without
    /// the aggression table over it — a condition function asking
    /// `GetFactionReaction`, or a panel explaining a decision.
    func reaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction

    /// The most hostile reaction any pair of the two actors' memberships
    /// declares, in either direction, or nil when no membership pair names the
    /// other.
    ///
    /// Most hostile wins, and that is our rule rather than a documented one:
    /// neither UESP nor the Creation Kit wiki says what an actor in both an
    /// allied and an enemy faction makes of a target. Erring toward the enemy
    /// reading keeps a quest faction that marks somebody an enemy from being
    /// silently cancelled by an unrelated friendly membership, which is the
    /// failure that would be invisible in play.
    ///
    /// Both directions are consulted because an XNAM is authored on one side
    /// and vanilla does not always author the mirror; a relation naming the
    /// pair at all is an opinion about the pair.
    func factionReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction?

    /// The reaction between the two actors' relationship rank, or nil when
    /// neither layer names the pair and when the rank named is one the spec does
    /// not name.
    ///
    /// A scripted rank wins over the record, in either actor's component, for
    /// the reason `RelationshipRuntime` states: setting a rank is a deliberate
    /// change to what the record started the pair at. It is also what lets a
    /// relationship with the player count at all, since the player has no `NPC_`
    /// base for a `RELA` record to name.
    func relationshipReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction?

    /// The scripted rank between the pair, from either actor's component. Both
    /// sides are written by `RelationshipRuntime`, so the second lookup covers a
    /// component an older build wrote one-sided rather than a disagreement this
    /// one can produce.
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

    /// Record-side resolution of an actor's authored `SNAM` run and `AIDT`.
    /// Nil on a synthetic scene, where nothing can be seeded and every actor's
    /// memberships are whatever a caller wrote by hand.
    var baselines: ActorFactionBaselineResolver? { get }

    /// The plugin an actor's `SNAM` links and NPC_ bases are relative to, which
    /// is the base plugin the record indexes were built from.
    var pluginName: String? { get }

    var store: WorldStateStore { get }

    /// `key`'s memberships, empty when nothing has ever written one.
    func state(of key: ReferenceKey) -> ActorFactionState

    func isMember(_ key: ReferenceKey, of faction: ReferenceKey) -> Bool

    /// The rank `key` holds, or nil when it is not a member.
    func rank(of key: ReferenceKey, in faction: ReferenceKey) -> Int8?

    /// Every faction `key` belongs to that this load order can still resolve,
    /// in key order. A membership the load order dropped stays in the component
    /// and is simply absent from this listing.
    func resolvedFactions(of key: ReferenceKey) -> [ResolvedFaction]

    /// Puts `key` in `faction` at `rank`, or moves an existing membership to
    /// that rank.
    ///
    /// A faction this load order does not carry is refused: a key nothing
    /// resolves could never be read back, and storing it would put a permanent
    /// unreadable entry in the save. That is the opposite of the rule for a
    /// *stored* membership, which is kept when it stops resolving — the
    /// difference is direction, exactly as it is for an owned perk.
    ///
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

    /// The same seed for a caller that already resolved the run it wants
    /// applied — the save decoder's counterpart, and what the unit suites use.
    @discardableResult
    func seed(
        _ memberships: [ActorBase.FactionMembership],
        fromPlugin plugin: String,
        to holder: ActorValueHolder
    ) -> FactionSeedReport

    /// Everything the derivation needs to know about one actor, assembled from
    /// the component, the records and the session's override.
    func profile(of holder: ActorValueHolder) -> ActorSocialProfile

    /// The crime faction `subject` reports crimes to — its authored `CRIF`
    /// resolved against the load order (issue #505). Nil for the player, a
    /// generated actor, and a link no plugin defines.
    func crimeFaction(of subject: ActorValueSubject) -> ReferenceKey?

    /// Whether `key` still has to be seeded before its memberships mean
    /// anything.
    ///
    /// Exposed so a per-frame caller can skip the mutating seed entirely — a
    /// `Set` membership test rather than a copy of this whole struct — and only
    /// pay for it the first time it sees an actor.
    func needsSeeding(_ key: ReferenceKey) -> Bool

    /// What `observer` makes of `target` from what is stored right now.
    ///
    /// Seeds nothing, so an actor nobody has seeded yet answers from an empty
    /// membership list. Callers that want the authored run to count seed first,
    /// which `decide(_:toward:)` does for them.
    func decision(
        _ observer: ActorValueHolder,
        toward target: ActorValueHolder
    ) -> HostilityDecision
}

extension FactionAccess {
    @discardableResult
    public func join(_ key: ReferenceKey, to faction: ReferenceKey) -> Bool {
        join(key, to: faction, rank: 0, in: nil)
    }

    @discardableResult
    public func join(_ key: ReferenceKey, to faction: ReferenceKey, rank: Int8) -> Bool {
        join(key, to: faction, rank: rank, in: nil)
    }

    @discardableResult
    public func join(
        _ key: ReferenceKey,
        to faction: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool {
        join(key, to: faction, rank: 0, in: cell)
    }

    @discardableResult
    public func leave(_ key: ReferenceKey, from faction: ReferenceKey) -> Bool {
        leave(key, from: faction, in: nil)
    }
}

/// Relationship ranks between actors, over the world-state store.
/// `RelationshipRuntime` conforms.
@MainActor
public protocol RelationshipAccess {
    /// Load-order RELA and ASTP lookup behind the authored layer.
    var relationships: RelationshipStore { get }

    var store: WorldStateStore { get }

    /// `key`'s scripted overrides, empty when nothing has ever written one.
    func state(of key: ReferenceKey) -> ActorRelationshipState

    /// The signed Creation Kit rank between two actors — "4: Lover ... -4:
    /// Archnemesis" (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>) —
    /// or nil when neither layer names the pair.
    ///
    /// Nil is not 0: 0 is Acquaintance, a rank a record and a script both author
    /// deliberately, and a caller has to be able to tell it from "nothing says".
    ///
    /// `bases` maps a reference to the `NPC_` identity a `RELA` record would
    /// name, and answers nil for an actor that has none — the player, and any
    /// actor no plugin describes.
    func rank(
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        bases: (ReferenceKey) -> ResolvedFormID?
    ) -> Int8?

    /// The scripted rank alone, in either direction. Both directions are stored,
    /// so the second read is a fallback for a component written by an older
    /// build rather than a disagreement this one can produce.
    func storedRank(of observer: ReferenceKey, toward target: ReferenceKey) -> Int8?

    /// Sets the rank between two actors, in both components.
    ///
    /// "Sets the relationship rank between this actor and another."
    /// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>) A relationship is
    /// one fact about a pair rather than two opinions — `RELA` stores a single
    /// record for it — so both sides are written and either actor can answer
    /// alone.
    ///
    /// An actor set against itself is refused: no `RELA` record names a base
    /// twice, and storing one would make `rank(of:toward:)` answer a question
    /// the records cannot pose.
    ///
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

extension RelationshipAccess {
    @discardableResult
    public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> Bool {
        setRank(rank, of: observer, toward: target, in: nil, targetCell: nil)
    }

    @discardableResult
    public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool {
        setRank(rank, of: observer, toward: target, in: cell, targetCell: nil)
    }
}
