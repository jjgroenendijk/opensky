// Cell-streamer integration for NPC locomotion. Navigation,
// collision, terrain, triggers, and residency already meet here.

public import OpenSkyAIPackages
import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyNavigation
public import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

public struct CellStreamerNPCMovementState {
    var runtime = NPCMovementRuntime()
    public var swimBreadcrumbs = SwimBreadcrumbs()
    var configuration = PlayerMovementConfiguration.synthetic
    var onPersist: ((NPCMovementPersistence) -> Void)?
    var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    var onPosesChanged: (([UInt32: float4x4]) -> Void)?
    var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?
    var onLanding: ((ReferenceKey, WalkLanding) -> Void)?
    /// An actor walked into another cell. Called after its rest write.
    var onCellHandoff: ((NPCMovementPersistence) -> Void)?
    /// The player and the standing actors walkers steer around.
    var standingActors: (() -> [NPCNeighbour])?
    var waterPushRace: ((ReferenceKey) -> WaterPushRace)?
    /// The half size of an actor's skeleton bound (`BBX`), once it has loaded.
    public var bodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)?
    var movementSpeeds: ((ReferenceKey) -> MovementType.Speeds?)?
    /// Rest writes no resident build has drawn yet, oldest first, per actor.
    var unbakedRests: [ReferenceKey: [NPCUnbakedRest]] = [:]
    /// The rest write in progress, so its store mutation rebuilds no cell.
    var recordingRest: NPCMovementPersistence?
    /// Rest writes held while the runtime mutates. A listener that starts the next
    /// move would else write into a runtime copy that the mutation then overwrites.
    public var heldRests: [NPCMovementPersistence]?
    /// Where a vehicle carries each actor riding one this frame.
    public var carried: [ReferenceKey: ReferenceTransformOverride] = [:]
    /// The live pose of each vehicle follower, which its collision moves to.
    public var vehiclePoses: [FormID: float4x4] = [:]
    /// The carriers and riders of every vehicle link. Their own walks do not collide
    /// with a vehicle's collision, so a horse is not blocked by the cart it pulls.
    public var vehicleLinkedActors: Set<ReferenceKey> = []
}

/// One NPC pose written to the store and drawn through a delta until the cell
/// that draws the actor is built from a snapshot that holds it.
struct NPCUnbakedRest {
    let sequence: UInt64
    let placement: PlacedReference.Placement
    let drawingCell: CellSceneLocation
}

extension CellStreamer.ActorSteps {
    public var npcMovement: NPCMovementRuntime {
        get { streamer.npcMovementState.runtime }
        nonmutating set { streamer.npcMovementState.runtime = newValue }
    }

    public var npcMovementConfiguration: PlayerMovementConfiguration {
        get { streamer.npcMovementState.configuration }
        nonmutating set { streamer.npcMovementState.configuration = newValue }
    }

    public var onNPCMovementPersist: ((NPCMovementPersistence) -> Void)? {
        get { streamer.npcMovementState.onPersist }
        nonmutating set { streamer.npcMovementState.onPersist = newValue }
    }

    public var onNPCLocomotionDrive: ((NPCLocomotionDriveUpdate) -> Void)? {
        get { streamer.npcMovementState.onDrive }
        nonmutating set { streamer.npcMovementState.onDrive = newValue }
    }

    public var onNPCPosesChanged: (([UInt32: float4x4]) -> Void)? {
        get { streamer.npcMovementState.onPosesChanged }
        nonmutating set { streamer.npcMovementState.onPosesChanged = newValue }
    }

    public var onNPCDoorCrossing: ((ReferenceKey, FormID) -> Void)? {
        get { streamer.npcMovementState.onDoorCrossing }
        nonmutating set { streamer.npcMovementState.onDoorCrossing = newValue }
    }

    public var onNPCLanding: ((ReferenceKey, WalkLanding) -> Void)? {
        get { streamer.npcMovementState.onLanding }
        nonmutating set { streamer.npcMovementState.onLanding = newValue }
    }

    public var onNPCCellHandoff: ((NPCMovementPersistence) -> Void)? {
        get { streamer.npcMovementState.onCellHandoff }
        nonmutating set { streamer.npcMovementState.onCellHandoff = newValue }
    }

    public var npcStandingActors: (() -> [NPCNeighbour])? {
        get { streamer.npcMovementState.standingActors }
        nonmutating set { streamer.npcMovementState.standingActors = newValue }
    }

    public var npcMovementSpeeds: ((ReferenceKey) -> MovementType.Speeds?)? {
        get { streamer.npcMovementState.movementSpeeds }
        nonmutating set { streamer.npcMovementState.movementSpeeds = newValue }
    }

