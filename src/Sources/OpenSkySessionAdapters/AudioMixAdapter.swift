import OpenSkyActorPresentation
public import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AudioMixAdapter` reads from the session.
@MainActor
public protocol AudioMixHost: AnyObject {
    var dialogueMenu: any DialogueMenuPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var menuMode: any MenuModePort { get }
    var runtimeState: any RuntimeStatePort { get }
}

/// Part of `AudioWorldAdapter`, over its own narrow host.
public struct AudioMixAdapter {
    public unowned let owner: AudioWorldAdapter
    public unowned let game: any AudioMixHost
}

extension AudioMixAdapter {
    /// Menu mode means a menu that pauses the world: the dialogue menu leaves voices playing.
    public func soundMixInputs() -> SoundMixInputs {
        let menus = game.menuMode
        return SoundMixInputs(
            menuMode: menus.isWorldSimPaused,
            loading: game.loadingScreens.isCovering,
            dialogue: game.dialogueMenu.isOpen,
            statsMenu: menus.stack.identifiers.contains(SkillsMenuCoordinator.identifier)
        )
    }

    public func isConversationSpeaker(_ speaker: ReferenceKey) -> Bool {
        game.dialogueMenu.isOpen && game.dialogueMenu.speakerOrTarget == speaker
    }

    public func playerConditionsPass(_ conditions: [Condition]) -> Bool {
        var context = game.runtimeState.conditionContext()
        context.subject = .player
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(conditions).isTrue
    }
}
