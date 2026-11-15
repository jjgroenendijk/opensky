public import OpenSkyFormatsESM
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyWorldInterface
public import simd

/// What the world adapters use of `PlayerBody`.
public protocol PlayerBodyPort: AnyObject {
    associatedtype SkinnedPosePlayback: SkinnedPosePlaybackPort
    var animation: SkinnedPosePlayback { get }
    var assembly: ActorAssembly<ActorRenderAsset> { get }
    /// The cape cloth on the third-person body, when the body wears one.
    var clothAnimation: (any RenderAnimation)? { get }
    var feetArmatures: [FormID] { get }
    var transform: float4x4 { get }
}
