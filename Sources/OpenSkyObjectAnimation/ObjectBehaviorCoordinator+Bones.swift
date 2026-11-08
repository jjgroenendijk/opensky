// The posed bones of a running object graph, for trap contact and the agent readout.

import Foundation
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
public import OpenSkyFormatsCore
import OpenSkyWorldInterface
public import simd

extension ObjectBehaviorCoordinator {
    /// Points on the object's moving parts in its own space, from the pose last
    /// published. Nil when `reference` runs no graph.
    public func contactPositions(of reference: UInt32) -> [SIMD3<Float>]? {
        guard let shape = running[reference]?.object.contactShape else { return nil }
        return boneMatrices(of: reference).map(shape.positions(posed:))
    }

    /// Each bone's transform in the object's own space, from the pose last published.
    public func boneMatrices(of reference: UInt32) -> [simd_float4x4]? {
        guard let entry = running[reference] else { return nil }
        let local = entry.object.nodes == nil ? entry.object.pose.bones : entry.graphBones
        return attempt {
            try SkeletonPoseMath.worldMatrices(
                skeleton: entry.object.asset.skeleton, localPoses: local
            )
        }
    }

    /// One named bone in the object's own space, from the pose last published.
    public func bone(of reference: UInt32, named name: String) -> PosedBone? {
        guard
            let skeleton = running[reference]?.object.asset.skeleton,
            let index = skeleton.bones
                .firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
            let matrices = boneMatrices(of: reference)
        else { return nil }
        return PosedBone(index: index, matrices: matrices, parents: skeleton.parentIndices)
    }

    /// One named bone in the world, from the pose last published and the object's placement.
    public func worldBone(of reference: UInt32, named name: String) -> float4x4? {
        guard let entry = running[reference], let bone = bone(of: reference, named: name) else {
            return nil
        }
        return entry.object.placement * bone.model
    }

    /// The references that run a graph now.
    public var runningReferences: [UInt32] {
        running.keys.sorted()
    }
}
