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

/// The cell streamer's NPC movement hooks, so a test can register them on a stand-in.
protocol NPCMovementHooks: AnyObject {
    var onNPCMovementPersist: ((NPCMovementPersistence) -> Void)? { get set }
    var onNPCCellHandoff: ((NPCMovementPersistence) -> Void)? { get set }
    var onNPCLocomotionDrive: ((NPCLocomotionDriveUpdate) -> Void)? { get set }
    var onNPCLanding: ((ReferenceKey, WalkLanding) -> Void)? { get set }
    var npcStandingActors: (() -> [NPCNeighbour])? { get set }
    var npcMovementSpeeds: ((ReferenceKey) -> MovementType.Speeds?)? { get set }
    var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)? { get set }
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
    func requestRebuild(of location: CellSceneLocation)
}

extension CellStreamer: NPCMovementHooks {}

/// Registers the NPC movement hooks of one session.
struct AINPCMovementSteps {
    let hosts: any AIWorldHosts

    private func registerBodyShapes(on streamer: any NPCMovementHooks) {
        guard let bounds = AIRecordReads(game: hosts).bodyBoundsLoader() else { return }
        streamer.npcBodyHalfExtents = { [weak hosts] actor in
            guard let skeleton = hosts?.effectsWorld.race(of: actor)?.maleSkeletonPath else {
                return nil
            }
            _ = bounds.drain()
            return bounds.value(for: ActorGraphCore.projectPath(modelPath: skeleton))
        }
    }

    private func registerMovementTypes(on streamer: any NPCMovementHooks) {
        streamer.npcMovementSpeeds = { [weak hosts] actor in
            hosts.flatMap { AIRecordReads(game: $0).movementSpeeds(of: actor) }
        }
    }

    func register(on streamer: any NPCMovementHooks) {
        let worldState = hosts.worldState
        streamer.onNPCMovementPersist = { [weak hosts] persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
            hosts?.packages.movementSettled(actor: persistence.actor, reason: persistence.reason)
            hosts?.followerCommands
                .movementSettled(actor: persistence.actor, reason: persistence.reason)
        }
        streamer.npcStandingActors = { [weak hosts] in
            hosts.map { AIBumpsAdapter(game: $0).standingActors() } ?? []
        }
        registerBodyShapes(on: streamer)
        registerMovementTypes(on: streamer)
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
