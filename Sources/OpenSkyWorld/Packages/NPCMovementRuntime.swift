// Fixed-clock NPC capsule movement, path following, bounded recovery, sparse
// persistence, and actor trigger occupancy.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

public struct NPCMovementWorld {
    public let sampleGround: WalkController.GroundSampler
    public let collisionQuery: WalkController.CollisionQuery
    public let repath: (NavigationPathQuery) -> NavigationPathResult
    public let cellAt: (SIMD3<Float>) -> CellSceneLocation?
    public let triggersAt: (PlayerCapsuleState) -> Set<ReferenceKey>
    /// False over an exterior cell whose terrain is not loaded, where a walk would fall.
    public var hasGround: (SIMD2<Float>) -> Bool = { _ in true }
    /// Actors that are not walking, such as the player and standing NPCs, that a mover
    /// steers around. Walking actors come from the runtime itself.
    public var standingActors: () -> [NPCNeighbour] = { [] }
    /// The water surface height over a point, or nil where there is no water.
    public var sampleWater: (SIMD2<Float>) -> Float? = { _ in nil }
}

public struct NPCMoveStart {
    public let actor: ReferenceKey
    public let formID: FormID
    public let placement: PlacedReference.Placement
    public let scale: Float
    public let capsule: PlayerCapsule
    public let configuration: PlayerMovementConfiguration
    public let path: NavigationPath
    /// A marker walk follows the terrain through rocks and logs, as a static-pathing
    /// patrol keeps to its authored line.
    public var ignoresStatics = false
}

public struct NPCMovementRuntime {
    /// Named crowd cap. Only actors with an active request own a controller.
    public static let maximumSimultaneousMovers = ActorMovementLimits.maximumSimultaneousMovers
    /// CPU budget for all NPC locomotion at the cap in a 16.67 ms frame. The real-data
    /// measurement checks the drive against it, and the frame ledger reads it.
    public static let maximumCPUTimeMillisecondsAtCap: Double = 2
    public static let waypointTolerance: Float = 12
    public static let stuckTimeout: Float = 2
    public static let progressTolerance: Float = 1
    public static let runDistance: Float = 512
    /// How fast an actor may turn, in radians per second. `nonisolated`, so the
    /// in-place turn (`NPCFacingHold`) can use it without main-actor isolation.
    nonisolated public static let maximumYawSpeed: Float = .pi * 2

    public var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    public var onPersist: ((NPCMovementPersistence) -> Void)?
    public var onTriggerTransition: ((TriggerTransitionEvent) -> Void)?
    public var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?

