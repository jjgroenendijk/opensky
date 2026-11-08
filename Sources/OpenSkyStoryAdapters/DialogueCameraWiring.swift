// `DialogueCameraWiringAdapter` joins the started session: what `wireDialogueCamera` registered.

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

/// Runs after the actor systems in the world tick, so the camera reads
/// this frame's pose.
public struct DialogueCameraWiring {
    public init(_ adapter: DialogueCameraWiringAdapter, gameSession: GameSession) {
        let renderer = gameSession.renderer
        gameSession.worldTick.register(.dialogueCamera) { [weak owner = adapter.owner] delta in
            owner?.cameraWiring.game.dialogueCamera.refreshFocus()
            owner?.cameraWiring.game.faceMorphs
                .tick(now: owner?.cameraWiring.game.renderer?.animationTime ?? 0)
            owner?.cameraWiring.game.headTracking.tick(deltaTime: delta)
        }
        renderer.worldOverlaySources
            .register(identifier: "dialogue-camera") { [weak gameSession] context, list in
                gameSession?.appendDialogueCameraOverlay(context: context, to: &list)
            }
    }
}
