// Cell-streamer integration for NPC locomotion (issue #423). Navigation,
// collision, terrain, triggers, and residency already meet here.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

public struct CellStreamerNPCMovementState {
    public var runtime = NPCMovementRuntime()
    public var configuration = PlayerMovementConfiguration.synthetic
    public var onPersist: ((NPCMovementPersistence) -> Void)?
    public var onDrive: ((NPCLocomotionDriveUpdate) -> Void)?
    public var onPosesChanged: (([UInt32: float4x4]) -> Void)?
    public var onDoorCrossing: ((ReferenceKey, FormID) -> Void)?
}

extension CellStreamer: MoveToPointControl {
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

    @discardableResult
    public func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        guard let entry = referenceEntry(key: actor), let placed = entry.placedActor else {
            return .actorNotResident
        }
        let startPosition = npcMovement.transform(for: actor)?.position
            ?? placed.placement.position
        let result = findPath(NavigationPathQuery(
            start: startPosition,
            target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        ))
        guard case let .path(path) = result else {
            guard case let .miss(reason) = result else { return .noPath(.disconnected) }
            return .noPath(reason)
        }
        let placement = PlacedReference.Placement(
            position: startPosition,
            rotation: npcMovement.transform(for: actor)?.rotation ?? placed.placement.rotation
        )
        let started = npcMovement.start(NPCMoveStart(
            actor: actor,
            formID: entry.formID,
            placement: placement,
            scale: placed.scale,
            capsule: .standard,
            configuration: npcMovementConfiguration,
            path: path
        ))
        return started ? .started : .moverCapReached
    }

    @discardableResult
    public func stopActor(_ actor: ReferenceKey) -> Bool {
        bindNPCMovementCallbacks()
        return npcMovement.stop(actor)
    }

    /// Turns a resident actor towards a world point (issue #427).
    ///
    /// Reads the same placement `moveActor` reads and prefers the movement
    /// runtime's own transform over the authored one, so an actor that walked
    /// somewhere turns where it now stands rather than where its ACHR was
    /// authored.
    @discardableResult
    public func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) -> Bool {
        guard let entry = referenceEntry(key: actor), let placed = entry.placedActor else {
            return false
        }
        bindNPCMovementCallbacks()
        let override = npcMovement.transform(for: actor)
        npcMovement.face(NPCFaceStart(
            actor: actor,
            formID: entry.formID,
            placement: PlacedReference.Placement(
                position: override?.position ?? placed.placement.position,
                rotation: override?.rotation ?? placed.placement.rotation
            ),
            scale: placed.scale,
            target: point
        ))
        onNPCPosesChanged?(npcMovement.instanceDeltas())
        return true
    }

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
        npcMovement.persistForSave()
    }

    public func advanceNPCMovement(frameTime: Float) {
        bindNPCMovementCallbacks()
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
            }
        ))
        onNPCPosesChanged?(npcMovement.instanceDeltas())
    }

    private func navigationCell(at position: SIMD3<Float>) -> CellSceneLocation? {
        reconcileNavigation()
        return navigationState.graph.cell(at: position)
    }

    public func bindNPCMovementCallbacks() {
        npcMovement.onDrive = { [weak self] update in
            self?.onNPCLocomotionDrive?(update)
        }
        npcMovement.onPersist = { [weak self] persistence in
            self?.onNPCMovementPersist?(persistence)
        }
        npcMovement.onTriggerTransition = { [weak self] event in
            self?.onTriggerTransition(event)
        }
        npcMovement.onDoorCrossing = { [weak self] actor, door in
            self?.onNPCDoorCrossing?(actor, door)
        }
    }
}
