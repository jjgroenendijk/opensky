// `DialogueWorldAdapter` joins the started session: what `wireDialogue` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Hostility and death decide who is worth talking to, so the candidate
/// list is built here, not in streaming.
public struct DialogueWiring {
    public init(_ adapter: DialogueWorldAdapter, streamer: CellStreamer) {
        streamer.talk.candidateSource = { [weak adapter] ray in
            adapter?.speakers.talkCandidates(along: ray) ?? []
        }
        // Activating a living actor while sneaking opens its pockets instead of a talk.
        streamer.talk.activations.register(.dialogue) { [weak adapter] event in
            guard let game = adapter?.game else { return }
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
