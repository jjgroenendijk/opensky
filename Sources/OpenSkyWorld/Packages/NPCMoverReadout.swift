// Transform, draw delta, readout and persistence projections for one mover.

import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

extension NPCMover {
    public var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: controller.feetPosition,
            rotation: SIMD3(authoredPlacement.rotation.x, authoredPlacement.rotation.y, yaw),
            scale: scale
        )
    }

    public var instanceDelta: float4x4 {
        NPCDrawDelta.from(drawn: authoredPlacement, to: transform, scale: scale)
    }

    public var readout: NPCMovementReadout {
        readout(as: state)
    }

    /// The same readout with the state overridden, for a mover the crowd
    /// registry stopped rather than one that ran to its own conclusion.
    public func readout(as state: NPCMovementState) -> NPCMovementReadout {
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

    public func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(
            actor: actor, transform: transform, cell: currentCell, reason: reason
        )
    }
}
