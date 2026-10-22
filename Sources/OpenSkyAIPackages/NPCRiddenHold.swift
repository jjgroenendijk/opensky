// A mount the player rides. The player's mount drive moves it, so the movement
// authority only records the pose, draws it, and persists it (docs/engine/riding.md).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// One actor the player steers. Its packages, walks, and turns wait until it is released.
nonisolated public struct NPCRiddenHold: Equatable, Sendable {
    public let actor: ReferenceKey
    public let formID: FormID
    /// Where the current cell build draws the actor, which the draw delta starts from.
    public internal(set) var authoredPlacement: PlacedReference.Placement
    public let scale: Float
    public private(set) var feetPosition: SIMD3<Float>
    /// Walk yaw, counter-clockwise from +X.
    public private(set) var yaw: Float
    public private(set) var cell: CellSceneLocation?

    public init(
        actor: ReferenceKey, formID: FormID, placement: PlacedReference.Placement,
        scale: Float, feetPosition: SIMD3<Float>, yaw: Float
    ) {
        self.actor = actor
        self.formID = formID
        authoredPlacement = placement
        self.scale = scale
        self.feetPosition = feetPosition
        self.yaw = yaw
    }

    /// Moves the mount. Returns true when it crossed into another cell.
    public mutating func move(
        to feet: SIMD3<Float>, yaw: Float, cell: CellSceneLocation?
    ) -> Bool {
        feetPosition = feet
        self.yaw = yaw
        let previous = self.cell
        self.cell = cell
        return previous != nil && cell != nil && previous != cell
    }

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

    public var readout: NPCMovementReadout {
        NPCMovementReadout(
            actor: actor, state: .ridden, feetPosition: feetPosition, yaw: yaw,
            waypointIndex: 0, waypointCount: 0, gait: .walk, repathCount: 0
        )
    }

    public func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(actor: actor, transform: transform, cell: cell, reason: reason)
    }
}
