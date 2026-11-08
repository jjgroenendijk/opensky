public import OpenSkyFormatsCore
public import OpenSkyWorldInterface

/// What the world adapters use of `ActorAnimationPlayback`.
public protocol ActorAnimationPlaybackPort: AnyObject {
    var armorAddons: [WornArmorAddon] { get }
    var clip: ActorAnimationClip { get }
    func hasBone(named bone: String) -> Bool
    var lagBoneOffsets: [String: Float] { get }
    func play(_ clip: ActorAnimationClip, startingAt time: Float, forSeconds seconds: Float)
    func skeletonPose(at time: Float) -> SkeletonPose?
    var weaponsDrawn: Bool { get set }
}
