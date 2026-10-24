import OpenSkyActorPresentation
import OpenSkyBehavior

/// One animated object a cell drew, handed to `ObjectBehaviorCoordinator`.
nonisolated public struct CellAnimatedObject: Sendable {
    public let reference: UInt32
    public let asset: BehaviorProjectAsset
    public let pose: PlayerPoseBuffer
    public let contactShape: TrapContactShape

    public init(
        reference: UInt32, asset: BehaviorProjectAsset, pose: PlayerPoseBuffer,
        contactShape: TrapContactShape = .empty
    ) {
        self.reference = reference
        self.asset = asset
        self.pose = pose
        self.contactShape = contactShape
    }
}
