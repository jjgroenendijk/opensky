// App side of `CrimeCoordinator`: builds it from the provider, attaches the
// perception pass as its witnesses, and answers `CrimeSessionWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyCrime
public import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `CrimeWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol CrimeWorldHost: AnyObject {
    var dialogueWorld: any DialogueWorldPort { get }
    var storyWorld: any StoryWorldPort { get }
    var factions: any FactionPort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var mapWorld: any MapWorldPort { get }
    var perception: any PerceptionPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Answers `CrimeSessionWorld` from the session systems `game` owns.
public final class CrimeWorldAdapter {
    public let game: any CrimeWorldHost

    public let factionsHost: any CrimeFactionsHost
    public let jailHost: any CrimeJailHost
    public let actorsHost: any CrimeActorsHost

    public var factions: CrimeFactionsAdapter {
        CrimeFactionsAdapter(game: factionsHost)
    }

    public var jail: CrimeJailAdapter {
        CrimeJailAdapter(game: jailHost)
    }

    public var actors: CrimeActorsAdapter {
        CrimeActorsAdapter(game: actorsHost)
    }

    public init(game: some CrimeWorldHost & CrimeFactionsHost & CrimeJailHost & CrimeActorsHost) {
        factionsHost = game
        jailHost = game
        actorsHost = game
        self.game = game
    }

    /// Perception is built first: its pass answers "did anybody see it" for every crime.
    public func witnesses() -> PerceptionCrimeWitnesses {
        let store = game.worldState
        return PerceptionCrimeWitnesses(
            perception: game.perception.runtime,
            isAlive: { [weak store] key in
                store?.component(ActorDeathState.self, for: key)?.isDead != true
            }
        )
    }

    /// Ownership reads the same FACT store as the hostility derivation.
    public func sessionData(
        _ provider: WorldDataStores,
        store: WorldStateStore
    ) -> CrimeSessionData? {
        guard
            let factionStore = provider.factionStore,
            let pluginName = provider.magicItemPluginName
        else { return nil }
        return CrimeSessionData(
            runtime: CrimeRuntime(
                store: store, factions: factionStore,
                settings: CrimeSettings.resolve(store: provider.gameSettings)
            ),
            locations: provider.locationStore,
            pluginName: pluginName,
            texts: CrimeTexts
                .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        )
    }

    public func run(_ commands: [CrimeCommand]) {
        for command in commands {
            switch command {
            case let .showNotice(text): game.hud.showNotification(text)
            case let .applyGuardHostility(hostility): game.factions.setCrimeHostility(hostility)
            case let .incrementStat(name, amount): game.worldState.incrementMiscStat(
                    name,
                    by: amount
                )
            case let .stoleFromFaction(faction, value, witnessed):
                game.scripts.bridge?.noteStolenValue(value, from: faction, witnessed: witnessed)
            case let .settlePickpocketCatches(faction, forgotten):
                game.inventoryWorld.settlePickpocketCatches(
                    chargedTo: faction,
                    forgotten: forgotten
                )
            case let .speakTrespassWarning(witness):
                game.storyWorld.sayTopic("TRES", speaker: witness, lookAt: .player)
            case let .raiseStat(name, value):
                let current = game.worldState.miscStats.value(name)
                if value > current {
                    game.worldState.incrementMiscStat(name, by: value - current)
                }
            }
        }
    }
}

extension CrimeWorldAdapter: CrimeSessionWorld {
    // MARK: - Places and references

    public var references: (any PapyrusWorldReferenceSource)? {
        game.streamer
    }

    public var currentCellLocation: CellSceneLocation? {
        game.streamer.currentCellLocation
    }

    public func cellOwnership(at location: CellSceneLocation) -> RecordOwnership? {
        game.streamer.residentScene(at: location)?.owner
    }

    public func cellTrespassFlags(at location: CellSceneLocation) -> CellTrespassFlags {
        game.streamer.residentScene(at: location)?.trespass ?? CellTrespassFlags()
    }

    public func cellLocationLink(at location: CellSceneLocation)
        -> (link: FormID, plugin: String)?
    {
        guard
            let scene = game.streamer.residentScene(at: location),
            let link = scene.locationLink,
            let plugin = scene.ownerPluginName
        else { return nil }
        return (link, plugin)
    }

    public func itemValue(of item: FormID) -> Int64 {
        Int64(game.inventory.itemDefinitions?.gameValue(of: item) ?? 0)
    }

    public func actorName(_ key: ReferenceKey) -> String {
        game.dialogueWorld.speakerLabel(for: key)
    }

    public var crosshairInteraction: PlacedInteraction? {
        game.hud.interactionTarget?.interaction
    }

    // MARK: - Factions

    // MARK: - Items and vendors

    public var inventory: (any InventoryAccess)? {
        game.inventory.runtime?.inventory
    }

    public func targetOwnership() -> ReferenceOwnershipReadout? {
        game.inventory.targetOwnership()
    }

    public func stolenPlayerStacks() -> [ItemStackReadout] {
        guard let runtime = game.inventory.runtime else { return [] }
        return game.inventory.readout(
            runtime.inventory.inventory(of: runtime.player).stacks.filter(\.stolen)
        )
    }

    public func vendor(faction key: ReferenceKey) -> Vendor? {
        game.inventory.vendors?.core.vendor(faction: key)
    }

    public func vendor(of actor: ReferenceKey) -> Vendor? {
        game.inventory.vendors?.vendor(of: actor)
    }

    // MARK: - Clock and player

    // MARK: - Guards
}

extension CrimeWorldAdapter: CrimeWorldPort {}
