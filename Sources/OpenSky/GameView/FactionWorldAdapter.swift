// App side of `FactionCoordinator`: builds it from the provider, hands its
// runtimes to the Papyrus bridge, and answers `FactionWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyCells
import OpenSkyCombat
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScripting
import OpenSkyWorld

/// What the faction adapter reads. The streamer is a closure, because a reload
/// replaces it; the coordinator is one, because it is built with this adapter.
struct FactionWorldDependencies {
    let factions: () -> FactionCoordinator
    let actors: ActorWorldAdapter
    let streamer: () -> CellStreamer?
}

/// Answers `FactionWorld` from the session systems it is given.
final class FactionWorldAdapter {
    private let dependencies: FactionWorldDependencies

    init(_ dependencies: FactionWorldDependencies) {
        self.dependencies = dependencies
    }

    var factions: FactionCoordinator {
        dependencies.factions()
    }

    /// An actor's `SNAM` run resolves through the same template resolver as its stats.
    static func sessionData(_ provider: WorldDataStores?) -> FactionSessionData? {
        guard
            let provider,
            let factionStore = provider.factionStore,
            let relationshipStore = provider.relationshipStore
        else { return nil }
        return FactionSessionData(
            factions: factionStore,
            relationships: relationshipStore,
            baselines: provider
                .actorValueBaselines?
                .resolver
                .map(ActorFactionBaselineResolver.init(actorValues:)),
            pluginName: provider.magicItemPluginName
        )
    }

    /// One family value for the Papyrus bridge.
    func wireNatives(bridge: PapyrusWorldStateBridge) {
        let factions = factions
        bridge.factionNatives = PapyrusFactionNatives(
            runtime: { [weak factions] key in factions?.seededRuntime(for: key) },
            relationships: { [weak factions] in factions?.relationships },
            socialDecision: { [weak factions] observer, target in
                factions?.socialDecision(of: observer, toward: target).map {
                    PapyrusSocialDecision(
                        isHostile: $0.isHostile, factionReaction: $0.factionReaction
                    )
                }
            },
            socialBase: { [weak factions] key in factions?.relationshipBase(of: key) },
            relationIndex: { [weak factions] in factions?.relations },
            reactionsChanged: { [weak factions] in factions?.setScriptedReactions($0) },
            socialProfile: { [weak factions] key in factions?.profile(of: key) }
        )
        bridge.publishFactionReactions()
    }
}

extension FactionWorldAdapter: FactionWorld {
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        dependencies.actors.actorValueHolder(for: key)
    }

    func residentActorKeys() -> [ReferenceKey] {
        dependencies.actors.combatActors().map(\.key)
    }

    func placedActorBase(of key: ReferenceKey) -> FormID? {
        dependencies.streamer()?.residentActorPlacement(key: key)?.base
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        dependencies.streamer()?.cellLocation(of: key)
    }
}
