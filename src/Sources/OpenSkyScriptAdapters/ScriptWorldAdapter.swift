// App side of `ScriptCoordinator`: builds the world bridge, gives its natives
// their collaborators, binds script lifetime to cell streaming, and ticks the
// VM from the renderer. The readout logic lives in the coordinator.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `ScriptWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol ScriptWorldHost: AnyObject {
    var worldData: WorldDataStores? { get }
    var containerMenu: any ContainerMenuPort { get }
    var hud: any HUDPort { get }
    var player: any PlayerPort { get }
    var ragdoll: any RagdollPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var mountWorld: any MountWorldPort { get }
}

public final class ScriptWorldAdapter {
    public let game: any ScriptWorldHost
    public let state = ScriptPartState()

    public let actorBindingsHost: any ScriptActorBindingsHost
    public let perkBindingsHost: any ScriptPerkBindingsHost
    public let sessionBindingsHost: any ScriptSessionBindingsHost
    public let playerBindingsHost: any ScriptPlayerBindingsHost
    public let referenceBindingsHost: any ScriptReferenceBindingsHost
    public let soundBindingsHost: any ScriptSoundBindingsHost
    public let physicsBindingsHost: any ScriptPhysicsBindingsHost
    public let nodeBindingsHost: any ScriptNodeBindingsHost
    public let skyBindingsHost: any ScriptSkyBindingsHost
    public let featureBindingsHost: any ScriptFeatureBindingsHost

    public var actorBindings: ScriptActorBindingsAdapter {
        ScriptActorBindingsAdapter(
            game: actorBindingsHost, skyBindings: skyBindings, physicsBindings: physicsBindings
        )
    }

    public var perkBindings: ScriptPerkBindingsAdapter {
        ScriptPerkBindingsAdapter(game: perkBindingsHost)
    }

    public var sessionBindings: ScriptSessionBindingsAdapter {
        ScriptSessionBindingsAdapter(
            game: sessionBindingsHost, state: state, playerBindings: playerBindings,
            referenceBindings: referenceBindings, soundBindings: soundBindings,
            nodeBindings: nodeBindings
        )
    }

    public var playerBindings: ScriptPlayerBindingsAdapter {
        ScriptPlayerBindingsAdapter(game: playerBindingsHost, physicsBindings: physicsBindings)
    }

    public var referenceBindings: ScriptReferenceBindingsAdapter {
        ScriptReferenceBindingsAdapter(game: referenceBindingsHost, nodeBindings: nodeBindings)
    }

    public private(set) lazy var soundBindings = ScriptSoundBindingsAdapter(
        game: soundBindingsHost, state: state
    )
    public var physicsBindings: ScriptPhysicsBindingsAdapter {
        ScriptPhysicsBindingsAdapter(
            game: physicsBindingsHost, state: state, nodeBindings: nodeBindings
        )
    }

    public var nodeBindings: ScriptNodeBindingsAdapter {
        ScriptNodeBindingsAdapter(game: nodeBindingsHost, state: state)
    }

    public private(set) lazy var skyBindings = ScriptSkyBindingsAdapter(
        game: skyBindingsHost, state: state
    )
    public var featureBindings: ScriptFeatureBindingsAdapter {
        ScriptFeatureBindingsAdapter(
            game: featureBindingsHost, skyBindings: skyBindings, soundBindings: soundBindings
        )
    }

    public init(game: some ScriptWorldHost & ScriptActorBindingsHost & ScriptPerkBindingsHost &
        ScriptSessionBindingsHost & ScriptPlayerBindingsHost & ScriptReferenceBindingsHost &
        ScriptSoundBindingsHost & ScriptPhysicsBindingsHost & ScriptNodeBindingsHost &
        ScriptSkyBindingsHost & ScriptFeatureBindingsHost)
    {
        actorBindingsHost = game
        perkBindingsHost = game
        sessionBindingsHost = game
        playerBindingsHost = game
        referenceBindingsHost = game
        soundBindingsHost = game
        physicsBindingsHost = game
        nodeBindingsHost = game
        skyBindingsHost = game
        featureBindingsHost = game
        self.game = game
    }

