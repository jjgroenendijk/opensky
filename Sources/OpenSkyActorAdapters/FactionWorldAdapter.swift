// App side of `FactionCoordinator`: builds it from the provider, hands its
// runtimes to the Papyrus bridge, and answers `FactionWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyFactions
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface

/// What the faction adapter reads. The streamer is a closure, because a reload
/// replaces it; the coordinator is one, because it is built with this adapter.
public struct FactionWorldDependencies {
    public let factions: () -> FactionCoordinator
    public let actors: any ActorWorldPort
    public let streamer: () -> CellStreamer?

    public init(
        factions: @escaping () -> FactionCoordinator,
        actors: any ActorWorldPort,
        streamer: @escaping () -> CellStreamer?
    ) {
        self.factions = factions
        self.actors = actors
        self.streamer = streamer
    }
}

/// Answers `FactionWorld` from the session systems it is given.
public final class FactionWorldAdapter {
    private let dependencies: FactionWorldDependencies

    public init(_ dependencies: FactionWorldDependencies) {
        self.dependencies = dependencies
    }

    public var factions: FactionCoordinator {
        dependencies.factions()
    }

    /// An actor's `SNAM` run resolves through the same template resolver as its stats.
    public static func sessionData(_ provider: WorldDataStores?) -> FactionSessionData? {
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
    public func papyrusNatives() -> PapyrusFactionNatives {
        let factions = factions
        return PapyrusFactionNatives(
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
    }
}

extension FactionWorldAdapter: FactionWorld {
    public func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        dependencies.actors.actorValueHolder(for: key)
    }

    public func residentActorKeys() -> [ReferenceKey] {
        dependencies.actors.combatActors().map(\.key)
    }

    public func placedActorBase(of key: ReferenceKey) -> FormID? {
        dependencies.streamer()?.residentActorPlacement(key: key)?.base
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        dependencies.streamer()?.cellLocation(of: key)
    }
}

extension FactionWorldAdapter: FactionWorldPort {}
