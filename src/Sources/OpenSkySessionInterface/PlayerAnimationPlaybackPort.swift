public import OpenSkyFormatsAnimation
public import OpenSkyWorldInterface
public import simd

/// What the world adapters use of `PlayerAnimationPlayback`.
public protocol PlayerAnimationPlaybackPort: AnyObject {
    var animatedBoneMatrices: [float4x4]? { get }
    var animatedBonesByName: [String: float4x4]? { get }
    var pose: PlayerPoseBuffer { get }
    func setRagdollBones(_ bones: [String: float4x4])
    var skeleton: HKASkeleton { get }

    var lastUpdatedBoneCount: Int { get }
}
