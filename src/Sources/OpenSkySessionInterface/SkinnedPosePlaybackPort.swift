public import OpenSkyFormatsAnimation
public import OpenSkyWorldInterface
public import simd

/// What the world adapters use of `SkinnedPosePlayback`.
public protocol SkinnedPosePlaybackPort: AnyObject {
    var animatedBoneMatrices: [float4x4]? { get }
    var animatedBonesByName: [String: float4x4]? { get }
    var pose: SkinnedPoseBuffer { get }
    func setRagdollBones(_ bones: [String: float4x4])
    var skeleton: HKASkeleton { get }

    var lastUpdatedBoneCount: Int { get }
}
