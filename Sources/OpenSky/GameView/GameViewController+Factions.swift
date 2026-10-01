// Session wiring for factions and derived hostility: builds the faction runtime
// over the provider's FACT and RELA indexes, seeds an actor from its `SNAM` run,
// and answers whether a resident actor is hostile to the player. The derivation
// runs on every query and is not cached, because actor values change every
// frame. Seeding walks the template chain, so it runs once per actor per
// session, behind a `Set` check.

import AppKit
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

/// Faction state the controller owns. Extensions cannot add stored properties,
/// so it lives as one value on `GameViewController`.
struct FactionBridgeState {
    /// Memberships, seeding and the hostility derivation over them, built by
    /// `wireFactions` when the provider can supply a FACT index. Nil without
    /// game data, and then every actor answers from the stored override alone,
    /// exactly as it did before this milestone.
    var runtime: FactionRuntime?
    /// Scripted relationship ranks over the same store, built
    /// beside the faction runtime because both need the provider's RELA index.
    /// Nil without game data, and then `SetRelationshipRank` refuses rather than
    /// writing a rank nothing can read back.
    var relationships: RelationshipRuntime?
    /// The load order's flattened interfaction reaction table, built once beside
    /// the derivation that already holds one. Kept here as well so
    /// `Faction.GetReaction` can be answered without an actor to hang the
    /// question on.
    var relations: FactionRelationIndex?
    /// Human-readable result of the last faction action.
    var lastActionText = "No faction action yet."
}

extension GameViewController {
    /// Builds the faction runtime over the provider's FACT and RELA indexes.
    ///
    /// Wired after `wirePerks`, because the baselines it reads are the ones the
    /// actor-value side already loaded: the template resolver behind an actor's
    /// `SNAM` run is the same one behind its stats.
    func wireFactions(provider: any WorldDataProviding) {
        guard
            let social = provider as? FactionDataProviding,
            let factionStore = social.factionStore,
            let relationshipStore = social.relationshipStore
        else { return }
        let baselines = (provider as? ActorValueDataProviding)?
            .actorValueBaselines?
            .resolver
            .map(ActorFactionBaselineResolver.init(actorValues:))
        let relations = FactionRelationIndex(store: factionStore)
        factions.relations = relations
        factions.relationships = RelationshipRuntime(
            store: worldState,
            relationships: relationshipStore
        )
        factions.runtime = FactionRuntime(
            store: worldState,
            factions: factionStore,
            derivation: HostilityDerivation(
                relations: relations,
                relationships: relationshipStore
            ),
            baselines: baselines,
            pluginName: (provider as? MagicDataProviding)?.magicItemPluginName
        )
    }

    // MARK: - Condition seam

    /// Faction memberships, relationship ranks, and the derivation, as the
    /// faction condition functions read them. Profiles cover the player and every
    /// resident actor; an unstreamed actor has none, so the functions report the
    /// gap. Seeding happens here because the condition body is nonisolated and
    /// cannot reach the store.
    func factionConditionResolution() -> FactionConditionResolution {
        guard let runtime = factions.runtime else { return .empty }
        var profiles: [ReferenceKey: ActorSocialProfile] = [:]
        for key in [ReferenceKey.player] + combatActors().map(\.key) {
            guard let holder = actorValueHolder(for: key) else { continue }
            seedFactions(of: holder)
            profiles[key] = factions.runtime?.profile(of: holder)
        }
        return FactionConditionResolution(
            factions: runtime.factions,
            sourcePlugin: (worldData as? MagicDataProviding)?.magicItemPluginName,
            derivation: runtime.derivation,
            profiles: profiles
        )
    }

    // MARK: - Papyrus seam

