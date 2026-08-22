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

/// Faction state the controller owns. Extensions cannot add stored properties,
/// so it lives as one value on `GameViewController`.
struct FactionBridgeState {
    /// Memberships, seeding and the hostility derivation over them, built by
    /// `wireFactions` when the provider can supply a FACT index. Nil without
    /// game data, and then every actor answers from the stored override alone,
    /// exactly as it did before this milestone.
    var runtime: FactionRuntime?
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
        factions.runtime = FactionRuntime(
            store: worldState,
            factions: factionStore,
            derivation: HostilityDerivation(
                relations: FactionRelationIndex(store: factionStore),
                relationships: relationshipStore
            ),
            baselines: baselines,
            pluginName: (provider as? MagicDataProviding)?.magicItemPluginName
        )
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
