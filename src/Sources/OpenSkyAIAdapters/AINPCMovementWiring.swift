// `AIWorldAdapter` joins the started session: what `wireNPCMovement` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
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

/// Connects `AIWorldAdapter` to the started session.
public struct AINPCMovementWiring {
    public init(_ adapter: AIWorldAdapter, gameSession: GameSession, streamer: CellStreamer) {
        streamer.npcMovementConfiguration = gameSession.locomotion.configuration.forActors
        let worldState = adapter.game.worldState
        let packages = adapter.game.packages
        let commands = adapter.game.followerCommands
        streamer.onNPCMovementPersist = { [weak packages, weak commands] persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
            packages?.movementSettled(actor: persistence.actor, reason: persistence.reason)
            commands?.movementSettled(actor: persistence.actor, reason: persistence.reason)
        }
        gameSession.onPlayerWalkArrived = { [weak packages] in
            packages?.movementSettled(actor: .player, reason: .arrival)
        }
        streamer.onNPCPosesChanged = { [weak gameSession] deltas in
            gameSession?.instancePoses.npcDeltas = deltas
        }
        streamer.npcStandingActors = { [weak adapter] in adapter?.bumps.standingActors() ?? [] }
        _ = AIBodyShapesWiring(adapter, streamer: streamer)
        _ = AIMovementTypesWiring(adapter, streamer: streamer)
        streamer.npcWaterPushRace = { [weak game = adapter.game] actor in
            game?.effectsWorld.waterPushRace(of: actor) ?? .normal
        }
        gameSession.locomotion.waterPushRace = adapter.game.effectsWorld.waterPushRace(of: .player)
        // A walker drawn by the cell it left would vanish when that cell unloads, so
        // it moves into the cell it entered, and the cell it left drops it.
        streamer.onNPCCellHandoff = { [weak game = adapter.game, weak streamer] persistence in
            guard let cell = persistence.cell, let streamer else { return }
            let drawing = streamer.cellLocation(of: persistence.actor)
            game?.scripts.bridge?.relocate(persistence.actor, to: cell)
            if let drawing, drawing != cell {
                streamer.requestRebuild(of: drawing)
            }
        }
        let animation = adapter.game.npcAnimation
        let graphs = adapter.game.actorGraphWorld
        streamer.onNPCLocomotionDrive = { [weak animation, weak graphs] update in
            graphs?.drive(update)
            animation?.drive(update)
        }
        streamer.onNPCLanding = { [weak combat = adapter.game.combat] actor, landing in
            combat?.applyFall(height: landing.height, speed: landing.speed, to: actor)
        }
    }
}
