import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
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
import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `ScriptFeatureBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptFeatureBindingsHost: AnyObject {
    var aiWorld: any AIWorldPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var effectsWorld: any EffectsWorldPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var mapWorld: any MapWorldPort { get }
    var menuWorld: any MenuWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var objectAnimationWorld: any ObjectAnimationWorldPort { get }
    var storyWorld: any StoryWorldPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptFeatureBindingsAdapter {
    public let game: any ScriptFeatureBindingsHost
    public let skyBindings: ScriptSkyBindingsAdapter
    public let soundBindings: ScriptSoundBindingsAdapter
}

extension ScriptFeatureBindingsAdapter {
    /// The features the natives reach, each answered by its world adapter.
    public func seams(
        provider: any WorldRecordsPort,
        worldState: WorldStateStore
    ) -> PapyrusBridgeSeams {
        var seams = PapyrusBridgeSeams()
        seams.quests = quests(provider: provider, worldState: worldState)
        seams.inventory = game.inventoryWorld
        seams.alchemy = game.inventoryWorld
        seams.actorAI = game.vehicleWorld
        seams.furniture = game.aiWorld
        seams.objectAnimation = game.audioFileSystem == nil ? nil : game.objectAnimationWorld
        seams.story = game.storyWorld
        seams.menus = game.menuWorld
        seams.trapWorld = game.effectsWorld
        seams.presenter = game.messages
        seams.itemNotices = ItemNoticeTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        seams.effectPresenter = game.effectsWorld
        seams.weather = skyBindings
        seams.music = soundBindings
        return seams
    }

    /// Without a QUST index every `Quest` native fails with
    /// `PapyrusQuestBridgeError.noQuestData`.
    private func quests(
        provider: any WorldRecordsPort,
        worldState: WorldStateStore
    ) -> (any QuestAccess)? {
        provider.questStore.map {
            game.storyWorld.questAccess(
                store: worldState, quests: $0, locations: provider.locationStore
            )
        }
    }
}
