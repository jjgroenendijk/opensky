// The shell of the faction domain: owns the membership and relationship
// runtimes, seeds an actor from its `SNAM` run, and answers hostility toward
// the player. The rules live in `FactionRuntime` and `HostilityDerivation`.
// See docs/engine/coordinators.md.

public import OpenSkyActorsInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldState

/// The load order's faction and relationship records.
public struct FactionSessionData {
    public let factions: FactionStore
    public let relationships: RelationshipStore
    public let baselines: ActorFactionBaselineResolver?
    public let pluginName: String?

    public init(
        factions: FactionStore,
        relationships: RelationshipStore,
        baselines: ActorFactionBaselineResolver?,
        pluginName: String?
    ) {
        self.factions = factions
        self.relationships = relationships
        self.baselines = baselines
        self.pluginName = pluginName
    }
}

/// Owns the faction runtimes and reads the world through `FactionWorld`.
/// Without game data every runtime stays nil, and hostility answers from the
/// stored override alone.
@MainActor
public final class FactionCoordinator {
    /// Nil without faction data.
    public private(set) var runtime: FactionRuntime?
    /// Nil without faction data, and then `SetRelationshipRank` refuses.
    public let relationships: RelationshipRuntime?
    /// Kept apart from the derivation's copy, so `Faction.GetReaction` needs
    /// no actor.
    public private(set) var relations: FactionRelationIndex?

    let store: WorldStateStore
    let world: any FactionWorld
    /// Each ordered pair's answer, kept until something it reads is written.
    private var pairs = HostilityPairCache()

    public init(store: WorldStateStore, world: any FactionWorld, data: FactionSessionData?) {
        self.store = store
        self.world = world
        guard let data else {
            relationships = nil
            return
        }
        let relations = FactionRelationIndex(store: data.factions)
        self.relations = relations
        relationships = RelationshipRuntime(store: store, relationships: data.relationships)
        runtime = FactionRuntime(
            store: store,
            factions: data.factions,
            derivation: HostilityDerivation(
                relations: relations,
                relationships: data.relationships
            ),
            baselines: data.baselines,
            pluginName: data.pluginName
        )
    }

    /// Applies the reactions scripts set, replacing the earlier set.
    public func setScriptedReactions(_ entries: [FactionReactionOverride]) {
        pairs.reset()
        relations?.setScriptedReactions(entries)
        runtime?.derivation.relations.setScriptedReactions(entries)
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
        if let holder = world.actorValueHolder(for: key) {
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
        guard let holder = world.actorValueHolder(for: key) else { return nil }
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
        pairAnswer(of: observer, toward: target).map {
            ($0.decision.isHostile, $0.factionReaction)
        }
    }

    /// What `observer` makes of `target`: crime, then relationship rank, then factions.
    public func reaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction? {
        pairAnswer(of: observer, toward: target)?.decision.reaction
    }

    /// The game keeps each pair's reaction once it is worked out, until a reset clears it
    /// (docs/engine/hostility.md#memberships-at-runtime). Here a write of any membership,
    /// relationship, or hostility, a load, or a change of the reaction or crime rules clears
    /// every pair.
    private func pairAnswer(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> HostilityPairAnswer? {
        pairs.expire(revision: store.revision(of: HostilityPairCache.readKinds))
        let pair = HostilityPair(observer: observer, target: target)
        // An actor that left has no profile, so it gets no answer, as before it was cached.
        if
            let known = pairs.answers[pair], world.actorValueHolder(for: observer) != nil,
            world.actorValueHolder(for: target) != nil
        {
            return known
        }
        guard
            let mine = profile(of: observer),
            let theirs = profile(of: target),
            let derivation = runtime?.derivation
        else { return nil }
        let answer = HostilityPairAnswer(
            decision: derivation.decide(mine, toward: theirs),
            factionReaction: derivation.factionReaction(of: mine, toward: theirs) ?? .neutral
        )
        // Seeding the pair may have written the store; the answer holds from here on.
        pairs.expire(revision: store.revision(of: HostilityPairCache.readKinds))
        pairs.answers[pair] = answer
        return answer
    }

    /// The player and every resident actor, seeded. An unstreamed actor has
    /// no profile, so the condition functions report the gap.
    public func conditionResolution() -> FactionConditionResolution {
        guard let runtime else { return .empty }
        var profiles: [ReferenceKey: ActorSocialProfile] = [:]
        for key in [ReferenceKey.player] + world.residentActorKeys() {
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
            let base = world.placedActorBase(of: key),
            let plugin = runtime.pluginName
        else { return nil }
        return runtime.derivation.relationships.resolvedID(base, fromPlugin: plugin)
    }

    // MARK: - Hostility

    /// Whether `observer` attacks `target` on sight. False when either has no profile.
    public func isHostile(_ observer: ReferenceKey, toward target: ReferenceKey) -> Bool {
        socialDecision(of: observer, toward: target)?.isHostile ?? false
    }

    /// What `key` makes of the player. Nil without a runtime or for the player.
    public func derivedHostilityDecision(of key: ReferenceKey) -> HostilityDecision? {
        guard key != .player, runtime != nil else { return nil }
        return pairAnswer(of: key, toward: .player)?.decision
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
            ActorCombatState(hostility: hostility), for: key, in: world.cellLocation(of: key)
        )
    }

    /// What the derivation reads about the player's bounties.
    /// The crime system sends its snapshot every frame, so only a changed one clears the pairs.
    public func setCrimeHostility(_ source: any CrimeHostilitySource) {
        if !source.answersAlike(runtime?.derivation.crime) {
            pairs.reset()
        }
        runtime?.derivation.crime = source
    }

    // MARK: - Memberships

    /// - Returns: true when the stored memberships changed.
    @discardableResult
    public func join(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8 = 0) -> Bool {
        guard let holder = world.actorValueHolder(for: key), runtime != nil else { return false }
        seed(holder)
        return runtime?.join(key, to: faction, rank: rank, in: holder.cell) ?? false
    }

    /// - Returns: true when the actor was a member.
    @discardableResult
    public func leave(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        guard let holder = world.actorValueHolder(for: key), runtime != nil else { return false }
        seed(holder)
        return runtime?.leave(key, from: faction, in: holder.cell) ?? false
    }
}
