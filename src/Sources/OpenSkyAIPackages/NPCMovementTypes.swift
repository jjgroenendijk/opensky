// Public values and the control seam for graph-agnostic NPC locomotion.
// The path follower owns travel; animation and combat consume
// the same intent without becoming movement authorities.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// The rigid move from where the cell build drew an actor to where it stands now.
/// The renderer applies it to the actor's baked instance, so nothing rebuilds.
nonisolated enum NPCDrawDelta {
    static func from(
        drawn: PlacedReference.Placement,
        to current: ReferenceTransformOverride,
        scale: Float
    ) -> float4x4 {
        let built = MatrixMath.placement(
            position: drawn.position, rotation: drawn.rotation, scale: scale
        )
        let live = MatrixMath.placement(
            position: current.position, rotation: current.rotation, scale: scale
        )
        return live * built.inverse
    }
}

nonisolated public struct NPCMovementPersistence: Equatable, Sendable {
    public let actor: ReferenceKey
    public let transform: ReferenceTransformOverride
    public let cell: CellSceneLocation?
    public let reason: NPCMovementSettleReason
}
