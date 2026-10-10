// A sheathed weapon is the same skinned attachment as a drawn one. The pose moves
// its hand node onto the sheath node, so a draw or a sheathe needs no rebuild.
// See docs/engine/actor-resolution.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum WeaponSheathing {
    /// `pose` with each hand node in `nodes` placed on its sheath node. A drawn
    /// pose, or a skeleton without one of the two nodes, keeps that pair as is.
    public static func apply(
        _ nodes: [String: String], drawn: Bool, to pose: SkeletonPose
    ) -> SkeletonPose {
        guard !drawn, !nodes.isEmpty else { return pose }
        var matrices = pose.matrices
        for (hand, sheath) in nodes {
            guard
                let handIndex = pose.bones.index(of: hand),
                let sheathIndex = pose.bones.index(of: sheath),
                matrices.indices.contains(handIndex),
                matrices.indices.contains(sheathIndex)
            else { continue }
            matrices[handIndex] = pose.matrices[sheathIndex]
        }
        return SkeletonPose(bones: pose.bones, matrices: matrices)
    }
}

nonisolated extension ResolvedActorVisual {
    /// Hand node to sheath node for every equipped weapon. A worn shield has
    /// none: the vanilla skeleton has no back node for it, so it stays on the arm.
    public var sheathNodes: [String: String] {
        var nodes: [String: String] = [:]
        for attachment in attachments {
            guard let sheath = attachment.sheathBone else { continue }
            nodes[attachment.bone] = sheath
        }
        return nodes
    }
}