    private var movers: [ReferenceKey: NPCMover] = [:]
    private var parked: [ReferenceKey: NPCParkedMovement] = [:]
    /// Actors turning on the spot. Not counted against the mover
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
        movers[start.actor] = NPCMover(
            start: start,
            drawnPlacement: drawnPlacement(of: start.actor)
        )
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
        let drawn = drawnPlacement(of: start.actor)
        stop(start.actor)
        facings[start.actor] = NPCFacingHold(
            start: start,
            feetPosition: settled?.feetPosition ?? start.placement.position,
            yaw: settled?.yaw ?? NPCYawMath.yaw(fromHeading: start.placement.rotation.z),
            drawnPlacement: drawn
        )
    }

    /// Releases a hold, parking the actor on the bearing it reached.
    ///
    /// - Returns: true when there was a hold to release.
    @discardableResult
    public mutating func releaseFacing(_ actor: ReferenceKey) -> Bool {
        guard let hold = facings.removeValue(forKey: actor) else { return false }
        parked[actor] = NPCParkedMovement(
            readout: hold.readout, transform: hold.transform, formID: hold.formID,
            scale: hold.scale, drawnPlacement: hold.authoredPlacement
        )
        onPersist?(hold.persistence(reason: .turn))
        return true
    }

    /// Stops one actor where it stands, keeping its pose. Combat's "hold" goes
    /// through the movement authority instead of letting a request expire.
    /// - Returns: true when there was a live mover to stop.
    @discardableResult
    public mutating func stop(_ actor: ReferenceKey) -> Bool {
        guard let mover = movers.removeValue(forKey: actor) else { return false }
        parked[actor] = NPCParkedMovement(mover, readout: mover.readout(as: .halted))
        onPersist?(mover.persistence(reason: .halt))
        // The same still-drive a mover publishes when it finishes on its own,
        // so the gait clip stops rather than looping on a standing actor.
        onDrive?(NPCLocomotionDriveUpdate(
            actor: actor, intent: .still, gait: .walk
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
        let crowd = neighbourSnapshot(world: world)
        for key in movers.keys.sorted() {
            guard var mover = movers[key] else { continue }
            let near = crowd.filter { $0.key != key }
            let outcome = mover.advance(by: frameTime, world: world, neighbours: near)
            publish(outcome.emissions)
            if outcome.isFinished {
                parked[key] = NPCParkedMovement(mover, readout: mover.readout)
                movers.removeValue(forKey: key)
            } else {
                movers[key] = mover
            }
        }
    }

    /// Every mover where it stood at the start of this step, and the standing actors the
    /// world names. One snapshot, so the order movers step in does not change who avoids whom.
    private func neighbourSnapshot(world: NPCMovementWorld) -> [NPCNeighbour] {
        guard !movers.isEmpty else { return [] }
        let walking = movers.keys.sorted().compactMap { key -> NPCNeighbour? in
            guard let mover = movers[key] else { return nil }
            let feet = mover.controller.feetPosition
            return NPCNeighbour(
                key: key, position: SIMD2(feet.x, feet.y), radius: mover.capsule.radius
            )
        }
        let walkers = Set(movers.keys)
        return walking + world.standingActors().filter { !walkers.contains($0.key) }
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

    /// Where an actor stands: its movement pose, else the pose a cell build draws
    /// from `snapshot`, which is the saved transform when one exists, then the record.
    public func standingTransform(
        of entry: RuntimeReferenceEntry,
        in snapshot: @autoclosure () -> WorldStateSnapshot
    ) -> ReferenceTransformOverride {
        transform(for: entry.key) ?? snapshot().resolvedState(for: entry).transform
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

    /// A parked actor keeps its delta until a cell build bakes its pose in (`bake`), so
    /// it stays drawn where it stopped and its arrival rebuilds nothing.
    public func instanceDeltas() -> [UInt32: float4x4] {
        let resting = parked.values.map { ($0.formID.rawValue, $0.instanceDelta) }
        let moving = movers.values.map { ($0.formID.rawValue, $0.instanceDelta) }
        let turning = facings.values.map { ($0.formID.rawValue, $0.instanceDelta) }
        return Dictionary(resting + moving + turning) { _, later in later }
    }

    /// Records that `actor`'s cell is now built with it at `placement`, so its draw
    /// delta starts there, whether it is parked, walking or turning.
    public mutating func bake(_ actor: ReferenceKey, at placement: PlacedReference.Placement) {
        parked[actor]?.drawnPlacement = placement
        movers[actor]?.authoredPlacement = placement
        facings[actor]?.authoredPlacement = placement
    }

    /// Where the current build draws `actor`, when a mover, hold or rest knows it.
    private func drawnPlacement(of actor: ReferenceKey) -> PlacedReference.Placement? {
        movers[actor]?.authoredPlacement ?? facings[actor]?.authoredPlacement
            ?? parked[actor]?.drawnPlacement
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
    let formID: FormID
    let scale: Float
    /// Where the current cell build draws the actor.
    var drawnPlacement: PlacedReference.Placement

    init(
        readout: NPCMovementReadout,
        transform: ReferenceTransformOverride,
        formID: FormID,
        scale: Float,
        drawnPlacement: PlacedReference.Placement
    ) {
        self.readout = readout
        self.transform = transform
        self.formID = formID
        self.scale = scale
        self.drawnPlacement = drawnPlacement
    }

    init(_ mover: NPCMover, readout: NPCMovementReadout) {
        self.init(
            readout: readout, transform: mover.transform, formID: mover.formID,
            scale: mover.scale, drawnPlacement: mover.authoredPlacement
        )
    }

    var instanceDelta: float4x4 {
        NPCDrawDelta.from(drawn: drawnPlacement, to: transform, scale: scale)
    }
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
