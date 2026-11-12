// `CombatWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension CombatWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some CombatWorldHosts,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        frames.registerCombatMelee(stage: stage)
        frames.registerCombatArchery(stage: stage)
        frames.registerCombatLoop(stage: stage)
    }
}

extension CombatFrameSteps {
    func registerCombatMelee(stage: SessionStage) {
        let gameSession = stage.gameSession
        // A frame step, not the audio tick: a swing must resolve with audio off.
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.melee) { [weak self, weak gameSession] _ in
            guard let self, let gameSession else { return }
            let combat = game.combat
            let locomotion = gameSession.locomotion
            if gameSession.movementMode.isPlayerControlled {
                combat.notePlayerSneaking(game.player.isSneaking)
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
            outcomes.run(commands)
        }
    }

    func registerCombatArchery(stage: SessionStage) {
        let gameSession = stage.gameSession
        // The world tick delivers a zero delta on a menu-paused frame, so an
        // arrow hangs in the air behind an open menu.
        let worldTick = gameSession.worldTick
        worldTick.register(.archery) { [weak self, weak gameSession] delta in
            guard let self, let gameSession else { return }
            let combat = game.combat
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
            outcomes.run(commands)
        }
    }

    func registerCombatLoop(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.combatLoop) { [weak self] delta in
            guard let self else { return }
            outcomes.run(game.combat.advanceLoop(by: delta))
            updateNPCDrawStates()
        }
    }
}
