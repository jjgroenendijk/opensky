public import OpenSkyActorPresentation
public import simd

/// One sequence door a cell drew, posed through its buffer.
nonisolated public struct CellSequenceDoor: Sendable {
    public enum Kind: Equatable, Sendable {
        /// Follows its saved open state.
        case door
        /// Swings open while the transition holds, and is never saved open.
        case loadDoor
        /// A container lid: open while the container menu shows this container.
        case containerLid
    }

    public let reference: UInt32
    public let rig: SequenceDoorRig
    public let pose: PlayerPoseBuffer
    /// The leaves plus the billboards and lag bones of the mesh, when it has any.
    public let nodes: EffectPoseRig?
    /// Where the door stands, so its billboards can turn to the camera.
    public let placement: float4x4
    public let kind: Kind

    public init(
        reference: UInt32, rig: SequenceDoorRig, pose: PlayerPoseBuffer,
        nodes: EffectPoseRig? = nil, placement: float4x4 = matrix_identity_float4x4,
        kind: Kind = .door
    ) {
        self.kind = kind
        self.reference = reference
        self.rig = rig
        self.pose = pose
        self.nodes = nodes
        self.placement = placement
    }
}
