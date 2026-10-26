// The bones of one posed effect model: each bone of the model's effect graph, then each
// node its own controllers move that the graph does not name. Every bone is a root at its
// model-frame transform. See docs/rendering/visual-effects.md#posed-effect-models.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd

nonisolated public struct EffectPoseRig: Sendable {
    public let nodes: NodeControllerRig?
    public let graph: HKASkeleton?
    public let skeleton: HKASkeleton
    /// The bone each moved node poses, in `nodes.boneNodes` order.
    let nodeBones: [Int]

    /// Nil when nothing in the model moves.
    public init?(nodes: NodeControllerRig?, graph rig: HKASkeleton?) {
        let graphRest = rig.flatMap {
            try? SkeletonPoseMath.worldMatrices(skeleton: $0, localPoses: $0.referencePose)
        }
        let graph = graphRest == nil ? nil : rig
        var names = (graph?.boneNames ?? []).map { $0.lowercased() }
        var rests = graphRest ?? []
        var nodeBones: [Int] = []
        let animator = nodes.map { NIFNodeAnimator(animation: $0.animation) }
        for (index, node) in (nodes?.boneNodes ?? []).enumerated() {
            let name = nodes?.skeleton.boneNames[index].lowercased() ?? ""
            if let known = names.firstIndex(of: name) {
                nodeBones.append(known)
                continue
            }
            nodeBones.append(names.count)
            names.append(name)
            rests.append(animator?.modelTransform(of: node).matrix ?? matrix_identity_float4x4)
        }
        guard !names.isEmpty else { return nil }
        self.nodes = nodes
        self.graph = graph
        self.nodeBones = nodeBones
        let graphNames = graph?.boneNames ?? []
        let nodeNames = nodes?.skeleton.boneNames ?? []
        let ownNames = graphNames + nodeNames.filter { name in
            !graphNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        skeleton = HKASkeleton(
            name: nil,
            bones: ownNames.map { HKABone(name: $0, lockTranslation: false) },
            parentIndices: ownNames.map { _ in -1 },
            referencePose: rests.map { HKABonePose(transform: $0) }
        )
    }

    /// Each bone in the model frame: the graph's `local` pose, then the moved nodes on top.
    public func bonePoses(graph local: [HKABonePose], animator: NIFNodeAnimator?) -> [HKABonePose] {
        var matrices = skeleton.referencePose.map(SkeletonPoseMath.localMatrix)
        if
            let graph, !local.isEmpty,
            let posed = try? SkeletonPoseMath.worldMatrices(skeleton: graph, localPoses: local)
        {
            for (index, matrix) in posed.enumerated() where index < matrices.count {
                matrices[index] = matrix
            }
        }
        if let nodes, let animator {
            for (index, node) in nodes.boneNodes.enumerated() {
                matrices[nodeBones[index]] = animator.modelTransform(of: node).matrix
            }
        }
        return matrices.map { HKABonePose(transform: $0) }
    }
}
