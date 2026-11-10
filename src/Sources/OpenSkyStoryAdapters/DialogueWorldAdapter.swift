// App side of `DialogueCoordinator`: wires the dialogue index and the Talk
// seams onto the streamer, and answers `DialogueWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
public import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DialogueWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol DialogueWorldHost: AnyObject, SendableMetatype {
    var containerMenu: any ContainerMenuPort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var localizedStringsLoader: (() -> LocalizedStrings)? { get }
    var mountWorld: any MountWorldPort { get }
    var player: any PlayerPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var scripts: any ScriptPort { get }
}

/// Answers `DialogueWorld` from the session systems `game` owns.
public final class DialogueWorldAdapter {
    public let game: any DialogueWorldHost
    let voiceTypes = DialogueVoiceTypeCache()

    public let cameraFocusHost: any DialogueCameraFocusHost
    public let speakersHost: any DialogueSpeakersHost
    public let outcomesHost: any DialogueOutcomesHost

    var cameraFocus: DialogueCameraFocusAdapter {
        DialogueCameraFocusAdapter(game: cameraFocusHost)
    }

    public var speakers: DialogueSpeakersAdapter {
        DialogueSpeakersAdapter(game: speakersHost, voiceTypes: voiceTypes)
    }

    public var outcomes: DialogueOutcomesAdapter {
        DialogueOutcomesAdapter(game: outcomesHost)
    }

    public init(game: some DialogueWorldHost & DialogueCameraFocusHost & DialogueSpeakersHost &
        DialogueOutcomesHost)
    {
        cameraFocusHost = game
        speakersHost = game
        outcomesHost = game
        self.game = game
    }
}

extension DialogueWorldAdapter: DialogueWorld {
    public func questStates() -> QuestResolution? {
        game.scripts.bridge?.questRuntime?.resolution()
    }

    public func questAliases() -> QuestAliasResolution {
        game.scripts.bridge?.questRuntime?.aliasResolution() ?? .empty
    }

    public func conditionContext() -> ConditionContext {
        var context = game.runtimeState.conditionContext()
        context.dialogue = DialogueResolution(
            voiceTypes: residentVoiceTypes(),
            speakerInDialogue: context.dialogue.speakerInDialogue,
            line: context.dialogue.line
        )
        context.speechChecks = outcomes.speechCheckResolution()
        return context
    }

    public var fragments: (any DialogueFragmentDispatching)? {
        game.scripts.bridge
    }

    public func loadStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }
}

extension DialogueWorldAdapter: DialogueWorldPort {}
