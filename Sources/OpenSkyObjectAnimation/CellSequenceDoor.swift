import OpenSkyActorPresentation
import simd

/// One sequence door a cell drew, posed through its buffer.
nonisolated public struct CellSequenceDoor: Sendable {
    public let reference: UInt32
    public let rig: SequenceDoorRig
    public let pose: PlayerPoseBuffer
    /// The leaves plus the billboards and lag bones of the mesh, when it has any.
    public let nodes: EffectPoseRig?
    /// Where the door stands, so its billboards can turn to the camera.
    public let placement: float4x4

    public init(
        reference: UInt32, rig: SequenceDoorRig, pose: PlayerPoseBuffer,
        nodes: EffectPoseRig? = nil, placement: float4x4 = matrix_identity_float4x4
    ) {
        self.reference = reference
        self.rig = rig
        self.pose = pose
        self.nodes = nodes
        self.placement = placement
    }
}
