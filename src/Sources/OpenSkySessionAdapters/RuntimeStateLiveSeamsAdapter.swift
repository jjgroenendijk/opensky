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
    /// Every seam is built when a condition first reads it, so a context that tests a
    /// quest stage reads no script, inventory, or package state.
    public func addLiveSeams(to context: inout ConditionContext) {
        let references = context.references
        let aliases = context.aliases
        context.setDeferred { [game] in
            game.scripts.runtime?.scriptVariableResolution() ?? ScriptVariableResolution.empty
        }
        context.setDeferred { [game] in
            game.scripts.bridge?.scriptedStateResolution() ?? ScriptedStateConditionResolution.empty
        }
        context.setDeferred { [game] in game.scenes.conditionResolution(aliases: aliases) }
        context.setDeferred { weatherResolution() }
        context.setDeferred { [game] in game.idleWorld.idles.furnitureResolution }
        context.setDeferred { [game] in game.actorGraphWorld.graphVariableResolution() }
        context.transform(CrimeConditionResolution.self) { [game] crime in
            let warnings = game.packages.trespassWarnings
            guard !warnings.isEmpty else { return crime }
            var crime = crime
            crime.situation?.trespassWarnings = warnings
            return crime
        }
        let magicSource = context
        context.setDeferred { [inventoryFacts] in
            inventoryFacts.inventoryResolution(context: magicSource) ?? .empty
        }
        context.setDeferred { [referenceMotion] in referenceMotion.referenceFacts(of: references) }
        context.setDeferred { [referenceMotion] in
            referenceMotion.motionResolution(references: references)
        }
        context.setDeferred { [referenceMotion] in
            referenceMotion.placeResolution(references: references)
        }
        referenceMotion.addMountSeams(to: &context)
        context.setDeferred { [game] in
            MenuConditionResolution(
                isMenuOpen: game.menuMode.topMenu != nil,
                isLoading: game.menuMode.topMenu == MenuIdentifier.loadingMenu
            )
        }
        context.setDeferred { [game] in
            var resolution = DialogueResolution(
                speakerInDialogue: game.dialogue.conversationSpeaker,
                line: game.dialogue.spokenLine
            )
            resolution.talkingActors = game.dialogue.dialogueMode.talkingActors
            return resolution
        }
        context.setDeferred { [game] in
            game.packages.runtime?.conditionResolution { location, actor in
                game.aiWorld.isWithin(location, actor: actor)
            } ?? PackageConditionResolution.empty
        }
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
