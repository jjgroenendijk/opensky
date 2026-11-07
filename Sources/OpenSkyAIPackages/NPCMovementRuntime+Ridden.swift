// Steering and releasing an actor something else moves: a mount the player rides or
// a dragon in flight (docs/engine/riding.md).

public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyWorldState

extension NPCMovementRuntime {
    /// `triggersAt` answers the trigger volumes at a pose, so a steered actor enters and
    /// leaves them as a walker does: a flying dragon crosses a quest's trigger.
    public mutating func steerRidden(
        _ actor: ReferenceKey, to feet: SIMD3<Float>, yaw: Float, cell: CellSceneLocation?,
        triggersAt: ((PlayerCapsuleState) -> Set<ReferenceKey>)? = nil
    ) {
        guard var hold = ridden[actor] else { return }
        let crossed = hold.move(to: feet, yaw: yaw, cell: cell)
        let edges = triggersAt.map {
            hold.triggerEdges(now: $0(PlayerCapsuleState(capsule: .standard, feetPosition: feet)))
        } ?? []
        ridden[actor] = hold
        for event in edges {
            onTriggerTransition?(event)
        }
        if crossed {
            onPersist?(hold.persistence(reason: .cellHandoff))
        }
    }

    /// Parks a ridden actor where the player left it.
    @discardableResult
    public mutating func releaseRidden(_ actor: ReferenceKey) -> Bool {
        guard let hold = ridden.removeValue(forKey: actor) else { return false }
        parked[actor] = NPCParkedMovement(
            readout: hold.readout, transform: hold.transform, formID: hold.formID,
            scale: hold.scale, drawnPlacement: hold.authoredPlacement
        )
        onPersist?(hold.persistence(reason: .halt))
        return true
    }

    public func isRidden(_ actor: ReferenceKey) -> Bool {
        ridden[actor] != nil
    }

    public func riddenHold(of actor: ReferenceKey) -> NPCRiddenHold? {
        ridden[actor]
    }
}
