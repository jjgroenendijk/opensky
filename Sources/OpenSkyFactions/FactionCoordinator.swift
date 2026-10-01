// The shell of the faction domain: owns the membership and relationship
// runtimes, seeds an actor from its `SNAM` run, and answers hostility toward
// the player. The rules live in `FactionRuntime` and `HostilityDerivation`.
// See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Owns the faction runtimes and reads the world through `FactionWorld`.
/// Without game data every runtime stays nil, and hostility answers from the
/// stored override alone.
@MainActor
public final class FactionCoordinator {
    /// Nil until `wire`.
    public private(set) var runtime: FactionRuntime?
    /// Nil until `wire`, and then `SetRelationshipRank` refuses.
    public private(set) var relationships: RelationshipRuntime?
    /// Kept apart from the derivation's copy, so `Faction.GetReaction` needs
    /// no actor.
    public private(set) var relations: FactionRelationIndex?

    let store: WorldStateStore
    weak var world: (any FactionWorld)?

    public init(store: WorldStateStore) {
        self.store = store
    }

    public func attach(world: any FactionWorld) {
        self.world = world
    }

    public func wire(
        factions: FactionStore,
        relationships relationshipStore: RelationshipStore,
        baselines: ActorFactionBaselineResolver?,
        pluginName: String?
    ) {
        let relations = FactionRelationIndex(store: factions)
        self.relations = relations
        relationships = RelationshipRuntime(store: store, relationships: relationshipStore)
        runtime = FactionRuntime(
            store: store,
            factions: factions,
            derivation: HostilityDerivation(relations: relations, relationships: relationshipStore),
            baselines: baselines,
            pluginName: pluginName
        )
    }

    // MARK: - Seeding

    /// Copies the authored `SNAM` run into the store the first time this
    /// session sees `holder`. Seeding walks the template chain, so it runs
    /// once per actor.
    public func seed(_ holder: ActorValueHolder) {
        guard runtime?.needsSeeding(holder.key) == true else { return }
        runtime?.seed(holder)
    }

    /// The runtime, with `key` seeded first so a read sees its authored run.
    public func seededRuntime(for key: ReferenceKey) -> FactionRuntime? {
        if let holder = world?.actorValueHolder(for: key) {
            seed(holder)
        }
        return runtime
    }

    /// Nil without faction data.
    public func memberships(of key: ReferenceKey) -> ActorFactionState? {
        seededRuntime(for: key)?.state(of: key)
    }

    /// Nil without faction data or for an actor that is not resident.
    public func profile(of key: ReferenceKey) -> ActorSocialProfile? {
        guard let holder = world?.actorValueHolder(for: key) else { return nil }
        seed(holder)
        return runtime?.profile(of: holder)
    }

    // MARK: - Reading

    /// What `observer` makes of `target`, for `Actor.GetFactionReaction` and
    /// `IsHostileToActor`. Both are seeded first.
    public func socialDecision(
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> (isHostile: Bool, factionReaction: ActorReaction)? {
        guard
            let mine = profile(of: observer),
            let theirs = profile(of: target),
            let derivation = runtime?.derivation
        else { return nil }
        return (
            derivation.decide(mine, toward: theirs).isHostile,
            derivation.factionReaction(of: mine, toward: theirs) ?? .neutral
        )
    }

    /// The player and every resident actor, seeded. An unstreamed actor has
    /// no profile, so the condition functions report the gap.
    public func conditionResolution() -> FactionConditionResolution {
        guard let runtime else { return .empty }
        var profiles: [ReferenceKey: ActorSocialProfile] = [:]
        for key in [ReferenceKey.player] + (world?.residentActorKeys() ?? []) {
            profiles[key] = profile(of: key)
        }
        return FactionConditionResolution(
            factions: runtime.factions,
            sourcePlugin: runtime.pluginName,
            derivation: runtime.derivation,
            profiles: profiles
        )
    }

    /// The `NPC_` identity a `RELA` record would name for `key`, resolved
    /// through the relationship store's own index.
    public func relationshipBase(of key: ReferenceKey) -> ResolvedFormID? {
        guard
            let runtime,
            let base = world?.placedActorBase(of: key),
            let plugin = runtime.pluginName
        else { return nil }
        return runtime.derivation.relationships.resolvedID(base, fromPlugin: plugin)
    }

    // MARK: - Hostility

    /// What `key` makes of the player. Nil without a runtime or for the player.
    public func derivedHostilityDecision(of key: ReferenceKey) -> HostilityDecision? {
        guard runtime != nil, key != .player, let observer = world?.actorValueHolder(for: key)
        else { return nil }
        seed(observer)
        return runtime?.decision(observer, toward: .player)
    }

    /// The derived answer, or the stored override alone without a runtime.
    /// The override is the derivation's first term, so it is not read twice.
    public func hostility(of key: ReferenceKey) -> ActorHostility {
        derivedHostilityDecision(of: key)?.hostility
            ?? store.component(ActorCombatState.self, for: key)?.hostility
            ?? .neutral
    }

    @discardableResult
    public func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        store.set(
            ActorCombatState(hostility: hostility), for: key, in: world?.cellLocation(of: key)
        )
    }

    /// What the derivation reads about the player's bounties.
    public func setCrimeHostility(_ source: any CrimeHostilitySource) {
        runtime?.derivation.crime = source
    }

    // MARK: - Memberships

    /// - Returns: true when the stored memberships changed.
    @discardableResult
    public func join(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8 = 0) -> Bool {
        guard let holder = world?.actorValueHolder(for: key), runtime != nil else { return false }
        seed(holder)
        return runtime?.join(key, to: faction, rank: rank, in: holder.cell) ?? false
    }

    /// - Returns: true when the actor was a member.
    @discardableResult
    public func leave(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        guard let holder = world?.actorValueHolder(for: key), runtime != nil else { return false }
        seed(holder)
        return runtime?.leave(key, from: faction, in: holder.cell) ?? false
    }
}
