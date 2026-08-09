// Transform, draw delta, readout, and persistence projections for one mover
// (issue #423). Split from the state machine for the lint type-size cap.

import simd

extension NPCMover {
    var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: controller.feetPosition,
            rotation: SIMD3(authoredPlacement.rotation.x, authoredPlacement.rotation.y, yaw),
            scale: scale
        )
    }

    var instanceDelta: float4x4 {
        let authored = MatrixMath.placement(
            position: authoredPlacement.position,
            rotation: authoredPlacement.rotation,
            scale: scale
        )
        let current = MatrixMath.placement(
            position: transform.position,
            rotation: transform.rotation,
            scale: scale
        )
        return current * authored.inverse
    }

    var readout: NPCMovementReadout {
        NPCMovementReadout(
            actor: actor,
            state: state,
            feetPosition: controller.feetPosition,
            yaw: yaw,
            waypointIndex: min(waypointIndex, path.waypoints.count),
            waypointCount: path.waypoints.count,
            gait: gait,
            repathCount: repathCount
        )
    }

    func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(
            actor: actor, transform: transform, cell: currentCell, reason: reason
        )
    }
}
