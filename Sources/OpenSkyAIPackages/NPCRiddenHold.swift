import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

nonisolated extension NPCRiddenHold {
    public var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: feetPosition,
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

    public func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(actor: actor, transform: transform, cell: cell, reason: reason)
    }
}
