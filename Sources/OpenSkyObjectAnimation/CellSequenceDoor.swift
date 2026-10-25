import OpenSkyActorPresentation

/// One sequence door a cell drew, posed through its buffer.
nonisolated public struct CellSequenceDoor: Sendable {
    public let reference: UInt32
    public let rig: SequenceDoorRig
    public let pose: PlayerPoseBuffer

    public init(
        reference: UInt32, rig: SequenceDoorRig, pose: PlayerPoseBuffer
    ) {
        self.reference = reference
        self.rig = rig
        self.pose = pose
    }
}
