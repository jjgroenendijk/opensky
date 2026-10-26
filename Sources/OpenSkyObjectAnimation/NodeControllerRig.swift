// A placed mesh whose node controllers play on their own clock, such as a forge's
// bellows or a moth on a path. Each moved node is a root bone at its model-frame
// transform, as a sequence door's leaf is. See docs/engine/object-animation.md#node-controllers.

import Foundation
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd

nonisolated public struct NodeControllerRig: Sendable {
    public let animation: NIFNodeAnimation
    /// One root bone per moved node, at its rest transform in the model frame.
    public let skeleton: HKASkeleton
    /// The node each bone poses, in bone order.
    public let boneNodes: [Int]

    /// Nil for a mesh without an active controller on a named node. `lagOnly` keeps only
    /// the lag bones, for a mesh whose behaviour graph replaces its keyed controllers.
    public init?(file: NIFFile, lagOnly: Bool = false) throws {
        try self.init(animation: NIFNodeAnimation(file: file), lagOnly: lagOnly)
    }

    public init?(animation full: NIFNodeAnimation, lagOnly: Bool = false) {
        let animation = lagOnly ? NIFNodeAnimation(
            nodes: full.nodes, controllers: full.controllers.filter(\.isLagBone),
            boneLOD: full.boneLOD
        ) : full
        var names = Set<String>()
        var boneNodes: [Int] = []
        for controller in animation.playingControllers {
            guard
                let name = animation.nodes[controller.node].name?.lowercased(),
                names.insert(name).inserted
            else { continue }
            boneNodes.append(controller.node)
        }
        guard !boneNodes.isEmpty else { return nil }
        self.animation = animation
        self.boneNodes = boneNodes
        let rest = NIFNodeAnimator(animation: animation)
        skeleton = HKASkeleton(
            name: nil,
            bones: boneNodes.map {
                HKABone(name: animation.nodes[$0].name ?? "", lockTranslation: false)
            },
            parentIndices: boneNodes.map { _ in -1 },
            referencePose: boneNodes
                .map { HKABonePose(transform: rest.modelTransform(of: $0).matrix) }
        )
    }

    /// Each bone's model-frame pose from the animator's current node transforms.
    public func bonePoses(_ animator: NIFNodeAnimator) -> [HKABonePose] {
        boneNodes.map { HKABonePose(transform: animator.modelTransform(of: $0).matrix) }
    }
}

/// One mesh with node controllers that a cell drew, posed through its buffer.
nonisolated public struct CellNodeAnimation: Sendable {
    public let reference: UInt32
    public let rig: NodeControllerRig
    public let pose: PlayerPoseBuffer
    /// Where the cell placed the mesh; lag bones trail it and bone LOD measures from it.
    public let placement: float4x4

    public init(
        reference: UInt32,
        rig: NodeControllerRig,
        pose: PlayerPoseBuffer,
        placement: float4x4
    ) {
        self.reference = reference
        self.rig = rig
        self.pose = pose
        self.placement = placement
    }
}
