// The streamer hooks that move NPCs: where a walk persists and settles, the body shapes
// and speeds the walker reads, and the hand-off between cells.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

/// Registers the NPC movement hooks of one session.
struct AINPCMovementSteps {
    let hosts: any AIWorldHosts

    private func registerBodyShapes(stage: SessionStage) {
        let streamer = stage.streamer
        guard let bounds = AIRecordReads(game: hosts).bodyBoundsLoader() else { return }
        streamer.npcBodyHalfExtents = { [weak hosts] actor in
            guard let skeleton = hosts?.effectsWorld.race(of: actor)?.maleSkeletonPath else {
                return nil
            }
            _ = bounds.drain()
            return bounds.value(for: ActorGraphCore.projectPath(modelPath: skeleton))
        }
    }

    private func registerMovementTypes(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.npcMovementSpeeds = { [weak hosts] actor in
            hosts.flatMap { AIRecordReads(game: $0).movementSpeeds(of: actor) }
        }
    }

    func register(stage: SessionStage) {
        let gameSession = stage.gameSession
        let streamer = stage.streamer
        streamer.npcMovementConfiguration = gameSession.locomotion.configuration.forActors
        let worldState = hosts.worldState
        streamer.onNPCMovementPersist = { [weak hosts] persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
            hosts?.packages.movementSettled(actor: persistence.actor, reason: persistence.reason)
            hosts?.followerCommands
                .movementSettled(actor: persistence.actor, reason: persistence.reason)
        }
        gameSession.onPlayerWalkArrived = { [weak hosts] in
            hosts?.packages.movementSettled(actor: .player, reason: .arrival)
        }
        streamer.onNPCPosesChanged = { [weak gameSession] deltas in
            gameSession?.instancePoses.npcDeltas = deltas
        }
        streamer.npcStandingActors = { [weak hosts] in
            hosts.map { AIBumpsAdapter(game: $0).standingActors() } ?? []
        }
        registerBodyShapes(stage: stage)
        registerMovementTypes(stage: stage)
        streamer.npcWaterPushRace = { [weak hosts] actor in
            hosts?.effectsWorld.waterPushRace(of: actor) ?? .normal
        }
        // A walker drawn by the cell it left would vanish when that cell unloads, so
        // it moves into the cell it entered, and the cell it left drops it.
        streamer.onNPCCellHandoff = { [weak hosts, weak streamer] persistence in
            guard let cell = persistence.cell, let streamer else { return }
            let drawing = streamer.cellLocation(of: persistence.actor)
            hosts?.scripts.bridge?.relocate(persistence.actor, to: cell)
            if let drawing, drawing != cell {
                streamer.requestRebuild(of: drawing)
            }
        }
        streamer.onNPCLocomotionDrive = { [weak hosts] update in
            hosts?.actorGraphWorld.drive(update)
            hosts?.npcAnimation.drive(update)
        }
        streamer.onNPCLanding = { [weak hosts] actor, landing in
            hosts?.combat.applyFall(height: landing.height, speed: landing.speed, to: actor)
        }
    }
}
