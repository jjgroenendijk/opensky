// Session wiring for factions and derived hostility (issue #503, roadmap item
// 21.3): builds the faction runtime over the provider's FACT and RELA indexes,
// seeds an actor from its authored `SNAM` run, and answers the one question the
// combat loop asks about every resident actor — is this one angry with the
// player.
//
// AppKit stays in this controller satellite; the runtime, the derivation, the
// relation index and the component are all engine types that build into
// `openskycli` and are testable without a window.
//
// ## What is paid per frame, and what is not
//
// `combatHostility(of:)` is asked for every resident actor by the combat loop,
// the perception overlay, the dialogue candidate filter and the navigation
// panel, several times per frame. Two costs are in that path and only one of
// them is cheap.
//
// The derivation itself is cheap: two component reads, a pair lookup and a walk
// of two short membership lists, all dictionary work. It runs every time and is
// not cached, because a cache would have to be invalidated by every world-state
// write and actor values are rewritten sixty times a second — the cache would
// miss on nearly every query while still costing a comparison.
//
// Seeding is not cheap: it walks the actor's whole template chain. So it
// happens once per actor per session, guarded by a `Set` test that costs no
// copy of the runtime, and the mutating path is entered only on the first sight
// of an actor.

import AppKit
import OpenSkyFormats
import OpenSkyGameData

/// Faction state the controller owns. Extensions cannot add stored properties,
/// so it lives as one value on `GameViewController`.
struct FactionBridgeState {
    /// Memberships, seeding and the hostility derivation over them, built by
    /// `wireFactions` when the provider can supply a FACT index. Nil without
    /// game data, and then every actor answers from the stored override alone,
    /// exactly as it did before this milestone.
    var runtime: FactionRuntime?
    /// Scripted relationship ranks over the same store (issue #508), built
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
    func wireFactions(provider: any CellSceneProvider) {
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

    /// Faction memberships, relationship ranks and the derivation over them, as
    /// the condition machinery reads them (issue #508). This is what
    /// `GetInFaction`, `GetFactionRank`, `GetFactionRankDifference`,
    /// `GetFactionRelation`, `GetRelationshipRank` and `IsHostileToActor` answer
    /// from.
    ///
    /// Profiles are built for the player and every resident actor, which is the
    /// same set `runtimeStateActorResolution()` already walks. An actor no cell
    /// has streamed carries no profile and the functions report the gap rather
    /// than answering "belongs to nothing" — which is the honest answer, because
    /// this engine has not read that actor's record yet.
    ///
    /// Seeding happens here rather than in the condition body: the body is
    /// nonisolated and cannot reach the store, and a per-actor seed is a
    /// `Set` membership test after the first sight of each one.
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
            sourcePlugin: (streamerCellProvider as? MagicDataProviding)?.magicItemPluginName,
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
    /// `IsGuard` and the guard pass (issue #505). Nil without faction data or
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

    /// The faction natives' collaborators (issue #508, roadmap item 21.4).
    ///
    /// Closures for the reason the perk ones are: `wireFactions` runs after the
    /// Papyrus bridge is built, so a reference captured here would be nil
    /// forever. The membership accessor takes the actor it is about because
    /// reading a membership has to seed it first, and seeding is a mutating call
    /// on a struct this controller owns by value.
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
            let plugin = (streamerCellProvider as? MagicDataProviding)?.magicItemPluginName
        else { return nil }
        return factions.runtime?.derivation.relationships
            .resolvedID(base, fromPlugin: plugin)
    }

    // MARK: - Derived hostility

    /// What `key` currently makes of the player, derived from its memberships,
    /// its relationships and its own aggression, with the session's explicit
    /// override on top.
    ///
    /// Falls back to the stored override alone when there is no runtime, which
    /// is every synthetic scene: a session with no load order has no relation to
    /// derive anything from, and inventing one would make the panel toggle look
    /// broken.
    func derivedHostilityDecision(of key: ReferenceKey) -> HostilityDecision? {
        guard
            let runtime = factions.runtime,
            key != .player,
            let observer = actorValueHolder(for: key)
        else { return nil }
        seedFactions(of: observer)
        return runtime.decision(observer, toward: .player)
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

    /// Every faction `key` currently belongs to that the load order resolves.
    func resolvedFactions(of key: ReferenceKey) -> [ResolvedFaction] {
        factions.runtime?.resolvedFactions(of: key) ?? []
    }
}
