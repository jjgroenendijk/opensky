// Pure skeleton pose math: local bone transforms to skeleton-world matrices.

import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import simd

nonisolated public enum SkeletonPoseError: Error, Equatable {
    case boneIndexOutOfRange(Int)
    case parentCycle(Int)
}

/// Pure pose math: local TRS -> skeleton-world matrices. Kept independent of
/// Metal + file loading so hierarchy and palette math are unit-testable.
nonisolated public enum SkeletonPoseMath: Sendable {
    public static func localMatrix(_ pose: HKABonePose) -> float4x4 {
        let rotation = float4x4(pose.rotation)
        let scale = float4x4(diagonal: SIMD4(pose.scale, 1))
        return MatrixMath.translation(pose.translation) * rotation * scale
    }

    public static func worldMatrices(
        skeleton: HKASkeleton,
        samples: [HKABoneTransformSample]
    ) throws -> [float4x4] {
        var local = skeleton.referencePose
        for sample in samples {
            guard local.indices.contains(sample.boneIndex) else {
                throw SkeletonPoseError.boneIndexOutOfRange(sample.boneIndex)
            }
            local[sample.boneIndex] = sample.pose
        }
        return try worldMatrices(skeleton: skeleton, localPoses: local)
    }

    /// Composes a dense local pose — one TRS per skeleton bone, which is what a
    /// behavior graph produces (`BehaviorPose.bones`) — through the parent
    /// chain. Bones past the end of `localPoses` keep their reference pose, so a
    /// graph bound to a rig with fewer bones than the skeleton still composes.
    public static func worldMatrices(
        skeleton: HKASkeleton,
        localPoses: [HKABonePose]
    ) throws -> [float4x4] {
        var local = skeleton.referencePose
        for index in local.indices where localPoses.indices.contains(index) {
            local[index] = localPoses[index]
        }
        var world = [float4x4?](repeating: nil, count: local.count)
        var visiting = Set<Int>()

        func resolve(_ index: Int) throws -> float4x4 {
            if let resolved = world[index] {
                return resolved
            }
            guard visiting.insert(index).inserted else {
                throw SkeletonPoseError.parentCycle(index)
            }
            defer { visiting.remove(index) }
            let own = localMatrix(local[index])
            let parent = skeleton.parentIndices[index]
            let resolved: float4x4
            if parent == -1 {
                resolved = own
            } else {
                guard world.indices.contains(parent) else {
                    throw SkeletonPoseError.boneIndexOutOfRange(parent)
                }
                resolved = try resolve(parent) * own
            }
            world[index] = resolved
            return resolved
        }

        return try local.indices.map(resolve)
    }
}
