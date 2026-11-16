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
import OpenSkyWorldState

/// The cell streamer's NPC movement hooks, so a test can register them on a stand-in.
protocol NPCMovementHooks {
    var onNPCMovementPersist: ((NPCMovementPersistence) -> Void)? { get nonmutating set }
    var onNPCCellHandoff: ((NPCMovementPersistence) -> Void)? { get nonmutating set }
    var onNPCLocomotionDrive: ((NPCLocomotionDriveUpdate) -> Void)? { get nonmutating set }
    var onNPCLanding: ((ReferenceKey, WalkLanding) -> Void)? { get nonmutating set }
    var npcStandingActors: (() -> [NPCNeighbour])? { get nonmutating set }
    var npcMovementSpeeds: ((ReferenceKey) -> ActorMovementSpeeds)? { get nonmutating set }
    var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)? { get nonmutating set }
    var npcHeightScale: ((ReferenceKey) -> Float)? { get nonmutating set }
    associatedtype Rebuilds: NPCCellRebuilds
    /// Held weakly by the cell handoff, so the hooks do not keep the streamer alive.
    var cellStreamer: Rebuilds { get }
}

/// Where an actor is drawn, and the rebuild of a cell it left.
protocol NPCCellRebuilds: AnyObject {
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
    func requestRebuild(of location: CellSceneLocation)
}

extension CellStreamer.ActorSteps: NPCMovementHooks {}

extension CellStreamer: NPCCellRebuilds {}

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
            switch bounds.state(of: ActorGraphCore.projectPath(modelPath: skeleton)) {
            case let .ready(halfExtents): return halfExtents
            case .failed: return LongBodyShape.missingBoundHalfExtents
            case .loading: return nil
            }
        }
    }

    /// An actor's height times its race's height, after its leveled template roll.
    private func registerHeights(on streamer: any NPCMovementHooks) {
        streamer.npcHeightScale = { [weak hosts] actor in
            guard
                let hosts,
                let base = hosts.streamer.residents.residentActorEntry(key: actor)?
                    .placedActor?.base,
                let baselines = hosts.aiRecords?.actorValueBaselines,
                let resolver = baselines.resolver
            else { return 1 }
            let roll = hosts.worldState.leveledRoll(of: actor, base: base, with: baselines.leveling)
            return ActorIdentityRecords(resolver: resolver).heightScale(ofBase: base, roll: roll)
        }
    }

    private func registerMovementTypes(on streamer: any NPCMovementHooks) {
        let settings = hosts.aiRecords.map { MovementSpeedSettings.resolve(store: $0.gameSettings) }
            ?? .vanilla
        streamer.npcMovementSpeeds = { [weak hosts] actor in
            hosts.map { AINPCSpeedReads(hosts: $0, settings: settings).speeds(of: actor) }
                ?? ActorMovementSpeeds()
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
        registerHeights(on: streamer)
        registerMovementTypes(on: streamer)
        // A walker drawn by the cell it left would vanish when that cell unloads, so
        // it moves into the cell it entered, and the cell it left drops it.
        let cells: any NPCCellRebuilds = streamer.cellStreamer
        streamer.onNPCCellHandoff = { [weak hosts, weak cells] persistence in
            guard let cell = persistence.cell, let cells else { return }
            let drawing = cells.cellLocation(of: persistence.actor)
            hosts?.scripts.bridge?.relocate(persistence.actor, to: cell)
            if let drawing, drawing != cell {
                cells.requestRebuild(of: drawing)
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
