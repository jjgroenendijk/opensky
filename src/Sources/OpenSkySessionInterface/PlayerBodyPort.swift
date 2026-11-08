public import OpenSkyFormatsESM
public import OpenSkyRendering
public import OpenSkyWorldInterface
public import simd

/// What the world adapters use of `PlayerBody`.
public protocol PlayerBodyPort: AnyObject {
    associatedtype PlayerAnimationPlayback: PlayerAnimationPlaybackPort
    var animation: PlayerAnimationPlayback { get }
    var assembly: ActorAssembly<ActorRenderAsset> { get }
    var feetArmatures: [FormID] { get }
    var transform: float4x4 { get }
}
