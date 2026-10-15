// Transform, draw delta, readout and persistence projections for one mover.

import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

extension NPCMover {
    public var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: controller.feetPosition,
            rotation: SIMD3(
                authoredPlacement.rotation.x, authoredPlacement.rotation.y,
                NPCYawMath.heading(fromYaw: yaw)
            ),
            scale: scale
        )
    }

    public var instanceDelta: float4x4 {
        NPCDrawDelta.from(drawn: authoredPlacement, to: transform, scale: scale)
    }

    /// Moving along its heading at its gait's speed, toward the next waypoint.
    public var motionFacts: ReferenceMotionFacts {
        let transform = transform
        let target = state == .moving && path.waypoints.indices.contains(waypointIndex)
            ? path.waypoints[waypointIndex] : nil
        let gaitSpeed = speed(of: gait)
        let heading = transform.rotation.z
        return ReferenceMotionFacts(
            position: transform.position,
            rotation: transform.rotation,
            velocity: SIMD3(sin(heading), cos(heading), 0) * (target == nil ? 0 : gaitSpeed),
            pathTarget: target,
            pathTargetSpeed: gaitSpeed,
            pathTurnSpeed: NPCMovementRuntime.maximumYawSpeed
        )
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
