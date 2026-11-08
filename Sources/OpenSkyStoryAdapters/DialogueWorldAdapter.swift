// App side of `DialogueCoordinator`: wires the dialogue index and the Talk
// seams onto the streamer, and answers `DialogueWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyDiagnostics
public import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
public import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DialogueWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol DialogueWorldHost: AnyObject {
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
    public unowned let game: any DialogueWorldHost
    /// `VTCK` by actor base. A template walk per actor per condition context costs too much.
    public var voiceTypesByRoll: [LeveledActorRollKey: FormID?] = [:]

    public let cameraWiringHost: any DialogueCameraWiringHost
    public let speakersHost: any DialogueSpeakersHost
    public let outcomesHost: any DialogueOutcomesHost

    public var cameraWiring: DialogueCameraWiringAdapter {
        DialogueCameraWiringAdapter(
            owner: self,
            game: cameraWiringHost
        )
    }

    public var speakers: DialogueSpeakersAdapter {
        DialogueSpeakersAdapter(owner: self, game: speakersHost)
    }

    public var outcomes: DialogueOutcomesAdapter {
        DialogueOutcomesAdapter(owner: self, game: outcomesHost)
    }

    public init(game: some DialogueWorldHost & DialogueCameraWiringHost & DialogueSpeakersHost &
        DialogueOutcomesHost)
    {
        cameraWiringHost = game
        speakersHost = game
        outcomesHost = game
        self.game = game
    }

    /// Hostility and death decide who is worth talking to, so the candidate
    /// list is built here, not in streaming.
    public func wireDialogue(streamer: CellStreamer) {
        streamer.talk.candidateSource = { [weak self] ray in
            self?.speakers.talkCandidates(along: ray) ?? []
        }
        // Activating a living actor while sneaking opens its pockets instead of a talk.
        streamer.talk.activations.register(.dialogue) { [weak self] event in
            guard let game = self?.game else { return }
            if game.mountWorld.mountOnActivation(event.speaker) {
                return
            }
            if game.player.isSneaking, game.containerMenu.openPickpocket(of: event.speaker) {
                return
            }
            game.dialogueMenu.begin(with: event.speaker)
        }
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

    public var conditionRegistry: ConditionFunctionRegistry {
        .standard
    }

    public var fragments: (any DialogueFragmentDispatching)? {
        game.scripts.bridge
    }

    public func loadStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }

    public func spokeToPlayer(_ speaker: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: speaker) {
            $0.setFlag(ScriptedStateName.talkedToPlayer, true)
        }
    }
}

extension DialogueWorldAdapter: DialogueWorldPort {}
