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
public import OpenSkyGameData
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
public protocol ScriptWorldHost: AnyObject, SendableMetatype {
    /// The leveled-list edits scripts made, saved with the session.
    var worldRecords: (any WorldRecordsPort)? { get }
    var containerMenu: any ContainerMenuPort { get }
    var hud: any HUDPort { get }
    var player: any PlayerPort { get }
    var ragdoll: any RagdollPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var mountWorld: any MountWorldPort { get }
}

/// Every host a `ScriptWorldAdapter` part reads, all one object.
public typealias ScriptWorldHosts = ScriptActorBindingsHost & ScriptFeatureBindingsHost &
    ScriptNodeBindingsHost &
    ScriptPerkBindingsHost & ScriptPhysicsBindingsHost & ScriptPlayerBindingsHost &
    ScriptReferenceBindingsHost & ScriptSessionBindingsHost & ScriptSkyBindingsHost &
    ScriptSoundBindingsHost & ScriptWorldHost

public final class ScriptWorldAdapter {
    public let game: any ScriptWorldHost
    public let state = ScriptPartState()

    let hosts: any ScriptWorldHosts

    public var actorBindings: ScriptActorBindingsAdapter {
        ScriptActorBindingsAdapter(
            game: hosts, skyBindings: skyBindings, physicsBindings: physicsBindings
        )
    }

    public var perkBindings: ScriptPerkBindingsAdapter {
        ScriptPerkBindingsAdapter(game: hosts)
    }

    public var sessionBindings: ScriptSessionBindingsAdapter {
        ScriptSessionBindingsAdapter(
            game: hosts, state: state, playerBindings: playerBindings,
            referenceBindings: referenceBindings, soundBindings: soundBindings,
            nodeBindings: nodeBindings
        )
    }

    var playerBindings: ScriptPlayerBindingsAdapter {
        ScriptPlayerBindingsAdapter(game: hosts, physicsBindings: physicsBindings)
    }

    var referenceBindings: ScriptReferenceBindingsAdapter {
        ScriptReferenceBindingsAdapter(game: hosts, nodeBindings: nodeBindings)
    }

    private(set) lazy var soundBindings = ScriptSoundBindingsAdapter(
        game: hosts, state: state
    )
    var physicsBindings: ScriptPhysicsBindingsAdapter {
        ScriptPhysicsBindingsAdapter(
            game: hosts, state: state, nodeBindings: nodeBindings
        )
    }

    public var nodeBindings: ScriptNodeBindingsAdapter {
        ScriptNodeBindingsAdapter(game: hosts, state: state)
    }

    public private(set) lazy var skyBindings = ScriptSkyBindingsAdapter(
        game: hosts, state: state
    )
    public var featureBindings: ScriptFeatureBindingsAdapter {
        ScriptFeatureBindingsAdapter(
            game: hosts, skyBindings: skyBindings, soundBindings: soundBindings
        )
    }

    public init(game: some ScriptWorldHosts) {
        hosts = game
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
        state.bridge = bridge
        bridge.sessionNatives.clockSource = { [weak gameSession] in gameSession?.gameClock }
        // The game counts real time from its launch, without frozen time (CK wiki
        // "GetCurrentRealTime - Utility"): the time before this session, then its frames.
        let beforeSession = BenchmarkAppStart.processStart().map { -$0.timeIntervalSinceNow } ?? 0
        bridge.sessionNatives.realTimeSource = { [weak gameSession] in
            beforeSession + (gameSession?.gameTime.realSecondsRun ?? 0)
        }
        actorBindings.fillActorNatives(bridge: bridge)
        nodeBindings.fillLineOfSight(bridge: bridge)
        perkBindings.fillSpellNatives(bridge: bridge, provider: provider)
        skyBindings.fillSky(bridge: bridge)
        nodeBindings.fillModelNodes(provider: provider, gameSession: gameSession)
        sessionBindings.fillGameNatives(bridge: bridge)
        bridge.sessionNatives.itemScripts = Self.itemScripts(provider.placedRecords)
        bridge.formIDResolver = provider.scriptFormIDResolver
        fillPlayerNatives(bridge: bridge)
        return bridge
    }

    /// The natives that reach the player's mount, sneak state, and HUD.
    public func fillPlayerNatives(bridge: PapyrusWorldStateBridge) {
        playerNatives.fillPlayerNatives(bridge: bridge)
    }

    /// An `AttachAshPile` pile opens its actor's inventory, as activating the body would.
    func searchAshPileOwner(of event: InteractionEvent, bridge: PapyrusWorldStateBridge) {
        playerNatives.searchAshPileOwner(of: event, bridge: bridge)
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
        playerNatives.crosshairReference
    }

    public func referenceKey(formID: FormID) -> ReferenceKey? {
        playerNatives.referenceKey(formID: formID)
    }

    public var gameClock: GameClock? {
        playerNatives.gameClock
    }

    public var playerLocation: ResolvedFormID?? {
        playerNatives.playerLocation
    }
}

/// The player natives and the crosshair, clock, and location reads of `ScriptWorldAdapter`.
struct ScriptPlayerNatives {
    let game: any ScriptWorldHost

    func fillPlayerNatives(bridge: PapyrusWorldStateBridge) {
        bridge.sessionNatives.leveledEdits = { [weak game] in
            game?.worldRecords?.leveledScriptEdits
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
    }

    func searchAshPileOwner(of event: InteractionEvent, bridge: PapyrusWorldStateBridge) {
        guard
            let entry = game.streamer.referenceEntry(formID: event.target.interaction.reference),
            let actor = bridge.ashPileOwner(of: entry.key),
            game.ragdoll.searchCorpse(actor)
        else { return }
        game.containerMenu.open()
    }

    var crosshairReference: FormID? {
        game.hud.interactionTarget?.interaction.reference
    }

    func referenceKey(formID: FormID) -> ReferenceKey? {
        game.streamer.referenceEntry(formID: formID)?.key
    }

    var gameClock: GameClock? {
        game.gameSession?.gameClock
    }

    var playerLocation: ResolvedFormID?? {
        let streamer = game.streamer
        guard
            let current = streamer.currentCellLocation,
            let scene = streamer.residentScene(at: current)
        else { return nil }
        return .some(game.runtimeStateWorld.location(of: scene.locationKey))
    }
}

extension ScriptWorldAdapter {
    var playerNatives: ScriptPlayerNatives {
        ScriptPlayerNatives(game: game)
    }
}
