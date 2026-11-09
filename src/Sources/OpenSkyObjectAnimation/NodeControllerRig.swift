// A placed mesh whose node controllers play on their own clock, such as a forge's
// bellows or a moth on a path, or whose billboard nodes turn to the camera. Each moved
// node is a root bone at its model-frame transform, as a sequence door's leaf is.
// See docs/engine/object-animation.md#node-controllers.

import Foundation
import OpenSkyActorPresentation
import OpenSkyBehavior
public import OpenSkyFormatsAnimation
public import OpenSkyFormatsMesh
public import OpenSkyRendering
public import OpenSkyWorldInterface
public import simd

nonisolated public struct NodeControllerRig: Sendable {
    public let animation: NIFNodeAnimation
    /// One root bone per moved node, at its rest transform in the model frame.
    public let skeleton: HKASkeleton
    /// The node each bone poses, in bone order.
    public let boneNodes: [Int]
    /// The mesh's controller sequences, which a behaviour graph's sequence generators play.
    public let sequences: [NIFSequence]

    /// Nil for a mesh without an active controller or a billboard on a named node.
    /// `lagOnly` keeps only the lag bones and billboards, for a mesh whose behaviour
    /// graph replaces its keyed controllers.
    /// A `lagOnly` rig also poses the nodes the mesh's sequences move.
    public init?(file: NIFFile, lagOnly: Bool = false) throws {
        try self.init(
            animation: NIFNodeAnimation(file: file), lagOnly: lagOnly,
            sequences: lagOnly ? file.sequences() : []
        )
    }

    public init?(
        animation full: NIFNodeAnimation, lagOnly: Bool = false, sequences: [NIFSequence] = []
    ) {
        let animation = lagOnly ? NIFNodeAnimation(
            nodes: full.nodes, controllers: full.controllers.filter(\.isLagBone),
            boneLOD: full.boneLOD
        ) : full
        var names = Set<String>()
        var boneNodes: [Int] = []
        let moved = animation.playingControllers.map(\.node) + animation.billboardNodes
            + Self.sequenceNodes(sequences, in: animation)
        for node in moved {
            guard
                let name = animation.nodes[node].name?.lowercased(),
                names.insert(name).inserted
            else { continue }
            boneNodes.append(node)
        }
        guard !boneNodes.isEmpty else { return nil }
        self.animation = animation
        self.boneNodes = boneNodes
        self.sequences = sequences
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

    public func sequence(named name: String) -> NIFSequence? {
        sequences.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func sequenceNodes(
        _ sequences: [NIFSequence], in animation: NIFNodeAnimation
    ) -> [Int] {
        sequences.flatMap(\.tracks).compactMap { track in
            guard case let .node(name) = track.target, case .transform = track.channel
            else { return nil }
            return animation.nodes.firstIndex {
                $0.name?.caseInsensitiveCompare(name) == .orderedSame
            }
        }
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
    public let pose: SkinnedPoseBuffer
    /// Where the cell placed the mesh; lag bones trail it and bone LOD measures from it.
    public let placement: float4x4
    /// The mesh's particle systems; an emitter below a moved node moves with it.
    public var particles: [ParticlePlayback] = []

    public init(
        reference: UInt32,
        rig: NodeControllerRig,
        pose: SkinnedPoseBuffer,
        placement: float4x4
    ) {
        self.reference = reference
        self.rig = rig
        self.pose = pose
        self.placement = placement
    }
}
