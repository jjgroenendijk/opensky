// The posed bones of a running object graph, for trap contact and the agent readout.

import OpenSkyActorPresentation
import OpenSkyBehavior
import simd

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
        return try? SkeletonPoseMath.worldMatrices(
            skeleton: entry.object.asset.skeleton, localPoses: entry.object.pose.bones
        )
    }

    /// The references that run a graph now.
    public var runningReferences: [UInt32] {
        running.keys.sorted()
    }
}
