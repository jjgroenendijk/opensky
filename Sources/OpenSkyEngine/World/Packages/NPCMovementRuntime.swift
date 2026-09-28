// Fixed-clock NPC capsule movement, path following, bounded recovery, sparse
// persistence, and actor trigger occupancy (issue #423).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

public struct NPCMovementWorld {
    public let sampleGround: WalkController.GroundSampler
    public let collisionQuery: WalkController.CollisionQuery
    public let repath: (NavigationPathQuery) -> NavigationPathResult
    public let cellAt: (SIMD3<Float>) -> CellSceneLocation?
    public let triggersAt: (PlayerCapsuleState) -> Set<ReferenceKey>
}

public struct NPCMoveStart {
    public let actor: ReferenceKey
    public let formID: FormID
    public let placement: PlacedReference.Placement
    public let scale: Float
    public let capsule: PlayerCapsule
    public let configuration: PlayerMovementConfiguration
    public let path: NavigationPath
}

public struct NPCMovementRuntime {
    /// Named crowd cap. Only actors with an active request own a controller.
    public static let maximumSimultaneousMovers = 8
    /// CPU slice reserved for all NPC locomotion at the cap in a 16.67 ms
    /// frame. The optimized real-data measurement decides the drive against
    /// this number; item 16.8 consumes it in the complete frame ledger.
    public static let maximumCPUTimeMillisecondsAtCap: Double = 2
    public static let waypointTolerance: Float = 12
    public static let stuckTimeout: Float = 2
    public static let progressTolerance: Float = 1
    public static let runDistance: Float = 512
    /// How fast an actor may turn, in radians per second. Explicitly
    /// `nonisolated` so the in-place turn (`NPCFacingHold`, issue #427) can
    /// corner at the same rate a mover does without becoming main-actor
    /// isolated itself.
    nonisolated public static let maximumYawSpeed: Float = .pi * 2

    public var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    public var onPersist: ((NPCMovementPersistence) -> Void)?
    public var onTriggerTransition: ((TriggerTransitionEvent) -> Void)?
    public var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?

    private var movers: [ReferenceKey: NPCMover] = [:]
    private var parked: [ReferenceKey: NPCParkedMovement] = [:]
    /// Actors turning on the spot (issue #427). Not counted against the mover
    /// cap: a turn runs no path, no collision sweep and no repath, so the CPU
    /// budget the cap protects does not apply to it.
    private var facings: [ReferenceKey: NPCFacingHold] = [:]

    public var activeMoverCount: Int {
        movers.count
    }

    public var activeFacingCount: Int {
        facings.count
    }

    public mutating func start(_ start: NPCMoveStart) -> Bool {
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
    public mutating func face(_ start: NPCFaceStart) {
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
    public mutating func releaseFacing(_ actor: ReferenceKey) -> Bool {
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
    public mutating func stop(_ actor: ReferenceKey) -> Bool {
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

    public mutating func advance(by frameTime: Float, world: NPCMovementWorld) {
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

    public mutating func persistForSave() {
        for key in movers.keys.sorted() {
            guard let mover = movers[key] else { continue }
            onPersist?(mover.persistence(reason: .save))
        }
        for key in facings.keys.sorted() {
            guard let hold = facings[key] else { continue }
            onPersist?(hold.persistence(reason: .save))
        }
    }

    public func transform(for actor: ReferenceKey) -> ReferenceTransformOverride? {
        movers[actor]?.transform ?? facings[actor]?.transform ?? parked[actor]?.transform
    }

    /// What one actor is turning towards, when it is turning.
    public func facing(for actor: ReferenceKey) -> NPCFacingHold? {
        facings[actor]
    }

    public func readouts() -> [NPCMovementReadout] {
        let live = movers.values.map(\.readout) + facings.values.map(\.readout)
        let held = parked.filter { facings[$0.key] == nil }.values.map(\.readout)
        return (live + held).sorted { $0.actor < $1.actor }
    }

    public func instanceDeltas() -> [UInt32: float4x4] {
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

public struct NPCMoverEmissions {
    public var drive: NPCLocomotionDriveUpdate?
    public var persistence: [NPCMovementPersistence] = []
    public var triggers: [TriggerTransitionEvent] = []
    public var doors: [(actor: ReferenceKey, reference: FormID)] = []
}

public struct NPCMoverAdvanceOutcome {
    public let emissions: NPCMoverEmissions
    public let isFinished: Bool
}
