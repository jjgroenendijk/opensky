/// What the world adapters use of `PlayerFirstPersonRig`.
public protocol PlayerFirstPersonRigPort: AnyObject {
    associatedtype PlayerAnimationPlayback: PlayerAnimationPlaybackPort
    var animation: PlayerAnimationPlayback { get }
}
