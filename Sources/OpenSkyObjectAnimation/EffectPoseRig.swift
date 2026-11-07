// The bones of one posed model: each bone of the model's behaviour graph, then each node
// its own controllers move or its billboard turns that the graph does not name. Every bone
// is a root at its model-frame transform. See docs/rendering/visual-effects.md#posed-effect-models.

import Foundation
import OpenSkyBehavior
public import OpenSkyFormatsAnimation
public import OpenSkyFormatsMesh
public import simd

nonisolated public struct EffectPoseRig: Sendable {
    public let nodes: NodeControllerRig?
    public let graph: HKASkeleton?
    public let skeleton: HKASkeleton
    /// The bone each moved node poses, in `nodes.boneNodes` order.
    let nodeBones: [Int]
    /// The graph bone above each moved node, in `nodes.boneNodes` order, with its rest
    /// inverse; a moved node rides that bone when the graph moves it.
    let nodeAnchors: [(bone: Int, restInverse: simd_float4x4)?]

    /// Nil when nothing in the model moves.
    public init?(nodes: NodeControllerRig?, graph rig: HKASkeleton?) {
        let graphRest = rig.flatMap {
            try? SkeletonPoseMath.worldMatrices(skeleton: $0, localPoses: $0.referencePose)
        }
        let graph = graphRest == nil ? nil : rig
        let graphNames = (graph?.boneNames ?? []).map { $0.lowercased() }
        var names = graphNames
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
        nodeAnchors = (nodes?.boneNodes ?? []).map { node in
            guard
                let animation = nodes?.animation, let graphRest,
                let bone = Self.graphAncestor(of: node, in: animation, graphNames: graphNames)
            else { return nil }
            return (bone, graphRest[bone].inverse)
        }
        let graphBoneNames = graph?.boneNames ?? []
        let nodeNames = nodes?.skeleton.boneNames ?? []
        let ownNames = graphBoneNames + nodeNames.filter { name in
            !graphBoneNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        skeleton = HKASkeleton(
            name: nil,
            bones: ownNames.map { HKABone(name: $0, lockTranslation: false) },
            parentIndices: ownNames.map { _ in -1 },
            referencePose: rests.map { HKABonePose(transform: $0) }
        )
    }

    /// True when the rig adds bones the graph does not have.
    public var addsNodes: Bool {
        skeleton.bones.count > (graph?.bones.count ?? 0)
    }

    /// Each bone in the model frame: the graph's `local` pose, then the moved nodes on top.
    public func bonePoses(graph local: [HKABonePose], animator: NIFNodeAnimator?) -> [HKABonePose] {
        var matrices = skeleton.referencePose.map(SkeletonPoseMath.localMatrix)
        var graphMoved = false
        if
            let graph, !local.isEmpty,
            let posed = try? SkeletonPoseMath.worldMatrices(skeleton: graph, localPoses: local)
        {
            for (index, matrix) in posed.enumerated() where index < matrices.count {
                matrices[index] = matrix
            }
            graphMoved = true
        }
        if let nodes, let animator {
            for (index, node) in nodes.boneNodes.enumerated() {
                var matrix = animator.modelTransform(of: node).matrix
                if
                    graphMoved, nodeBones[index] >= (graph?.bones.count ?? 0),
                    let anchor = nodeAnchors[index]
                {
                    matrix = matrices[anchor.bone] * anchor.restInverse * matrix
                }
                matrices[nodeBones[index]] = matrix
            }
        }
        return matrices.map { HKABonePose(transform: $0) }
    }

    /// Each bone's change from its rest in the model frame, by lowercased name.
    public func nodeDeltas(_ poses: [HKABonePose]) -> [String: float4x4] {
        Self.deltas(skeleton: skeleton, poses: poses)
    }

    /// Each root bone's change from its rest, by lowercased name; a bone at rest is left out.
    public static func deltas(skeleton: HKASkeleton, poses: [HKABonePose]) -> [String: float4x4] {
        var deltas: [String: float4x4] = [:]
        for (index, pose) in poses.enumerated() where index < skeleton.bones.count {
            let rest = SkeletonPoseMath.localMatrix(skeleton.referencePose[index])
            let delta = SkeletonPoseMath.localMatrix(pose) * rest.inverse
            guard !Self.isIdentity(delta) else { continue }
            deltas[skeleton.bones[index].name.lowercased()] = delta
        }
        return deltas
    }

    private static func isIdentity(_ matrix: float4x4) -> Bool {
        let difference = matrix - matrix_identity_float4x4
        return [
            difference.columns.0,
            difference.columns.1,
            difference.columns.2,
            difference.columns.3
        ].allSatisfy { simd_reduce_max(simd_abs($0)) < 1e-5 }
    }

    /// The nearest node above `node` that the graph names. The step limit stops a cycle.
    private static func graphAncestor(
        of node: Int, in animation: NIFNodeAnimation, graphNames: [String]
    ) -> Int? {
        var current = animation.nodes[node].parent
        var steps = 0
        while let index = current, steps < 64 {
            if
                let name = animation.nodes[index].name?.lowercased(),
                let bone = graphNames.firstIndex(of: name)
            {
                return bone
            }
            current = animation.nodes[index].parent
            steps += 1
        }
        return nil
    }
}
