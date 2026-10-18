import OpenSkyActorPresentation

/// One animated object a cell drew, handed to `ObjectBehaviorCoordinator`.
nonisolated public struct CellAnimatedObject: Sendable {
    public let reference: UInt32
    public let asset: ObjectBehaviorAsset
    public let pose: PlayerPoseBuffer

    public init(reference: UInt32, asset: ObjectBehaviorAsset, pose: PlayerPoseBuffer) {
        self.reference = reference
        self.asset = asset
        self.pose = pose
    }
}
