// Fixed-clock NPC capsule movement, path following, bounded recovery, sparse
// persistence, and actor trigger occupancy (issue #423).

import simd

struct NPCMovementWorld {
    let sampleGround: WalkController.GroundSampler
    let collisionQuery: WalkController.CollisionQuery
    let repath: (NavigationPathQuery) -> NavigationPathResult
    let cellAt: (SIMD3<Float>) -> CellSceneLocation?
    let triggersAt: (PlayerCapsuleState) -> Set<ReferenceKey>
}

struct NPCMoveStart {
    let actor: ReferenceKey
    let formID: FormID
    let placement: PlacedReference.Placement
    let scale: Float
    let capsule: PlayerCapsule
    let configuration: PlayerMovementConfiguration
    let path: NavigationPath
}

struct NPCMovementRuntime {
    /// Named crowd cap. Only actors with an active request own a controller.
    static let maximumSimultaneousMovers = 8
    /// CPU slice reserved for all NPC locomotion at the cap in a 16.67 ms
    /// frame. The optimized real-data measurement decides the drive against
    /// this number; item 16.8 consumes it in the complete frame ledger.
    static let maximumCPUTimeMillisecondsAtCap: Double = 2
    static let waypointTolerance: Float = 12
    static let stuckTimeout: Float = 2
    static let progressTolerance: Float = 1
    static let runDistance: Float = 512
    static let maximumYawSpeed: Float = .pi * 2

    var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    var onPersist: ((NPCMovementPersistence) -> Void)?
    var onTriggerTransition: ((TriggerTransitionEvent) -> Void)?
    var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?

    private var movers: [ReferenceKey: NPCMover] = [:]
    private var parked: [ReferenceKey: NPCParkedMovement] = [:]

    var activeMoverCount: Int {
        movers.count
    }

    mutating func start(_ start: NPCMoveStart) -> Bool {
        guard movers[start.actor] != nil || movers.count < Self.maximumSimultaneousMovers else {
            return false
        }
        movers[start.actor] = NPCMover(start: start)
        parked.removeValue(forKey: start.actor)
        return true
    }

    mutating func advance(by frameTime: Float, world: NPCMovementWorld) {
        for key in movers.keys.sorted() {
            guard var mover = movers[key] else { continue }
            let outcome = mover.advance(by: frameTime, world: world)
            publish(outcome.emissions)
            if outcome.isFinished {
                parked[key] = NPCParkedMovement(
                    readout: mover.readout,
                    transform: mover.transform
                )
                movers.removeValue(forKey: key)
            } else {
                movers[key] = mover
            }
        }
    }

    mutating func persistForSave() {
        for key in movers.keys.sorted() {
            guard let mover = movers[key] else { continue }
            onPersist?(mover.persistence(reason: .save))
        }
    }

    func transform(for actor: ReferenceKey) -> ReferenceTransformOverride? {
        movers[actor]?.transform ?? parked[actor]?.transform
    }

    func readouts() -> [NPCMovementReadout] {
        let live = movers.values.map(\.readout)
        return (live + parked.values.map(\.readout)).sorted { $0.actor < $1.actor }
    }

    func instanceDeltas() -> [UInt32: float4x4] {
        Dictionary(uniqueKeysWithValues: movers.values.map { mover in
            (mover.formID.rawValue, mover.instanceDelta)
        })
    }

    private func publish(_ emissions: NPCMoverEmissions) {
        if let drive = emissions.drive {
            onDrive?(drive)
        }
        for persistence in emissions.persistence {
            onPersist?(persistence)
        }
        for event in emissions.triggers {
            onTriggerTransition?(event)
        }
        for door in emissions.doors {
            onDoorCrossing?(door.actor, door.reference)
        }
    }
}

private struct NPCParkedMovement {
    let readout: NPCMovementReadout
    let transform: ReferenceTransformOverride
}

struct NPCMoverEmissions {
    var drive: NPCLocomotionDriveUpdate?
    var persistence: [NPCMovementPersistence] = []
    var triggers: [TriggerTransitionEvent] = []
    var doors: [(actor: ReferenceKey, reference: FormID)] = []
}

struct NPCMoverAdvanceOutcome {
    let emissions: NPCMoverEmissions
    let isFinished: Bool
}
