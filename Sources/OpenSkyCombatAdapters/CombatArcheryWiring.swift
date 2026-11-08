// `CombatWorldAdapter` joins the started session: what `wireArchery` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Connects `CombatWorldAdapter` to the started session.
public struct CombatArcheryWiring {
    public init(_ adapter: CombatWorldAdapter, gameSession: GameSession) {
        let combat = adapter.game.combat
        // The world tick delivers a zero delta on a menu-paused frame, so an
        // arrow hangs in the air behind an open menu.
        let worldTick = gameSession.worldTick
        worldTick.register(.archery) { [weak adapter, weak combat, weak gameSession] delta in
            guard let combat, let gameSession else { return }
            let locomotion = gameSession.locomotion
            combat.isTimeSlowed = gameSession.magicTimeScale < 1
            let commands = combat.advanceArchery(
                events: locomotion.graphEvents.drain(locomotion.archeryEventConsumer),
                intent: locomotion.archeryIntent,
                isPlayerControlled: gameSession.movementMode.isPlayerControlled,
                delta: delta
            )
            gameSession.bowZoomTimeScale = combat.bowZoomTimeScale
            gameSession.bowZoomViewShare = combat.archery?.zoom.viewShare ?? 1
            adapter?.run(commands)
        }
    }
}
