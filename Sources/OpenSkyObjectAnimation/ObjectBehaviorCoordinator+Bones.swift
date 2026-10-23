// The bone positions of a running object graph, for trap contact.

import OpenSkyActorPresentation
import OpenSkyBehavior
import simd

extension ObjectBehaviorCoordinator {
    /// Each bone's origin in the object's own space, from the pose last published.
    /// Nil when `reference` runs no graph.
    public func bonePositions(of reference: UInt32) -> [SIMD3<Float>]? {
        guard let entry = running[reference] else { return nil }
        let skeleton = entry.object.asset.skeleton
        guard
            let matrices = try? SkeletonPoseMath.worldMatrices(
                skeleton: skeleton, localPoses: entry.object.pose.bones
            )
        else { return nil }
        return matrices.map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
    }

    /// The references that run a graph now.
    public var runningReferences: [UInt32] {
        running.keys.sorted()
    }
}
