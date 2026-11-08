import Foundation
import OpenSkyBehavior
public import OpenSkyFormatsAnimation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
public import simd
import Synchronization

/// One worn armour addon model.
nonisolated public struct WornArmorAddon: Equatable, Sendable {
    public let armature: FormID
    public let modelPath: String
    public let slots: BodySlots

    public init(armature: FormID, modelPath: String, slots: BodySlots = BodySlots()) {
        self.armature = armature
        self.modelPath = modelPath
        self.slots = slots
    }
}

nonisolated public final class ActorAnimationClip: Sendable {
    public let skeleton: HKASkeleton
    public let animation: HKASplineCompressedAnimation
    public let binding: HKAAnimationBinding
    /// The `.nif` this rig's skeleton came from, which also holds its ragdoll bodies
    /// and joints.
    public let skeletonMeshPath: String
    /// The skeleton's bone names, indexed once so skinning can map to bone order.
    public let boneIndex: SkeletonBoneIndex

    public init(
        skeleton: HKASkeleton,
        animation: HKASplineCompressedAnimation,
        binding: HKAAnimationBinding,
        skeletonMeshPath: String = ""
    ) {
        self.skeleton = skeleton
        self.animation = animation
        self.binding = binding
        self.skeletonMeshPath = skeletonMeshPath
        boneIndex = SkeletonBoneIndex(names: skeleton.boneNames)
    }

    /// The rig's bind pose as skeleton-world matrices, in bone order. The frame
    /// a ragdoll's bodies are authored against.
    public var bindWorldMatrices: [float4x4] {
        attempt {
            try SkeletonPoseMath.worldMatrices(
                skeleton: skeleton, localPoses: skeleton.referencePose
            )
        } ?? []
    }

    /// The pose at `time` as skeleton-world matrices in bone order, which is
    /// what a ragdoll hand-off reads. Nil where the clip cannot be sampled, the
    /// same condition `namedWorldTransforms(at:)` returns nil on.
    public func orderedWorldTransforms(at time: Float) -> [float4x4]? {
        guard let pose = worldPose(at: time) else { return nil }
        let bind = bindWorldMatrices
        return skeleton.boneNames.indices.map { index in
            // A repeated name poses as its first bone, as skinning reads it.
            let source = boneIndex.index(of: skeleton.boneNames[index]) ?? index
            if source < pose.matrices.count {
                return pose.matrices[source]
            }
            return bind.indices.contains(index) ? bind[index] : matrix_identity_float4x4
        }
    }

    public func namedWorldTransforms(at time: Float) -> [String: float4x4]? {
        worldPose(at: time)?.named
    }

    /// The pose at `time` in skeleton bone order. Nil where the clip cannot be sampled.
    public func worldPose(at time: Float) -> SkeletonPose? {
        guard animation.duration > 0 else { return nil }
        let sampleTime = time.truncatingRemainder(dividingBy: animation.duration)
        guard
            let samples = attempt({
                try animation.boneLocalTransforms(
                    at: sampleTime,
                    binding: binding
                )
            }),
            let world = attempt({
                try SkeletonPoseMath.worldMatrices(
                    skeleton: skeleton,
                    samples: samples
                )
            })
        else { return nil }
        return SkeletonPose(bones: boneIndex, matrices: world)
    }
}
