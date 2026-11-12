import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditionFunctions
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateLiveSeamsAdapter` reads from the session.
@MainActor
public protocol RuntimeStateLiveSeamsHost: AnyObject, SendableMetatype {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var dialogue: any DialoguePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var menuMode: any MenuModePort { get }
    var packages: any PackagePort { get }
    var scenes: any ScenePort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateLiveSeamsAdapter {
    public let game: any RuntimeStateLiveSeamsHost
    public let inventoryFacts: RuntimeStateInventoryFactsAdapter
    public let referenceMotion: RuntimeStateReferenceMotionAdapter
}

extension RuntimeStateLiveSeamsAdapter {
    public func addLiveSeams(to context: inout ConditionContext) {
        context[resolution: ScriptVariableResolution.self] = game.scripts.runtime?
            .scriptVariableResolution() ?? .empty
        context.scriptedState = game.scripts.bridge?.scriptedStateResolution() ?? .empty
        context.scenes = game.scenes.conditionResolution(aliases: context.aliases)
        context.weather = weatherResolution()
        context.furniture = game.idleWorld.idles.furnitureResolution
        context[resolution: GraphVariableResolution.self] = game.actorGraphWorld
            .graphVariableResolution()
        let warnings = game.packages.trespassWarnings
        if !warnings.isEmpty {
            context.crime.situation?.trespassWarnings = warnings
        }
        if let inventory = inventoryFacts.inventoryResolution(context: context) {
            context.inventory = inventory
        }
        context[resolution: ReferenceConditionResolution.self] = referenceMotion
            .referenceFacts(of: context.references)
        context.motion = referenceMotion.motionResolution(references: context.references)
        context[resolution: PlaceConditionResolution.self] = referenceMotion
            .placeResolution(references: context.references)
        referenceMotion.addMountSeams(to: &context)
        context.menus = MenuConditionResolution(
            isMenuOpen: game.menuMode.topMenu != nil,
            isLoading: game.menuMode.topMenu == MenuIdentifier.loadingMenu
        )
        context.dialogue = DialogueResolution(
            speakerInDialogue: game.dialogue.conversationSpeaker, line: game.dialogue.spokenLine
        )
        context.packages = game.packages.runtime?.conditionResolution { location, actor in
            game.aiWorld.isWithin(location, actor: actor)
        } ?? .empty
    }

    private func weatherResolution() -> WeatherConditionResolution {
        guard
            let weather = game.gameSession?.weather,
            let current = weather.currentWeatherID
        else { return .empty }
        return WeatherConditionResolution(
            weather: current,
            precipitation: weather.store.weather(current)?.data?.precipitation ?? .none
        )
    }
}
