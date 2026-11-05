import OpenSkyActorPresentation
import OpenSkyBehavior
import simd

/// One animated object a cell drew, handed to `ObjectBehaviorCoordinator`.
nonisolated public struct CellAnimatedObject: Sendable {
    public let reference: UInt32
    public let asset: BehaviorProjectAsset
    public let pose: PlayerPoseBuffer
    public let contactShape: TrapContactShape
    /// The graph's bones plus the billboards and lag bones of the mesh, when it has any.
    /// The pose buffer then holds this rig's model-frame bones, not the graph's.
    public let nodes: EffectPoseRig?
    /// Where the object stands, so its billboards can turn to the camera.
    public let placement: float4x4

    public init(
        reference: UInt32, asset: BehaviorProjectAsset, pose: PlayerPoseBuffer,
        contactShape: TrapContactShape = .empty, nodes: EffectPoseRig? = nil,
        placement: float4x4 = matrix_identity_float4x4
    ) {
        self.reference = reference
        self.asset = asset
        self.pose = pose
        self.contactShape = contactShape
        self.nodes = nodes
        self.placement = placement
    }
}