    /// Builds the bridge with every seam, then the VM over it. The streamer, the
    /// renderer, and the provider each feed the VM one way, so the engine never
    /// depends on it. Without compiled scripts there is no VM.
    public func makeBridge(
        provider: WorldDataStores,
        gameSession: GameSession,
        streamer: CellStreamer,
        worldState: WorldStateStore
    ) -> PapyrusWorldStateBridge {
        let bridge = PapyrusWorldStateBridge(
            worldState: worldState, references: streamer,
            globals: game.runtimeState.globalStore,
            seams: featureBindings.seams(provider: provider, worldState: worldState)
        )
        bridge.sessionNatives.clockSource = { [weak gameSession] in gameSession?.gameClock }
        // The game counts real time from its launch, without frozen time (CK wiki
        // "GetCurrentRealTime - Utility"): the time before this session, then its frames.
        let beforeSession = BenchmarkAppStart.processStart().map { -$0.timeIntervalSinceNow } ?? 0
        bridge.sessionNatives.realTimeSource = { [weak gameSession] in
            beforeSession + (gameSession?.gameTime.realSecondsRun ?? 0)
        }
        _ = ScriptActorNativesWiring(actorBindings, bridge: bridge)
        _ = ScriptLineOfSightWiring(nodeBindings, bridge: bridge)
        _ = ScriptSpellNativesWiring(perkBindings, bridge: bridge, provider: provider)
        _ = ScriptSkyWiring(skyBindings, bridge: bridge)
        _ = ScriptModelNodesWiring(nodeBindings, provider: provider, gameSession: gameSession)
        _ = ScriptGameNativesWiring(sessionBindings, bridge: bridge, provider: provider)
        bridge.sessionNatives.itemScripts = Self.itemScripts(provider.placedRecords)
        bridge.formIDResolver = provider.scriptFormIDResolver
        bridge.leveledEdits = { [weak game] in
            game?.worldData?.actorValueBaselines?.leveling.scriptEdits
        }
        bridge.playerNatives
            .playersLastMount = { [weak game] in game?.vehicleWorld.vehicles.playersLastMount }
        bridge.playerNatives.dismount = { [weak game] actor in
            game?.mountWorld.dismount(actor) ?? false
        }
        bridge.playerNatives
            .togglePlayerSneaking = { [weak game] in game?.player.isSneaking.toggle() }
        bridge.playerNatives
            .toggleMenus = { [weak game] in game?.hud.update { $0.layerEnabled.toggle() } }
        return bridge
    }

    /// An `AttachAshPile` pile opens its actor's inventory, as activating the body would.
    func searchAshPileOwner(of event: InteractionEvent, bridge: PapyrusWorldStateBridge) {
        guard
            let entry = game.streamer?.referenceEntry(formID: event.target.interaction.reference),
            let actor = bridge.ashPileOwner(of: entry.key),
            game.ragdoll.searchCorpse(actor)
        else { return }
        game.containerMenu.open()
    }

    /// Decoded once per base form, because each equip asks again.
    private static func itemScripts(
        _ lookup: PlacedRecordLookup?
    ) -> (ReferenceKey) -> [AttachedScript] {
        var cache: [ReferenceKey: [AttachedScript]] = [:]
        return { base in
            if let known = cache[base] {
                return known
            }
            let scripts = lookup?.scripts(ofBase: base) ?? []
            cache[base] = scripts
            return scripts
        }
    }
}

extension ScriptWorldAdapter: ScriptWorld {
    public var crosshairReference: FormID? {
        game.hud.interactionTarget?.interaction.reference
    }

    public func referenceKey(formID: FormID) -> ReferenceKey? {
        game.streamer?.referenceEntry(formID: formID)?.key
    }

    public var gameClock: GameClock? {
        game.gameSession?.gameClock
    }

    public var playerLocation: ResolvedFormID?? {
        guard
            let streamer = game.streamer,
            let current = streamer.currentCellLocation,
            let scene = streamer.residentScene(at: current)
        else { return nil }
        return .some(game.runtimeStateWorld.location(of: scene.locationKey))
    }
}
