// `CombatWorldAdapter` joins the started session: what `wireMelee` registered.

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
public struct CombatMeleeWiring {
    public init(_ adapter: CombatWorldAdapter, gameSession: GameSession) {
        let combat = adapter.game.combat
        // A frame step, not the audio tick: a swing must resolve with audio off.
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.melee) { [weak adapter, weak combat, weak gameSession] _ in
            guard let combat, let gameSession else { return }
            let locomotion = gameSession.locomotion
            if gameSession.movementMode.isPlayerControlled, let adapter {
                combat.notePlayerSneaking(adapter.game.player.isSneaking)
            }
            if let landing = gameSession.walkController.takeLanding() {
                combat.applyFall(height: landing.height, speed: landing.speed, to: .player)
            }
            for (name, value) in combat.perkGraphFlagChanges() {
                locomotion.write(.bool(value), to: name)
            }
            let commands = combat.advanceMelee(
                events: locomotion.graphEvents.drain(locomotion.meleeEventConsumer),
                intent: locomotion.meleeIntent,
                isPlayerControlled: gameSession.movementMode.isPlayerControlled
            )
            adapter?.run(commands)
        }
    }
}