    public var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)? {
        get { streamer.npcMovementState.bodyHalfExtents }
        nonmutating set { streamer.npcMovementState.bodyHalfExtents = newValue }
    }

    /// The race facts that decide how a current pushes a walking NPC.
    public var npcWaterPushRace: ((ReferenceKey) -> WaterPushRace)? {
        get { streamer.npcMovementState.waterPushRace }
        nonmutating set { streamer.npcMovementState.waterPushRace = newValue }
    }

    /// A `direct` move walks the straight line to `point` on the terrain, without a
    /// navmesh path or static collision. `walkRunBlend` sets a speed from walk to run.
    @discardableResult
    public func moveActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool = false,
        gait: LocomotionGait? = nil, runSlowdown: FollowSettings? = nil,
        walkRunBlend: Float? = nil
    ) -> NPCMoveCommandResult {
        movers.moveActor(
            actor, to: point, direct: direct, gait: gait, runSlowdown: runSlowdown,
            walkRunBlend: walkRunBlend
        )
    }

    /// Stops one actor where it stands, through the movement authority.
    /// - Returns: true when there was a live mover to stop.
    @discardableResult
    public func stopActor(_ actor: ReferenceKey) -> Bool {
        bindNPCMovementCallbacks()
        return movers.holdingRests { npcMovement.stop(actor) }
    }

    /// Moves a still actor's rest to where a vehicle let it off.
    public func restActor(_ actor: ReferenceKey, at transform: ReferenceTransformOverride) {
        npcMovement.rest(actor, at: transform)
    }

    /// Turns a resident actor towards a world point.
    ///
    /// Reads the same placement `moveActor` reads and prefers the movement
    /// runtime's own transform over the authored one, so an actor that walked
    /// somewhere turns where it now stands rather than where its ACHR was
    /// authored.
    @discardableResult
    public func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) -> Bool {
        // A vehicle owns a rider's pose; the rider's seat idle sets where it looks.
        guard
            streamer.npcMovementState.carried[actor] == nil,
            let entry = streamer.residents.referenceEntry(key: actor), entry.placedActor != nil
        else {
            return false
        }
        bindNPCMovementCallbacks()
        let standing = npcMovement.standingTransform(of: entry, in: streamer.stateSource())
        npcMovement.face(NPCFaceStart(
            actor: actor,
            formID: entry.formID,
            placement: standing.placement,
            scale: standing.scale,
            target: point
        ))
        onNPCPosesChanged?(npcMovement.instanceDeltas())
        return true
    }

    /// Moves a standing actor on the ground and turns its heading, as its graph's root
    /// motion does. A walking, turning, carried, or knocked actor keeps its own driver.
    public func moveStandingActor(
        _ actor: ReferenceKey, by displacement: SIMD2<Float>, turning headingTurn: Float
    ) {
        guard npcMovement.facing(for: actor) == nil else { return }
        placeStandingActor(actor) { standing in
            var position = standing.position
            position.x += displacement.x
            position.y += displacement.y
            var rotation = standing.rotation
            rotation.z += headingTurn
            return ReferenceTransformOverride(
                position: position, rotation: rotation, scale: standing.scale
            )
        }
    }

    /// Puts a standing actor at `transform`, as `TetherToHorse` puts the horse ahead of its
    /// cart. A walking, carried, or knocked actor keeps its own driver.
    public func placeStandingActor(
        _ actor: ReferenceKey,
        at transform: ReferenceTransformOverride
    ) {
        placeStandingActor(actor) { _ in transform }
    }

    private func placeStandingActor(
        _ actor: ReferenceKey,
        moved: (ReferenceTransformOverride) -> ReferenceTransformOverride
    ) {
        guard
            streamer.npcMovementState.carried[actor] == nil, !npcMovement.isWalking(actor),
            !npcMovement.isSliding(actor),
            let entry = streamer.residents.referenceEntry(key: actor), entry.placedActor != nil
        else { return }
        bindNPCMovementCallbacks()
        let standing = npcMovement.standingTransform(of: entry, in: streamer.stateSource())
        let target = moved(standing)
        npcMovement.place(
            NPCFaceStart(
                actor: actor, formID: entry.formID, placement: standing.placement,
                scale: standing.scale, target: target.position
            ),
            at: target
        )
        onNPCPosesChanged?(npcMovement.instanceDeltas())
    }

    /// Where the player swims, so a follower can swim after it off the navmesh.
    public func recordPlayerSwim(at feet: SIMD3<Float>, isSwimming: Bool) {
        streamer.npcMovementState.swimBreadcrumbs.record(feet, isSwimming: isSwimming)
    }

    public func isActorWalking(_ actor: ReferenceKey) -> Bool {
        npcMovement.isWalking(actor)
    }

    /// Turns a standing actor to a heading (`angleZ`) and returns the turn still left. A
    /// walking actor turns once it stops, so it reports the whole turn. Nil when it cannot turn.
    public func turnActor(
        _ actor: ReferenceKey, toHeading heading: Float, within tolerance: Float
    ) -> Float? {
        guard
            streamer.npcMovementState.carried[actor] == nil,
            let entry = streamer.residents.referenceEntry(key: actor), entry.placedActor != nil
        else { return nil }
        guard !npcMovement.isWalking(actor) else { return .pi }
        let standing = npcMovement.standingTransform(of: entry, in: streamer.stateSource())
        let remaining = NPCYawMath.shortestTurn(from: standing.rotation.z, to: heading)
        guard abs(remaining) > tolerance else {
            releaseActorFacing(actor)
            return remaining
        }
        let ahead = SIMD3(sin(heading), cos(heading), 0) * 100
        faceActor(actor, towards: standing.position + ahead)
        return remaining
    }

    /// Releases a facing hold, leaving the actor where it now stands.
    /// - Returns: true when there was a hold to release.
    @discardableResult
    public func releaseActorFacing(_ actor: ReferenceKey) -> Bool {
        bindNPCMovementCallbacks()
        let released = npcMovement.releaseFacing(actor)
        if released {
            onNPCPosesChanged?(npcMovement.instanceDeltas())
        }
        return released
    }

    /// Pushes a resident actor at `velocity`, units per second. False when it is not
    /// resident, a vehicle carries it, or the player rides it.
    @discardableResult
    public func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>) -> Bool {
        guard
            streamer.npcMovementState.carried[actor] == nil,
            let entry = streamer.residents.referenceEntry(key: actor), entry.placedActor != nil
        else { return false }
        bindNPCMovementCallbacks()
        let standing = npcMovement.standingTransform(of: entry, in: streamer.stateSource())
        let knocked = npcMovement.knock(
            NPCFaceStart(
                actor: actor, formID: entry.formID, placement: standing.placement,
                scale: standing.scale, target: standing.position
            ),
            velocity: velocity,
            configuration: npcMovementConfiguration
        )
        onNPCPosesChanged?(npcMovement.instanceDeltas())
        return knocked
    }

    /// Takes a resident actor for the player to ride. Nil when it is not resident or a
    /// vehicle carries it.
    public func takeRiddenActor(_ actor: ReferenceKey) -> NPCRiddenHold? {
        guard
            streamer.npcMovementState.carried[actor] == nil,
            let entry = streamer.residents.referenceEntry(key: actor), entry.placedActor != nil
        else { return nil }
        bindNPCMovementCallbacks()
        let standing = npcMovement.standingTransform(of: entry, in: streamer.stateSource())
        let hold = movers.holdingRests {
            npcMovement.takeRidden(NPCFaceStart(
                actor: actor, formID: entry.formID, placement: standing.placement,
                scale: standing.scale, target: standing.position
            ))
        }
        onNPCPosesChanged?(npcMovement.instanceDeltas())
        return hold
    }

    public func steerRiddenActor(_ actor: ReferenceKey, to feet: SIMD3<Float>, yaw: Float) {
        bindNPCMovementCallbacks()
        let cell = movers.navigationCell(at: feet)
        movers.holdingRests {
            npcMovement
                .steerRidden(actor, to: feet, yaw: yaw, cell: cell) { [weak streamer] state in
                    Set(streamer?.triggers.triggerVolumes(intersecting: state)
                        .map(\.reference) ?? [])
                }
        }
        onNPCPosesChanged?(npcMovement.instanceDeltas())
    }

    public func riddenHold(of actor: ReferenceKey) -> NPCRiddenHold? {
        npcMovement.riddenHold(of: actor)
    }

    @discardableResult
    public func releaseRiddenActor(_ actor: ReferenceKey) -> Bool {
        bindNPCMovementCallbacks()
        let released = movers.holdingRests { npcMovement.releaseRidden(actor) }
        onNPCPosesChanged?(npcMovement.instanceDeltas())
        return released
    }

    public func npcMovementReadouts() -> [NPCMovementReadout] {
        npcMovement.readouts()
    }

    /// The actor's live pose: where its vehicle carries it, else where it walks.
    public func npcTransform(for actor: ReferenceKey) -> ReferenceTransformOverride? {
        streamer.npcMovementState.carried[actor] ?? npcMovement.transform(for: actor)
    }

    /// Writes all active actors once immediately before a save snapshot.
    public func persistNPCMovementForSave() {
        movers.holdingRests { npcMovement.persistForSave() }
    }

    func advanceNPCMovement(frameTime: Float) {
        movers.advanceNPCMovement(frameTime: frameTime)
    }

    func noteNPCRestMutation(sequence: UInt64) -> Bool {
        movers.noteNPCRestMutation(sequence: sequence)
    }

    public func bindNPCMovementCallbacks() {
        movers.bindNPCMovementCallbacks()
    }

    var movers: CellNPCMovers {
        CellNPCMovers(streamer: streamer)
    }
}
