/// What the world adapters use of `PlayerFirstPersonRig`.
public protocol PlayerFirstPersonRigPort: AnyObject {
    associatedtype SkinnedPosePlayback: SkinnedPosePlaybackPort
    var animation: SkinnedPosePlayback { get }
}
