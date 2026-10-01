// App side of `FactionCoordinator`: builds it from the provider, hands its
// runtimes to the Papyrus bridge, and answers `FactionWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyCombat
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

/// Answers `FactionWorld` from the session systems `game` owns.
final class FactionWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// After `wirePerks`: an actor's `SNAM` run resolves through the same
    /// template resolver as its stats.
    func wireFactions(provider: any WorldDataProviding) {
        guard
            let social = provider as? FactionDataProviding,
            let factionStore = social.factionStore,
            let relationshipStore = social.relationshipStore
        else { return }
        game.factions.attach(world: self)
        game.factions.wire(
            factions: factionStore,
            relationships: relationshipStore,
            baselines: (provider as? ActorValueDataProviding)?
                .actorValueBaselines?
                .resolver
                .map(ActorFactionBaselineResolver.init(actorValues:)),
            pluginName: (provider as? MagicDataProviding)?.magicItemPluginName
        )
    }

    /// Closures, because `wireFactions` runs after the Papyrus bridge is built.
    func wireNatives(bridge: PapyrusWorldStateBridge) {
        let factions = game.factions
        bridge.factionRuntime = { [weak factions] key in factions?.seededRuntime(for: key) }
        bridge.relationshipRuntime = { [weak factions] in factions?.relationships }
        bridge.socialDecision = { [weak factions] observer, target in
            factions?.socialDecision(of: observer, toward: target).map {
                PapyrusSocialDecision(isHostile: $0.isHostile, factionReaction: $0.factionReaction)
            }
        }
        bridge.actorSocialBase = { [weak factions] key in factions?.relationshipBase(of: key) }
        bridge.factionRelationIndex = { [weak factions] in factions?.relations }
        bridge.socialProfile = { [weak factions] key in factions?.profile(of: key) }
    }
}

extension FactionWorldAdapter: FactionWorld {
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        game.actorWorld.actorValueHolder(for: key)
    }

    func residentActorKeys() -> [ReferenceKey] {
        game.actorWorld.combatActors().map(\.key)
    }

    func placedActorBase(of key: ReferenceKey) -> FormID? {
        game.streamer?.referenceEntry(key: key)?.placedActor?.base
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        game.streamer?.cellLocation(of: key)
    }
}
