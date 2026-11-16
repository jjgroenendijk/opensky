// Where and how big an actor draws, for parts that must line up with its body:
// ragdoll bodies and cape cloth.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyWorldState
public import simd

/// The actor's live pose once it moved, and its height on top of its scale. The plugin
/// placement alone would put the parts where the actor once stood.
nonisolated public struct ActorDrawnFrame: Sendable {
    public let scale: Float
    public let actorToWorld: float4x4

    public init(
        placed: PlacedReference.Placement, scale: Float,
        moved: ReferenceTransformOverride?, height: Float
    ) {
        let placement = moved?.placement ?? placed
        self.scale = (moved?.scale ?? scale) * height
        actorToWorld = MatrixMath.placement(
            position: placement.position, rotation: placement.rotation, scale: self.scale
        )
    }
}

extension CellStreamerPort {
    /// The drawn frame of a loaded actor placed at `placed` with its own `scale`.
    public func drawnFrame(
        of key: ReferenceKey, placed: PlacedReference.Placement, scale: Float
    ) -> ActorDrawnFrame {
        ActorDrawnFrame(
            placed: placed, scale: scale,
            moved: npcTransform(for: key), height: npcHeightScale?(key) ?? 1
        )
    }
}
