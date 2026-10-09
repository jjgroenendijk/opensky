// Cell-streamer integration for NPC locomotion. Navigation,
// collision, terrain, triggers, and residency already meet here.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

public struct CellStreamerNPCMovementState {
    public var runtime = NPCMovementRuntime()
    public var configuration = PlayerMovementConfiguration.synthetic
    public var onPersist: ((NPCMovementPersistence) -> Void)?
    public var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    public var onPosesChanged: (([UInt32: float4x4]) -> Void)?
    public var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?
    /// An actor walked into another cell. Called after its rest write.
    public var onCellHandoff: ((NPCMovementPersistence) -> Void)?
    /// Rest writes no resident build has drawn yet, oldest first, per actor.
    public var unbakedRests: [ReferenceKey: [NPCUnbakedRest]] = [:]
    /// The rest write in progress, so its store mutation rebuilds no cell.
    public var recordingRest: NPCMovementPersistence?
    /// Rest writes held while the runtime mutates. A listener that starts the next
    /// move would else write into a runtime copy that the mutation then overwrites.
    public var heldRests: [NPCMovementPersistence]?
}

/// One NPC pose written to the store and drawn through a delta until the cell
/// that draws the actor is built from a snapshot that holds it.
public struct NPCUnbakedRest {
    public let sequence: UInt64
    public let placement: PlacedReference.Placement
    public let drawingCell: CellSceneLocation
}

extension CellStreamer {
    public var npcMovement: NPCMovementRuntime {
        get { npcMovementState.runtime }
        set { npcMovementState.runtime = newValue }
    }

    public var npcMovementConfiguration: PlayerMovementConfiguration {
        get { npcMovementState.configuration }
        set { npcMovementState.configuration = newValue }
    }

    public var onNPCMovementPersist: ((NPCMovementPersistence) -> Void)? {
        get { npcMovementState.onPersist }
        set { npcMovementState.onPersist = newValue }
    }

    public var onNPCLocomotionDrive: ((NPCLocomotionDriveUpdate) -> Void)? {
        get { npcMovementState.onDrive }
        set { npcMovementState.onDrive = newValue }
    }

    public var onNPCPosesChanged: (([UInt32: float4x4]) -> Void)? {
        get { npcMovementState.onPosesChanged }
        set { npcMovementState.onPosesChanged = newValue }
    }

    public var onNPCDoorCrossing: ((ReferenceKey, FormID) -> Void)? {
        get { npcMovementState.onDoorCrossing }
        set { npcMovementState.onDoorCrossing = newValue }
    }

    public var onNPCCellHandoff: ((NPCMovementPersistence) -> Void)? {
        get { npcMovementState.onCellHandoff }
        set { npcMovementState.onCellHandoff = newValue }
    }