    /// What one actor makes of another, for `Actor.GetFactionReaction` and
    /// `Actor.IsHostileToActor`'s condition twin.
    ///
    /// Both actors are seeded first, so a script asking about somebody nobody has
    /// looked at sees the authored `SNAM` run rather than an empty membership
    /// list.
    func socialDecision(
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> PapyrusSocialDecision? {
        guard
            let observerHolder = actorValueHolder(for: observer),
            let targetHolder = actorValueHolder(for: target)
        else { return nil }
        seedFactions(of: observerHolder)
        seedFactions(of: targetHolder)
        guard let runtime = factions.runtime else { return nil }
        let mine = runtime.profile(of: observerHolder)
        let theirs = runtime.profile(of: targetHolder)
        return PapyrusSocialDecision(
            isHostile: runtime.derivation.decide(mine, toward: theirs).isHostile,
            factionReaction: runtime.derivation.factionReaction(of: mine, toward: theirs)
                ?? .neutral
        )
    }

    /// One actor's social profile, seeded first, for `GetCrimeFaction`,
    /// `IsGuard` and the guard pass. Nil without faction data or
    /// for an actor that is not resident.
    func socialProfile(of key: ReferenceKey) -> ActorSocialProfile? {
        guard let holder = actorValueHolder(for: key) else { return nil }
        seedFactions(of: holder)
        return factions.runtime?.profile(of: holder)
    }

    /// The faction runtime, with `key` seeded first so a membership read sees the
    /// actor's authored run. Nil in a session with no faction data.
    func seededFactionRuntime(for key: ReferenceKey) -> FactionRuntime? {
        if let holder = actorValueHolder(for: key) {
            seedFactions(of: holder)
        }
        return factions.runtime
    }

    /// The faction natives' collaborators. Closures, because `wireFactions` runs
    /// after the Papyrus bridge is built. The membership accessor takes its actor
    /// because a read must seed it first, which mutates a value this controller
    /// owns.
    func wireFactionNatives(bridge: PapyrusWorldStateBridge) {
        bridge.factionRuntime = { [weak self] key in
            self?.seededFactionRuntime(for: key)
        }
        bridge.relationshipRuntime = { [weak self] in self?.factions.relationships }
        bridge.socialDecision = { [weak self] observer, target in
            self?.socialDecision(of: observer, toward: target)
        }
        bridge.actorSocialBase = { [weak self] key in
            self?.actorRelationshipBase(of: key)
        }
        bridge.factionRelationIndex = { [weak self] in self?.factions.relations }
        bridge.socialProfile = { [weak self] key in self?.socialProfile(of: key) }
    }

    /// The `NPC_` identity a `RELA` record would name for one reference, resolved
    /// through the relationship store's own index so it matches the keys that
    /// store built its pair table with.
    func actorRelationshipBase(of key: ReferenceKey) -> ResolvedFormID? {
        guard
            let base = streamer?.referenceEntry(key: key)?.placedActor?.base,
            let plugin = (worldData as? MagicDataProviding)?.magicItemPluginName
        else { return nil }
        return factions.runtime?.derivation.relationships
            .resolvedID(base, fromPlugin: plugin)
    }

    // MARK: - Derived hostility

    /// What `key` makes of the player, from its memberships, relationships and
    /// aggression, with the session override on top. Without a runtime (every
    /// synthetic scene) only the stored override answers.
    func derivedHostilityDecision(of key: ReferenceKey) -> HostilityDecision? {
        guard
            let runtime = factions.runtime,
            key != .player,
            let observer = actorValueHolder(for: key)
        else { return nil }
        seedFactions(of: observer)
        return runtime.decision(observer, toward: .player)
    }

    /// The derived answer, or the stored override alone without a faction
    /// runtime. The override is the first term of the derivation, so it is not
    /// read twice.
    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        if let decision = derivedHostilityDecision(of: key) {
            return decision.hostility
        }
        return worldState.component(ActorCombatState.self, for: key)?.hostility ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        worldState.set(
            ActorCombatState(hostility: hostility),
            for: key,
            in: streamer?.cellLocation(of: key)
        )
    }

    /// Copies `holder`'s authored `SNAM` run into the store the first time this
    /// session sees it, and does nothing on every call after that.
    func seedFactions(of holder: ActorValueHolder) {
        guard factions.runtime?.needsSeeding(holder.key) == true else { return }
        guard var runtime = factions.runtime else { return }
        runtime.seed(holder)
        factions.runtime = runtime
    }

    // MARK: - Memberships

    /// Puts `key` in `faction` at `rank`, reporting what happened.
    ///
    /// - Returns: true when the stored memberships changed.
    @discardableResult
    func joinFaction(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8 = 0) -> Bool {
        guard let holder = actorValueHolder(for: key), let runtime = factions.runtime else {
            return false
        }
        seedFactions(of: holder)
        return runtime.join(key, to: faction, rank: rank, in: holder.cell)
    }

    /// Takes `key` out of `faction`.
    ///
    /// - Returns: true when the actor was a member.
    @discardableResult
    func leaveFaction(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        guard let holder = actorValueHolder(for: key), let runtime = factions.runtime else {
            return false
        }
        seedFactions(of: holder)
        return runtime.leave(key, from: faction, in: holder.cell)
    }
}
