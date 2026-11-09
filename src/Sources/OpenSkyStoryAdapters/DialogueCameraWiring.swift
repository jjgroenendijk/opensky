// `DialogueCameraWiringAdapter` joins the started session: what `wireDialogueCamera` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
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
        gameSession.worldTick.register(.dialogueCamera) { [weak game = adapter.game] delta in
            game?.dialogueCamera.refreshFocus()
            game?.faceMorphs.tick(now: game?.renderer?.animationTime ?? 0)
            game?.headTracking.tick(deltaTime: delta)
        }
        renderer.worldOverlaySources
            .register(identifier: "dialogue-camera") { [weak gameSession] context, list in
                gameSession?.appendDialogueCameraOverlay(context: context, to: &list)
            }
    }
}