    /// A `direct` move walks the straight line to `point` on the terrain, without a
    /// navmesh path or static collision.
    @discardableResult
    public func moveActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool = false
    ) -> NPCMoveCommandResult {
        guard let entry = referenceEntry(key: actor), entry.placedActor != nil else {
            return .actorNotResident
        }
        let standing = npcMovement.standingTransform(of: entry, in: stateSource())
        let result = direct ? .path(.straight(to: point)) : findPath(NavigationPathQuery(
            start: standing.position,
            target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        ))
        guard case let .path(path) = result else {
            guard case let .miss(reason) = result else { return .noPath(.disconnected) }
            return .noPath(reason)
        }
        let started = npcMovement.start(NPCMoveStart(
            actor: actor,
            formID: entry.formID,
            placement: standing.placement,
            scale: standing.scale,
            capsule: .standard,
            configuration: npcMovementConfiguration,
            path: path,
            ignoresStatics: direct
        ))
        return started ? .started : .moverCapReached
    }

    /// Stops one actor where it stands, through the movement authority.
    /// - Returns: true when there was a live mover to stop.
    @discardableResult
    public func stopActor(_ actor: ReferenceKey) -> Bool {
        bindNPCMovementCallbacks()
        return holdingRests { npcMovement.stop(actor) }
    }

    /// Turns a resident actor towards a world point.
    ///
    /// Reads the same placement `moveActor` reads and prefers the movement
    /// runtime's own transform over the authored one, so an actor that walked
    /// somewhere turns where it now stands rather than where its ACHR was
    /// authored.
    @discardableResult
    public func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) -> Bool {
        guard let entry = referenceEntry(key: actor), entry.placedActor != nil else {
            return false
        }
        bindNPCMovementCallbacks()
        let standing = npcMovement.standingTransform(of: entry, in: stateSource())
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

    /// What one actor is turning towards, for the gate readout.
    public func npcFacing(for actor: ReferenceKey) -> NPCFacingHold? {
        npcMovement.facing(for: actor)
    }

    public func npcMovementReadouts() -> [NPCMovementReadout] {
        npcMovement.readouts()
    }

    public func npcTransform(for actor: ReferenceKey) -> ReferenceTransformOverride? {
        npcMovement.transform(for: actor)
    }

    /// Writes all active actors once immediately before a save snapshot.
    public func persistNPCMovementForSave() {
        holdingRests { npcMovement.persistForSave() }
    }

    public func advanceNPCMovement(frameTime: Float) {
        bindNPCMovementCallbacks()
        holdingRests { advanceMovers(frameTime: frameTime) }
        bakeBuiltRests()
        onNPCPosesChanged?(npcMovement.instanceDeltas())
    }

    /// Runs `body`, then delivers the rest writes it emitted, once the runtime holds
    /// its result.
    private func holdingRests<T>(_ body: () -> T) -> T {
        npcMovementState.heldRests = []
        let result = body()
        let rests = npcMovementState.heldRests ?? []
        npcMovementState.heldRests = nil
        rests.forEach(deliverRest)
        return result
    }

    private func advanceMovers(frameTime: Float) {
        npcMovement.advance(by: frameTime, world: NPCMovementWorld(
            sampleGround: { [weak self] position in self?.sampleTerrain(at: position) },
            collisionQuery: { [weak self] bounds in
                self?.collisionCandidates(overlapping: bounds) ?? []
            },
            repath: { [weak self] query in
                self?.findPath(query) ?? .miss(.disconnected)
            },
            cellAt: { [weak self] position in
                self?.navigationCell(at: position)
            },
            triggersAt: { [weak self] state in
                Set(self?.triggerVolumes(intersecting: state).map(\.reference) ?? [])
            },
            hasGround: { [weak self] position in
                self?.interiorScene != nil || self?.sampleTerrain(at: position) != nil
            }
        ))
    }

    /// Called from `noteStateMutation` while a rest write is in progress. The actor
    /// already draws at that pose, so the write rebuilds nothing; a later build of
    /// its cell bakes it in. Returns false when no rest write is in progress.
    func noteNPCRestMutation(sequence: UInt64) -> Bool {
        guard let rest = npcMovementState.recordingRest else { return false }
        if let cell = cellLocation(of: rest.actor) {
            npcMovementState.unbakedRests[rest.actor, default: []].append(NPCUnbakedRest(
                sequence: sequence, placement: rest.transform.placement, drawingCell: cell
            ))
        }
        return true
    }

    /// Moves each actor's draw base to the newest rest its cell's resident build holds.
    private func bakeBuiltRests() {
        for actor in npcMovementState.unbakedRests.keys.sorted() {
            guard
                var rests = npcMovementState.unbakedRests[actor],
                let cell = rests.last?.drawingCell,
                let built = residentStateSequence(at: cell),
                let baked = rests.lastIndex(where: { $0.sequence <= built })
            else { continue }
            npcMovement.bake(actor, at: rests[baked].placement)
            rests.removeSubrange(...baked)
            npcMovementState.unbakedRests[actor] = rests.isEmpty ? nil : rests
        }
    }

    private func residentStateSequence(at location: CellSceneLocation) -> UInt64? {
        switch location {
        case let .exterior(coordinate):
            return composition.cells[coordinate]?.stateSequence
        case .interior:
            guard let interiorScene, interiorScene.location == location else { return nil }
            return interiorScene.stateSequence
        }
    }

    private func navigationCell(at position: SIMD3<Float>) -> CellSceneLocation? {
        reconcileNavigation()
        return navigationState.graph.cell(at: position)
    }

    private func deliverRest(_ persistence: NPCMovementPersistence) {
        npcMovementState.recordingRest = persistence
        onNPCMovementPersist?(persistence)
        npcMovementState.recordingRest = nil
        if persistence.reason == .cellHandoff {
            onNPCCellHandoff?(persistence)
        }
    }

    public func bindNPCMovementCallbacks() {
        npcMovement.onDrive = { [weak self] update in
            self?.onNPCLocomotionDrive?(update)
        }
        npcMovement.onPersist = { [weak self] persistence in
            guard let self else { return }
            if npcMovementState.heldRests != nil {
                npcMovementState.heldRests?.append(persistence)
            } else {
                deliverRest(persistence)
            }
        }
        npcMovement.onTriggerTransition = { [weak self] event in
            self?.onTriggerTransition(event)
        }
        npcMovement.onDoorCrossing = { [weak self] actor, door in
            self?.onNPCDoorCrossing?(actor, door)
        }
    }
}
