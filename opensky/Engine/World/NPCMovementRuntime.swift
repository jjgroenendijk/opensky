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
    /// How fast an actor may turn, in radians per second. Explicitly
    /// `nonisolated` so the in-place turn (`NPCFacingHold`, issue #427) can
    /// corner at the same rate a mover does without becoming main-actor
    /// isolated itself.
    nonisolated static let maximumYawSpeed: Float = .pi * 2

    var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    var onPersist: ((NPCMovementPersistence) -> Void)?
    var onTriggerTransition: ((TriggerTransitionEvent) -> Void)?
    var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?

    private var movers: [ReferenceKey: NPCMover] = [:]
    private var parked: [ReferenceKey: NPCParkedMovement] = [:]
    /// Actors turning on the spot (issue #427). Not counted against the mover
    /// cap: a turn runs no path, no collision sweep and no repath, so the CPU
    /// budget the cap protects does not apply to it.
    private var facings: [ReferenceKey: NPCFacingHold] = [:]

    var activeMoverCount: Int {
        movers.count
    }

    var activeFacingCount: Int {
        facings.count
    }

    mutating func start(_ start: NPCMoveStart) -> Bool {
        guard movers[start.actor] != nil || movers.count < Self.maximumSimultaneousMovers else {
            return false
        }
        movers[start.actor] = NPCMover(start: start)
        parked.removeValue(forKey: start.actor)
        // Walking somewhere outranks standing still looking at something: the
        // mover owns the yaw from here, and a hold left behind would fight it.
        facings.removeValue(forKey: start.actor)
        return true
    }

    /// Turns one actor on the spot towards a world point and holds it there.
    ///
    /// Takes the actor's mover away first, for the reason a walk takes a hold
    /// away: one owner of a yaw at a time. A hold that is already running is
    /// re-aimed rather than restarted, so a player circling a speaker mid
    /// conversation is followed smoothly instead of snapping on every update.
    mutating func face(_ start: NPCFaceStart) {
        if var hold = facings[start.actor] {
            hold.aim(at: start.target)
            facings[start.actor] = hold
            return
        }
        let settled = parked[start.actor]?.readout ?? movers[start.actor]?.readout
        stop(start.actor)
        facings[start.actor] = NPCFacingHold(
            start: start,
            feetPosition: settled?.feetPosition ?? start.placement.position,
            yaw: settled?.yaw ?? start.placement.rotation.z
        )
    }

    /// Releases a hold, parking the actor on the bearing it reached.
    ///
    /// - Returns: true when there was a hold to release.
    @discardableResult
    mutating func releaseFacing(_ actor: ReferenceKey) -> Bool {
        guard let hold = facings.removeValue(forKey: actor) else { return false }
        parked[actor] = NPCParkedMovement(
            readout: hold.readout, transform: hold.transform
        )
        onPersist?(hold.persistence(reason: .turn))
        return true
    }

    /// Stops one actor where it stands, parking its pose so a later read still
    /// finds it there.
    ///
    /// The combat layer's "hold": an actor that reached weapon range, raised its
    /// guard or gave up should stop walking, and it must stop through the
    /// movement authority rather than by having its request quietly ignored.
    ///
    /// - Returns: true when there was a live mover to stop.
    @discardableResult
    mutating func stop(_ actor: ReferenceKey) -> Bool {
        guard let mover = movers.removeValue(forKey: actor) else { return false }
        parked[actor] = NPCParkedMovement(
            readout: mover.readout(as: .halted), transform: mover.transform
        )
        onPersist?(mover.persistence(reason: .halt))
        // The same still-drive a mover publishes when it finishes on its own,
        // so the gait clip stops rather than looping on a standing actor.
        onDrive?(NPCLocomotionDriveUpdate(
            actor: actor, intent: .still, gait: .walk, yaw: mover.yaw, deltaTime: 0
        ))
        return true
    }

    mutating func advance(by frameTime: Float, world: NPCMovementWorld) {
        for key in facings.keys.sorted() {
            guard var hold = facings[key] else { continue }
            let drive = hold.advance(by: frameTime)
            facings[key] = hold
            onDrive?(drive)
        }
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
        for key in facings.keys.sorted() {
            guard let hold = facings[key] else { continue }
            onPersist?(hold.persistence(reason: .save))
        }
    }

    func transform(for actor: ReferenceKey) -> ReferenceTransformOverride? {
        movers[actor]?.transform ?? facings[actor]?.transform ?? parked[actor]?.transform
    }

    /// What one actor is turning towards, when it is turning.
    func facing(for actor: ReferenceKey) -> NPCFacingHold? {
        facings[actor]
    }

    func readouts() -> [NPCMovementReadout] {
        let live = movers.values.map(\.readout) + facings.values.map(\.readout)
        let held = parked.filter { facings[$0.key] == nil }.values.map(\.readout)
        return (live + held).sorted { $0.actor < $1.actor }
    }

    func instanceDeltas() -> [UInt32: float4x4] {
        let moving = movers.values.map { ($0.formID.rawValue, $0.instanceDelta) }
        let turning = facings.values.map { ($0.formID.rawValue, $0.instanceDelta) }
        return Dictionary(moving + turning) { _, turned in turned }
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
